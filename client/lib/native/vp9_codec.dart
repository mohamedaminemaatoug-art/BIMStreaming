import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ─── C type aliases ──────────────────────────────────────────────────────────

typedef _EncoderCreateC = Pointer Function(Uint32, Uint32, Uint32);
typedef _EncoderCreateDart = Pointer Function(int, int, int);

typedef _EncoderEncodeC = Int32 Function(
    Pointer, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Uint8);
typedef _EncoderEncodeDart = int Function(
    Pointer, Pointer<Uint8>, int, Pointer<Uint8>, int, int);

typedef _EncoderSetBitrateC = Int32 Function(Pointer, Uint32);
typedef _EncoderSetBitrateDart = int Function(Pointer, int);

typedef _EncoderFreeC = Void Function(Pointer);
typedef _EncoderFreeDart = void Function(Pointer);

typedef _DecoderCreateC = Pointer Function();
typedef _DecoderCreateDart = Pointer Function();

typedef _DecoderDecodeC = Int32 Function(
    Pointer, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint32>, Pointer<Uint32>);
typedef _DecoderDecodeDart = int Function(
    Pointer, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint32>);

typedef _DecoderFreeC = Void Function(Pointer);
typedef _DecoderFreeDart = void Function(Pointer);

// ─── DLL loader ─────────────────────────────────────────────────────────────

DynamicLibrary _loadCodecLib() {
  if (Platform.isWindows) {
    return DynamicLibrary.open('bimstreaming_codec.dll');
  }
  throw UnsupportedError('bimstreaming_codec is Windows-only');
}

DynamicLibrary? _lib;
DynamicLibrary get _codecLib => _lib ??= _loadCodecLib();

// ─── VP9 Encoder ─────────────────────────────────────────────────────────────

class Vp9Encoder {
  final Pointer _handle;
  final int width;
  final int height;

  // Pre-allocated persistent buffers — no malloc per frame.
  late final Pointer<Uint8> _inBuf;
  late final int _inCap;
  late final Pointer<Uint8> _outBuf;
  late final int _outCap;

  late final _EncoderEncodeDart _encode;
  late final _EncoderSetBitrateDart _setBitrate;
  late final _EncoderFreeDart _free;

  Vp9Encoder._(this._handle, this.width, this.height) {
    _inCap  = width * height * 4;       // BGRA input
    _outCap = width * height * 2;       // VP9 output upper bound
    _inBuf  = malloc.allocate<Uint8>(_inCap);
    _outBuf = malloc.allocate<Uint8>(_outCap);

    _encode = _codecLib
        .lookupFunction<_EncoderEncodeC, _EncoderEncodeDart>('bim_encoder_encode');
    _setBitrate = _codecLib
        .lookupFunction<_EncoderSetBitrateC, _EncoderSetBitrateDart>(
            'bim_encoder_set_bitrate');
    _free = _codecLib
        .lookupFunction<_EncoderFreeC, _EncoderFreeDart>('bim_encoder_free');
  }

  static Vp9Encoder? create(int width, int height, {int bitrateKbps = 1500}) {
    final fn = _codecLib
        .lookupFunction<_EncoderCreateC, _EncoderCreateDart>('bim_encoder_create');
    final handle = fn(width, height, bitrateKbps);
    if (handle == nullptr) return null;
    return Vp9Encoder._(handle, width, height);
  }

  /// Encode a BGRA frame. [bgraPixels] must be exactly `width * height * 4` bytes.
  Uint8List? encode(Uint8List bgraPixels, {bool forceKeyframe = false}) {
    if (bgraPixels.length < width * height * 4) return null;

    // Copy into the persistent input buffer — no per-frame malloc.
    _inBuf.asTypedList(_inCap).setAll(0, bgraPixels);

    final written = _encode(
      _handle,
      _inBuf,
      _inCap,
      _outBuf,
      _outCap,
      forceKeyframe ? 1 : 0,
    );
    if (written <= 0) return null;
    return Uint8List.fromList(_outBuf.asTypedList(written));
  }

  void setBitrate(int bitrateKbps) => _setBitrate(_handle, bitrateKbps);

  void dispose() {
    _free(_handle);
    malloc.free(_inBuf);
    malloc.free(_outBuf);
  }
}

// ─── VP9 Decoder ─────────────────────────────────────────────────────────────

class Vp9Decoder {
  final Pointer _handle;

  // Pre-allocated persistent buffers — no per-frame malloc.
  Pointer<Uint8> _inBuf;
  int _inCap;
  Pointer<Uint8> _outBuf;
  int _outCap;

  final Pointer<Uint32> _outW = malloc.allocate<Uint32>(sizeOf<Uint32>());
  final Pointer<Uint32> _outH = malloc.allocate<Uint32>(sizeOf<Uint32>());

  late final _DecoderDecodeDart _decode;
  late final _DecoderFreeDart _free;

  Vp9Decoder._(this._handle)
      : _inBuf  = malloc.allocate<Uint8>(256 * 1024), // 256 KB initial VP9 input
        _inCap  = 256 * 1024,
        _outBuf = malloc.allocate<Uint8>(1920 * 1080 * 4),
        _outCap = 1920 * 1080 * 4 {
    _decode = _codecLib
        .lookupFunction<_DecoderDecodeC, _DecoderDecodeDart>('bim_decoder_decode');
    _free = _codecLib
        .lookupFunction<_DecoderFreeC, _DecoderFreeDart>('bim_decoder_free');
  }

  static Vp9Decoder? create() {
    final fn = _codecLib
        .lookupFunction<_DecoderCreateC, _DecoderCreateDart>('bim_decoder_create');
    final handle = fn();
    if (handle == nullptr) return null;
    return Vp9Decoder._(handle);
  }

  DecodedFrame? decode(Uint8List vp9Packet) {
    if (vp9Packet.isEmpty) return null;

    // Grow input buffer only when needed.
    if (vp9Packet.length > _inCap) {
      malloc.free(_inBuf);
      _inCap = vp9Packet.length * 2;
      _inBuf = malloc.allocate<Uint8>(_inCap);
    }
    _inBuf.asTypedList(vp9Packet.length).setAll(0, vp9Packet);

    final written = _decode(
      _handle,
      _inBuf,
      vp9Packet.length,
      _outBuf,
      _outCap,
      _outW,
      _outH,
    );

    if (written <= 0) return null;

    final w = _outW.value;
    final h = _outH.value;

    // Grow output buffer only when needed.
    final needed = w * h * 4;
    if (needed > _outCap) {
      malloc.free(_outBuf);
      _outCap = needed;
      _outBuf = malloc.allocate<Uint8>(_outCap);

      final written2 = _decode(
        _handle,
        _inBuf,
        vp9Packet.length,
        _outBuf,
        _outCap,
        _outW,
        _outH,
      );
      if (written2 <= 0) return null;
    }

    return DecodedFrame(
      bgra: Uint8List.fromList(_outBuf.asTypedList(w * h * 4)),
      width: w,
      height: h,
    );
  }

  void dispose() {
    _free(_handle);
    malloc.free(_inBuf);
    malloc.free(_outBuf);
    malloc.free(_outW);
    malloc.free(_outH);
  }
}

class DecodedFrame {
  final Uint8List bgra;
  final int width;
  final int height;

  const DecodedFrame({required this.bgra, required this.width, required this.height});
}
