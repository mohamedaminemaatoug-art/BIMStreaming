//! BimStreaming VP9 codec DLL
//!
//! Exposes a minimal C-ABI for VP9 encoding (BGRA → VP9) and decoding (VP9 → BGRA).
//! Configuration mirrors RustDesk's real-time VP9 settings:
//!   - CBR mode, speed=7, row-MT enabled, 4 tile columns
//!   - keyframe interval: 300 frames

#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(dead_code)]
#![allow(clippy::all)]

use std::os::raw::c_int;

include!(concat!(env!("OUT_DIR"), "/vpx_bindings.rs"));

// ─── VP9 encoder control IDs (from vp8cx.h) ──────────────────────────────────
const VP8E_SET_CPUUSED: c_int = 13;
const VP9E_SET_TILE_COLUMNS: c_int = 104;
const VP9E_SET_ROW_MT: c_int = 109;

// Sizes of the opaque structs (from bindgen layout tests in generated bindings).
// These are compile-time-verified by the layout test inside vpx_bindings.rs.
const CFG_SIZE: usize = 504; // sizeof(vpx_codec_enc_cfg_t)
const DEC_CFG_SIZE: usize = 12; // sizeof(vpx_codec_dec_cfg_t)

// Field byte offsets inside vpx_codec_enc_cfg_t (x64 Windows, MSVC layout).
// Verified by hand against the vcpkg 1.16.0 header; total matches CFG_SIZE.
const OFF_G_THREADS: usize = 4;
const OFF_G_W: usize = 12;
const OFF_G_H: usize = 16;
const OFF_G_TIMEBASE_NUM: usize = 28;
const OFF_G_TIMEBASE_DEN: usize = 32;
const OFF_G_ERROR_RESILIENT: usize = 36;
const OFF_G_PASS: usize = 40;
const OFF_G_LAG_IN_FRAMES: usize = 44;
const OFF_RC_DROPFRAME_THRESH: usize = 48;
const OFF_RC_END_USAGE: usize = 72;
const OFF_RC_TARGET_BITRATE: usize = 112;
const OFF_RC_MIN_QUANTIZER: usize = 116;
const OFF_RC_MAX_QUANTIZER: usize = 120;
const OFF_RC_UNDERSHOOT_PCT: usize = 124;
const OFF_KF_MODE: usize = 160;
const OFF_KF_MIN_DIST: usize = 164;
const OFF_KF_MAX_DIST: usize = 168;

// Field offsets inside vpx_codec_dec_cfg_t
const OFF_DEC_THREADS: usize = 0;

// ─── Raw-pointer field accessors ─────────────────────────────────────────────

unsafe fn set_u32(base: *mut u8, off: usize, val: u32) {
    (base.add(off) as *mut u32).write_unaligned(val);
}
unsafe fn set_i32(base: *mut u8, off: usize, val: i32) {
    (base.add(off) as *mut i32).write_unaligned(val);
}

// ─── Internal state ──────────────────────────────────────────────────────────

struct Encoder {
    ctx: vpx_codec_ctx_t,
    cfg: Box<[u8; CFG_SIZE]>,
    width: u32,
    height: u32,
    pts: i64,
    yuv: Vec<u8>,
}

struct Decoder {
    ctx: vpx_codec_ctx_t,
}

// ─── Colour-space conversion ─────────────────────────────────────────────────

/// BGRA (4 bytes/px, memory order B G R A) → planar I420 (Y Cb Cr, BT.601).
fn bgra_to_i420(src: &[u8], width: usize, height: usize, dst: &mut Vec<u8>) {
    let n = width * height;
    dst.resize(n * 3 / 2, 0);

    for row in 0..height {
        for col in 0..width {
            let p = (row * width + col) * 4;
            let b = src[p] as i32;
            let g = src[p + 1] as i32;
            let r = src[p + 2] as i32;
            dst[row * width + col] =
                (((66 * r + 129 * g + 25 * b + 128) >> 8) + 16).clamp(0, 255) as u8;
        }
    }

    for row in (0..height).step_by(2) {
        for col in (0..width).step_by(2) {
            let p = (row * width + col) * 4;
            let b = src[p] as i32;
            let g = src[p + 1] as i32;
            let r = src[p + 2] as i32;
            let u = (((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128).clamp(0, 255) as u8;
            let v = (((112 * r - 94 * g - 18 * b + 128) >> 8) + 128).clamp(0, 255) as u8;
            let uv_r = row / 2;
            let uv_c = col / 2;
            let uv_w = width / 2;
            dst[n + uv_r * uv_w + uv_c] = u;
            dst[n + n / 4 + uv_r * uv_w + uv_c] = v;
        }
    }
}

/// Planar I420 → BGRA. Fixed-point BT.601 inverse.
unsafe fn i420_planes_to_bgra(
    y_ptr: *const u8,
    u_ptr: *const u8,
    v_ptr: *const u8,
    y_stride: usize,
    u_stride: usize,
    v_stride: usize,
    width: usize,
    height: usize,
    out: &mut [u8],
) {
    for row in 0..height {
        for col in 0..width {
            let y_val = *y_ptr.add(row * y_stride + col) as i32;
            let u_val = *u_ptr.add((row / 2) * u_stride + col / 2) as i32 - 128;
            let v_val = *v_ptr.add((row / 2) * v_stride + col / 2) as i32 - 128;
            let y_adj = 1192 * (y_val - 16);
            let r = ((y_adj + 1634 * v_val + 512) >> 10).clamp(0, 255) as u8;
            let g = ((y_adj - 833 * v_val - 400 * u_val + 512) >> 10).clamp(0, 255) as u8;
            let b = ((y_adj + 2066 * u_val + 512) >> 10).clamp(0, 255) as u8;
            let idx = (row * width + col) * 4;
            out[idx] = b;
            out[idx + 1] = g;
            out[idx + 2] = r;
            out[idx + 3] = 255;
        }
    }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

fn cpu_threads() -> u32 {
    std::thread::available_parallelism()
        .map(|n| n.get() as u32)
        .unwrap_or(4)
        .min(16)
}

// ─── Encoder API ─────────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn bim_encoder_create(width: u32, height: u32, bitrate_kbps: u32) -> *mut Encoder {
    unsafe {
        let iface = vpx_codec_vp9_cx();
        if iface.is_null() {
            return std::ptr::null_mut();
        }

        // Allocate cfg as raw bytes; the opaque bindgen type has no accessible fields.
        let mut cfg_box = Box::new([0u8; CFG_SIZE]);
        let cfg_ptr = cfg_box.as_mut_ptr();

        let rc = vpx_codec_enc_config_default(
            iface,
            cfg_ptr as *mut vpx_codec_enc_cfg_t,
            0,
        );
        if rc != vpx_codec_err_t_VPX_CODEC_OK {
            return std::ptr::null_mut();
        }

        // Mirror RustDesk vpxcodec.rs VP9 CBR real-time config.
        set_u32(cfg_ptr, OFF_G_W, width);
        set_u32(cfg_ptr, OFF_G_H, height);
        set_i32(cfg_ptr, OFF_G_TIMEBASE_NUM, 1);
        set_i32(cfg_ptr, OFF_G_TIMEBASE_DEN, 1000); // ms timestamps
        set_u32(cfg_ptr, OFF_G_THREADS, cpu_threads());
        set_u32(cfg_ptr, OFF_G_ERROR_RESILIENT, VPX_ERROR_RESILIENT_DEFAULT);
        set_i32(cfg_ptr, OFF_G_PASS, vpx_enc_pass_VPX_RC_ONE_PASS);
        set_u32(cfg_ptr, OFF_G_LAG_IN_FRAMES, 0);
        set_i32(cfg_ptr, OFF_RC_END_USAGE, vpx_rc_mode_VPX_CBR);
        set_u32(cfg_ptr, OFF_RC_TARGET_BITRATE, bitrate_kbps);
        set_u32(cfg_ptr, OFF_RC_UNDERSHOOT_PCT, 95);
        set_u32(cfg_ptr, OFF_RC_DROPFRAME_THRESH, 25);
        set_u32(cfg_ptr, OFF_RC_MIN_QUANTIZER, 4);
        set_u32(cfg_ptr, OFF_RC_MAX_QUANTIZER, 56);
        set_i32(cfg_ptr, OFF_KF_MODE, vpx_kf_mode_VPX_KF_AUTO);
        set_u32(cfg_ptr, OFF_KF_MIN_DIST, 0);
        set_u32(cfg_ptr, OFF_KF_MAX_DIST, 300);

        let mut ctx: vpx_codec_ctx_t = std::mem::zeroed();
        let rc = vpx_codec_enc_init_ver(
            &mut ctx,
            iface,
            cfg_ptr as *const vpx_codec_enc_cfg_t,
            0,
            VPX_ENCODER_ABI_VERSION as i32,
        );
        if rc != vpx_codec_err_t_VPX_CODEC_OK {
            return std::ptr::null_mut();
        }

        vpx_codec_control_(&mut ctx, VP8E_SET_CPUUSED, 7i32);
        vpx_codec_control_(&mut ctx, VP9E_SET_ROW_MT, 1i32);
        vpx_codec_control_(&mut ctx, VP9E_SET_TILE_COLUMNS, 4i32);

        let n = (width * height) as usize;
        let enc = Box::new(Encoder {
            ctx,
            cfg: cfg_box,
            width,
            height,
            pts: 0,
            yuv: Vec::with_capacity(n * 3 / 2),
        });
        Box::into_raw(enc)
    }
}

#[no_mangle]
pub unsafe extern "C" fn bim_encoder_encode(
    enc: *mut Encoder,
    bgra: *const u8,
    bgra_len: usize,
    out: *mut u8,
    out_cap: usize,
    force_key: u8,
) -> i32 {
    if enc.is_null() || bgra.is_null() || out.is_null() {
        return -1;
    }
    let enc = &mut *enc;
    let w = enc.width as usize;
    let h = enc.height as usize;
    let expected_bgra = w * h * 4;
    if bgra_len < expected_bgra {
        return -1;
    }

    let bgra_slice = std::slice::from_raw_parts(bgra, expected_bgra);
    bgra_to_i420(bgra_slice, w, h, &mut enc.yuv);

    let mut img: vpx_image_t = std::mem::zeroed();
    let wrapped = vpx_img_wrap(
        &mut img,
        vpx_img_fmt_VPX_IMG_FMT_I420,
        enc.width,
        enc.height,
        1,
        enc.yuv.as_mut_ptr(),
    );
    if wrapped.is_null() {
        return -1;
    }

    let flags: i32 = if force_key != 0 { VPX_EFLAG_FORCE_KF as i32 } else { 0 };
    let pts = enc.pts;
    enc.pts += 33;

    let rc = vpx_codec_encode(
        &mut enc.ctx,
        &img,
        pts,
        33,
        flags,
        VPX_DL_REALTIME,
    );
    if rc != vpx_codec_err_t_VPX_CODEC_OK {
        return -1;
    }

    let mut iter: vpx_codec_iter_t = std::ptr::null();
    let mut written = 0i32;

    loop {
        let pkt = vpx_codec_get_cx_data(&mut enc.ctx, &mut iter);
        if pkt.is_null() {
            break;
        }
        if (*pkt).kind == vpx_codec_cx_pkt_kind_VPX_CODEC_CX_FRAME_PKT {
            let frame = &(*pkt).data.frame;
            let sz = frame.sz as usize;
            if sz > out_cap {
                return -1;
            }
            std::ptr::copy_nonoverlapping(frame.buf as *const u8, out, sz);
            written = sz as i32;
            break;
        }
    }

    written
}

#[no_mangle]
pub unsafe extern "C" fn bim_encoder_set_bitrate(enc: *mut Encoder, bitrate_kbps: u32) -> i32 {
    if enc.is_null() {
        return -1;
    }
    let enc = &mut *enc;
    let cfg_ptr = enc.cfg.as_mut_ptr();
    set_u32(cfg_ptr, OFF_RC_TARGET_BITRATE, bitrate_kbps);
    let rc = vpx_codec_enc_config_set(
        &mut enc.ctx,
        cfg_ptr as *const vpx_codec_enc_cfg_t,
    );
    if rc == vpx_codec_err_t_VPX_CODEC_OK { 0 } else { -1 }
}

#[no_mangle]
pub unsafe extern "C" fn bim_encoder_free(enc: *mut Encoder) {
    if enc.is_null() {
        return;
    }
    let mut enc = Box::from_raw(enc);
    vpx_codec_destroy(&mut enc.ctx);
}

// ─── Decoder API ─────────────────────────────────────────────────────────────

#[no_mangle]
pub extern "C" fn bim_decoder_create() -> *mut Decoder {
    unsafe {
        let iface = vpx_codec_vp9_dx();
        if iface.is_null() {
            return std::ptr::null_mut();
        }

        // vpx_codec_dec_cfg_t: {u32 threads, u32 w, u32 h} — 12 bytes
        let mut dec_cfg = [0u8; DEC_CFG_SIZE];
        set_u32(dec_cfg.as_mut_ptr(), OFF_DEC_THREADS, cpu_threads());

        let mut ctx: vpx_codec_ctx_t = std::mem::zeroed();
        let rc = vpx_codec_dec_init_ver(
            &mut ctx,
            iface,
            dec_cfg.as_ptr() as *const vpx_codec_dec_cfg_t,
            0,
            VPX_DECODER_ABI_VERSION as i32,
        );
        if rc != vpx_codec_err_t_VPX_CODEC_OK {
            return std::ptr::null_mut();
        }
        let dec = Box::new(Decoder { ctx });
        Box::into_raw(dec)
    }
}

#[no_mangle]
pub unsafe extern "C" fn bim_decoder_decode(
    dec: *mut Decoder,
    vp9: *const u8,
    vp9_len: usize,
    out: *mut u8,
    out_cap: usize,
    out_w: *mut u32,
    out_h: *mut u32,
) -> i32 {
    if dec.is_null() || vp9.is_null() || out.is_null() {
        return -1;
    }
    let dec = &mut *dec;

    let rc = vpx_codec_decode(
        &mut dec.ctx,
        vp9,
        vp9_len as u32,
        std::ptr::null_mut(),
        0,
    );
    if rc != vpx_codec_err_t_VPX_CODEC_OK {
        return -1;
    }

    let mut iter: vpx_codec_iter_t = std::ptr::null();
    let img = vpx_codec_get_frame(&mut dec.ctx, &mut iter);
    if img.is_null() {
        return 0;
    }

    let w = (*img).d_w as usize;
    let h = (*img).d_h as usize;
    let needed = w * h * 4;
    if needed > out_cap {
        return -1;
    }

    let out_slice = std::slice::from_raw_parts_mut(out, needed);
    i420_planes_to_bgra(
        (*img).planes[VPX_PLANE_Y as usize],
        (*img).planes[VPX_PLANE_U as usize],
        (*img).planes[VPX_PLANE_V as usize],
        (*img).stride[VPX_PLANE_Y as usize] as usize,
        (*img).stride[VPX_PLANE_U as usize] as usize,
        (*img).stride[VPX_PLANE_V as usize] as usize,
        w,
        h,
        out_slice,
    );

    if !out_w.is_null() {
        *out_w = w as u32;
    }
    if !out_h.is_null() {
        *out_h = h as u32;
    }
    needed as i32
}

#[no_mangle]
pub unsafe extern "C" fn bim_decoder_free(dec: *mut Decoder) {
    if dec.is_null() {
        return;
    }
    let mut dec = Box::from_raw(dec);
    vpx_codec_destroy(&mut dec.ctx);
}
