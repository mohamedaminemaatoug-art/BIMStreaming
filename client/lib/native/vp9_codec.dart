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
    // The DLL must reside in the same directory as the Flutter executable.
    return DynamicLibrary.open('bimstreaming_codec.dll');
  }
  throw UnsupportedError('bimstreaming_codec is Windows-only');
}

DynamicLibrary? _lib;
DynamicLibrary get _codecLib => _lib ??= _loadCodecLib();

// ─── VP9 Encoder ─────────────────────────────────────────────────────────────

/// Hardware-accelerated VP9 CBR encoder.
///
/// Wraps the Rust `bimstreaming_codec.dll`. Not thread-safe — use from a
/// single Dart isolate.
class Vp9Encoder {
  final Pointer _handle;
  final int width;
  final int height;

  // Pre-allocated output buffer (worst-case I-frame ≈ width*height*3/2)
  late final Pointer<Uint8> _outBuf;
  late final int _outCap;

  // Cached function pointers
  late final _EncoderEncodeDart _encode;
  late final _EncoderSetBitrateDart _setBitrate;
  late final _EncoderFreeDart _free;

  Vp9Encoder._(this._handle, this.width, this.height) {
    _outCap = width * height * 2; // generous upper bound
    _outBuf = malloc.allocate<Uint8>(_outCap);

    _encode = _codecLib
        .lookupFunction<_EncoderEncodeC, _EncoderEncodeDart>('bim_encoder_encode');
    _setBitrate = _codecLib
        .lookupFunction<_EncoderSetBitrateC, _EncoderSetBitrateDart>(
            'bim_encoder_set_bitrate');
    _free = _codecLib
        .lookupFunction<_EncoderFreeC, _EncoderFreeDart>('bim_encoder_free');
  }

  /// Create an encoder for [width]×[height] frames at [bitrateKbps] kbps.
  ///
  /// Returns null if the native encoder could not be initialised.
  static Vp9Encoder? create(int width, int height, {int bitrateKbps = 1500}) {
    final fn = _codecLib
        .lookupFunction<_EncoderCreateC, _EncoderCreateDart>('bim_encoder_create');
    final handle = fn(width, height, bitrateKbps);
    if (handle == nullptr) return null;
    return Vp9Encoder._(handle, width, height);
  }

  /// Encode a BGRA frame.
  ///
  /// [bgraPixels] must be exactly `width * height * 4` bytes.
  /// Returns the encoded VP9 packet, or null on error.
  Uint8List? encode(Uint8List bgraPixels, {bool forceKeyframe = false}) {
    if (bgraPixels.length < width * height * 4) return null;

    // Pin the Dart bytes so we can pass a pointer to native code.
    final nativeBgra = malloc.allocate<Uint8>(bgraPixels.length);
    nativeBgra.asTypedList(bgraPixels.length).setAll(0, bgraPixels);

    try {
      final written = _encode(
        _handle,
        nativeBgra,
        bgraPixels.length,
        _outBuf,
        _outCap,
        forceKeyframe ? 1 : 0,
      );
      if (written <= 0) return null;
      // Copy result out before the next encode call overwrites _outBuf.
      return Uint8List.fromList(_outBuf.asTypedList(written));
    } finally {
      malloc.free(nativeBgra);
    }
  }

  /// Dynamically update the target bitrate (no re-initialisation needed).
  void setBitrate(int bitrateKbps) {
    _setBitrate(_handle, bitrateKbps);
  }

  /// Release all native resources.
  void dispose() {
    _free(_handle);
    malloc.free(_outBuf);
  }
}

// ─── VP9 Decoder ─────────────────────────────────────────────────────────────

/// VP9 decoder — converts encoded packets back to BGRA pixel buffers.
///
/// Not thread-safe — use from a single Dart isolate.
class Vp9Decoder {
  final Pointer _handle;

  // Pre-allocated BGRA output buffer (resized as needed)
  Pointer<Uint8> _outBuf;
  int _outCap;

  // Width/height out-params (heap-allocated for FFI)
  final Pointer<Uint32> _outW = malloc.allocate<Uint32>(sizeOf<Uint32>());
  final Pointer<Uint32> _outH = malloc.allocate<Uint32>(sizeOf<Uint32>());

  late final _DecoderDecodeDart _decode;
  late final _DecoderFreeDart _free;

  Vp9Decoder._(this._handle)
      : _outBuf = malloc.allocate<Uint8>(1920 * 1080 * 4),
        _outCap = 1920 * 1080 * 4 {
    _decode = _codecLib
        .lookupFunction<_DecoderDecodeC, _DecoderDecodeDart>('bim_decoder_decode');
    _free = _codecLib
        .lookupFunction<_DecoderFreeC, _DecoderFreeDart>('bim_decoder_free');
  }

  /// Create a decoder. Returns null if native initialisation fails.
  static Vp9Decoder? create() {
    final fn = _codecLib
        .lookupFunction<_DecoderCreateC, _DecoderCreateDart>('bim_decoder_create');
    final handle = fn();
    if (handle == nullptr) return null;
    return Vp9Decoder._(handle);
  }

  /// Decode one VP9 packet.
  ///
  /// Returns a [DecodedFrame] with BGRA pixels, or null if no frame was produced.
  DecodedFrame? decode(Uint8List vp9Packet) {
    if (vp9Packet.isEmpty) return null;

    final nativeVp9 = malloc.allocate<Uint8>(vp9Packet.length);
    nativeVp9.asTypedList(vp9Packet.length).setAll(0, vp9Packet);

    try {
      final written = _decode(
        _handle,
        nativeVp9,
        vp9Packet.length,
        _outBuf,
        _outCap,
        _outW,
        _outH,
      );

      if (written <= 0) return null;

      final w = _outW.value;
      final h = _outH.value;

      // If the frame is larger than our buffer, reallocate and retry.
      final needed = w * h * 4;
      if (needed > _outCap) {
        malloc.free(_outBuf);
        _outBuf = malloc.allocate<Uint8>(needed);
        _outCap = needed;

        final written2 = _decode(
          _handle,
          nativeVp9,
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
    } finally {
      malloc.free(nativeVp9);
    }
  }

  /// Release all native resources.
  void dispose() {
    _free(_handle);
    malloc.free(_outBuf);
    malloc.free(_outW);
    malloc.free(_outH);
  }
}

/// Result of a successful VP9 decode.
class DecodedFrame {
  final Uint8List bgra;
  final int width;
  final int height;

  const DecodedFrame({required this.bgra, required this.width, required this.height});
}
