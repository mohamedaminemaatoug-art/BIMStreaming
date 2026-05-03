use std::path::PathBuf;

fn main() {
    let vcpkg_root = std::env::var("VCPKG_ROOT")
        .expect("VCPKG_ROOT must be set to your vcpkg installation directory");

    let triplet = "x64-windows-static";
    let lib_dir = format!("{}/installed/{}/lib", vcpkg_root, triplet);
    let include_dir = format!("{}/installed/{}/include", vcpkg_root, triplet);

    println!("cargo:rustc-link-search=native={}", lib_dir);
    println!("cargo:rustc-link-lib=static=vpx");
    // Windows system libs required by libvpx
    println!("cargo:rustc-link-lib=Ole32");
    println!("cargo:rustc-link-lib=User32");
    println!("cargo:rustc-link-lib=Winmm");

    println!("cargo:rerun-if-env-changed=VCPKG_ROOT");
    println!("cargo:rerun-if-changed=build.rs");

    let bindings = bindgen::Builder::default()
        .header(format!("{}/vpx/vpx_codec.h", include_dir))
        .header(format!("{}/vpx/vpx_encoder.h", include_dir))
        .header(format!("{}/vpx/vpx_decoder.h", include_dir))
        .header(format!("{}/vpx/vp8cx.h", include_dir))
        .header(format!("{}/vpx/vp8dx.h", include_dir))
        .header(format!("{}/vpx/vpx_image.h", include_dir))
        .clang_arg(format!("-I{}", include_dir))
        .allowlist_function("vpx_codec_.*")
        .allowlist_function("vpx_img_.*")
        .allowlist_type("vpx_.*")
        .allowlist_type("vp8.*")
        .allowlist_var("VPX_.*")
        .allowlist_var("VP8.*")
        .allowlist_var("VP9.*")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .generate()
        .expect("Unable to generate VPX bindings");

    let out_path = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("vpx_bindings.rs"))
        .expect("Couldn't write VPX bindings");
}
