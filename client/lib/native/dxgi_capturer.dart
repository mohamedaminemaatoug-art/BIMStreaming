// ignore_for_file: camel_case_types, non_constant_identifier_names

/// DXGI Desktop Duplication screen capturer for Windows.
///
/// Adapts RustDesk's video_service.rs DXGI capture approach to Dart FFI.
/// Replaces GDI BitBlt (~15-20 ms/frame) with IDXGIOutputDuplication
/// (~1-3 ms/frame), eliminating the capture bottleneck so JPEG encoding
/// becomes the primary limiter.
///
/// COM calling convention (mirrors win32 package):
///   this  = pObj.cast<Pointer<IntPtr>>()   (= pObj.address, the COM interface ptr)
///   vtable slot N = Pointer<IntPtr>.fromAddress(pObj.ref.lpVtbl.address) + N
///
/// Usage:
///   final cap = DxgiCapturer();
///   if (cap.init()) {
///     final frame = cap.captureFrame();
///     // frame?.bgraPixels, frame?.width, frame?.height
///   }
///   cap.dispose();
library;

import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// ─── Type aliases ──────────────────────────────────────────────────────────────

/// COM vtable pointer type — Pointer<Pointer<IntPtr>>.
typedef _VP = Pointer<Pointer<IntPtr>>;

// ─── COM object struct ────────────────────────────────────────────────────────

/// Minimal COM object layout: first field is the vtable pointer.
base class _COM extends Struct {
  /// Value stored at the COM object's first field = vtable array address.
  external _VP lpVtbl;
}

// ─── Native structs ────────────────────────────────────────────────────────────

/// D3D11_TEXTURE2D_DESC — 11 × UINT = 44 bytes.
final class _TexDesc extends Struct {
  @Uint32() external int width;
  @Uint32() external int height;
  @Uint32() external int mipLevels;
  @Uint32() external int arraySize;
  @Uint32() external int format;
  @Uint32() external int sampleCount;
  @Uint32() external int sampleQuality;
  @Uint32() external int usage;
  @Uint32() external int bindFlags;
  @Uint32() external int cpuAccessFlags;
  @Uint32() external int miscFlags;
}

/// D3D11_MAPPED_SUBRESOURCE — 16 bytes on 64-bit.
final class _Mapped extends Struct {
  external Pointer<Uint8> pData;
  @Uint32() external int rowPitch;
  @Uint32() external int depthPitch;
}

/// GUID — 16 bytes.
final class _GUID extends Struct {
  @Uint32() external int data1;
  @Uint16() external int data2;
  @Uint16() external int data3;
  @Array(8) external Array<Uint8> data4;
}

final class _Rational extends Struct {
  @Uint32() external int numerator;
  @Uint32() external int denominator;
}

final class _ModeDesc extends Struct {
  @Uint32() external int width;
  @Uint32() external int height;
  external _Rational refreshRate;
  @Uint32() external int format;
  @Uint32() external int scanlineOrdering;
  @Uint32() external int scaling;
}

final class _OutDuplDesc extends Struct {
  external _ModeDesc modeDesc;
  @Uint32() external int rotation;
  @Int32() external int desktopImageInSystemMemory;
}

final class _MappedRect extends Struct {
  external Pointer<Uint8> pBits;
  @Int32() external int pitch;
}

// ─── Native function types ─────────────────────────────────────────────────────

typedef _CreateDevN = Int32 Function(
    Pointer<Void>, Int32, Pointer<Void>, Uint32, Pointer<Uint32>, Uint32, Uint32,
    Pointer<Pointer<_COM>>, Pointer<Uint32>, Pointer<Pointer<_COM>>);
typedef _CreateDevD = int Function(
    Pointer<Void>, int, Pointer<Void>, int, Pointer<Uint32>, int, int,
    Pointer<Pointer<_COM>>, Pointer<Uint32>, Pointer<Pointer<_COM>>);

typedef _QIN = Int32 Function(_VP, Pointer<_GUID>, Pointer<Pointer<Void>>);
typedef _QID = int Function(_VP, Pointer<_GUID>, Pointer<Pointer<Void>>);

typedef _RelN = Uint32 Function(_VP);
typedef _RelD = int Function(_VP);

typedef _GetAdpN = Int32 Function(_VP, Pointer<Pointer<_COM>>);
typedef _GetAdpD = int Function(_VP, Pointer<Pointer<_COM>>);

typedef _EnumOutN = Int32 Function(_VP, Uint32, Pointer<Pointer<_COM>>);
typedef _EnumOutD = int Function(_VP, int, Pointer<Pointer<_COM>>);

typedef _DuplN = Int32 Function(_VP, Pointer<Void>, Pointer<Pointer<_COM>>);
typedef _DuplD = int Function(_VP, Pointer<Void>, Pointer<Pointer<_COM>>);

typedef _GetDescN = Void Function(_VP, Pointer<Void>);
typedef _GetDescD = void Function(_VP, Pointer<Void>);

typedef _GetOutDuplDescN = Void Function(_VP, Pointer<_OutDuplDesc>);
typedef _GetOutDuplDescD = void Function(_VP, Pointer<_OutDuplDesc>);

typedef _AcqN = Int32 Function(_VP, Uint32, Pointer<Void>, Pointer<Pointer<_COM>>);
typedef _AcqD = int Function(_VP, int, Pointer<Void>, Pointer<Pointer<_COM>>);

typedef _RelFrmN = Int32 Function(_VP);
typedef _RelFrmD = int Function(_VP);

typedef _MapDesktopSurfaceN = Int32 Function(_VP, Pointer<_MappedRect>);
typedef _MapDesktopSurfaceD = int Function(_VP, Pointer<_MappedRect>);

typedef _UnmapDesktopSurfaceN = Int32 Function(_VP);
typedef _UnmapDesktopSurfaceD = int Function(_VP);

typedef _CrTexN = Int32 Function(_VP, Pointer<_TexDesc>, Pointer<Void>, Pointer<Pointer<_COM>>);
typedef _CrTexD = int Function(_VP, Pointer<_TexDesc>, Pointer<Void>, Pointer<Pointer<_COM>>);

typedef _CopyN = Void Function(_VP, Pointer<Void>, Pointer<Void>);
typedef _CopyD = void Function(_VP, Pointer<Void>, Pointer<Void>);

typedef _MapN = Int32 Function(_VP, Pointer<Void>, Uint32, Uint32, Uint32, Pointer<_Mapped>);
typedef _MapD = int Function(_VP, Pointer<Void>, int, int, int, Pointer<_Mapped>);

typedef _UnmapN = Void Function(_VP, Pointer<Void>, Uint32);
typedef _UnmapD = void Function(_VP, Pointer<Void>, int);

typedef _TexGetDescN = Void Function(_VP, Pointer<_TexDesc>);
typedef _TexGetDescD = void Function(_VP, Pointer<_TexDesc>);

// ─── Result type ──────────────────────────────────────────────────────────────

class DxgiCaptureResult {
  final Uint8List bgraPixels;
  final int width;
  final int height;
  const DxgiCaptureResult(this.bgraPixels, this.width, this.height);
}

// ─── IID record ───────────────────────────────────────────────────────────────

class _Iid {
  final int d1, d2, d3;
  final List<int> d4;
  const _Iid(this.d1, this.d2, this.d3, this.d4);
}

// ─── Main capturer ────────────────────────────────────────────────────────────

/// DXGI Desktop Duplication-based screen capturer.
///
/// Thread affinity: all methods must be called from the same Dart isolate
/// that created the capturer (COM objects are apartment-threaded).
class DxgiCapturer {
  // ── D3D11 / DXGI constants ──────────────────────────────────────────────────
  static const int _kHwDriver   = 1;
  static const int _kBgraFlag   = 0x20;
  static const int _kSdkVer     = 7;
  static const int _kFmtBgra    = 87;
  static const int _kStaging    = 3;
  static const int _kCpuRead    = 0x20000;
  static const int _kMapRead    = 1;
  static const int _kHrOk       = 0;
  static const int _kErrTimeout = -2004869081; // DXGI_ERROR_WAIT_TIMEOUT
  static const int _kErrAccess  = -2004869082; // DXGI_ERROR_ACCESS_LOST

  // ── Vtable indices ──────────────────────────────────────────────────────────
  static const int _iQI      = 0;
  static const int _iRel     = 2;
  static const int _iGetAdp  = 7;
  static const int _iEnumOut = 7;
  static const int _iDuplOut = 22;
  static const int _iGetDesc = 7;
  static const int _iAcqFrm  = 8;
  static const int _iMapDesktopSurface = 12;
  static const int _iUnmapDesktopSurface = 13;
  static const int _iRelFrm  = 14;
  static const int _iCrTex2  = 5;
  static const int _iCopyR   = 47;
  static const int _iMap     = 14;
  static const int _iUnmap   = 15;
  static const int _iTexDesc = 10;

  // ── Interface IDs ───────────────────────────────────────────────────────────
  static const _iidDxgiDevice = _Iid(0x54ec77fa, 0x1377, 0x44e6,
      [0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c]);
  static const _iidOutput1 = _Iid(0x00cddea8, 0x939b, 0x4b83,
      [0xa3, 0x40, 0xa6, 0x85, 0x22, 0x66, 0x66, 0xcc]);
  static const _iidTex2d = _Iid(0x6f15aaf2, 0xd208, 0x4e89,
      [0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c]);

  // ── State ───────────────────────────────────────────────────────────────────
  DynamicLibrary? _d3d11;
  Pointer<_COM>? _dev;
  Pointer<_COM>? _ctx;
  Pointer<_COM>? _dupl;
  Pointer<_COM>? _stag;
  bool _fastlane = false;

  int _w = 0, _h = 0;
  bool _ready = false;

  bool get isReady => _ready;

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Initialize for [monitor] index (0 = primary).
  bool init({int monitor = 0}) {
    _disposeAll();
    try {
      _d3d11 = DynamicLibrary.open('d3d11.dll');
      if (!_createDevice()) return false;
      if (!_buildDuplication(monitor)) return false;
      if (!_readDimensions()) return false;
      if (!_makeStagingTexture(_w, _h)) return false;
      _ready = true;
      return true;
    } catch (_) {
      _disposeAll();
      return false;
    }
  }

  /// Capture one frame. Returns null on timeout, access-lost, or error.
  DxgiCaptureResult? captureFrame() {
    if (!_ready || _dupl == null || _ctx == null || _stag == null) return null;

    final frameInfoBuf = calloc<Uint8>(128);
    final ppRes = calloc<Pointer<_COM>>();
    try {
      final hr = _vt(_dupl!, _iAcqFrm)
          .cast<Pointer<NativeFunction<_AcqN>>>()
          .value
          .asFunction<_AcqD>()(
              _this(_dupl!), 0, frameInfoBuf.cast(), ppRes);

      if (hr == _kErrTimeout) return null;
      if (hr == _kErrAccess || hr < 0) {
        _ready = false;
        return null;
      }

      final pRes = ppRes.value;
      if (pRes.address == 0) {
        _callReleaseFrame();
        return null;
      }

      final pTex = _qi(pRes, _iidTex2d);
      if (pTex == null) {
        _rel(pRes);
        _callReleaseFrame();
        return null;
      }

      final texDesc = calloc<_TexDesc>();
      try {
        _vt(pTex, _iTexDesc)
            .cast<Pointer<NativeFunction<_TexGetDescN>>>()
            .value
            .asFunction<_TexGetDescD>()(_this(pTex), texDesc);
        final fw = texDesc.ref.width;
        final fh = texDesc.ref.height;
        if (fw != _w || fh != _h) {
          if (_stag != null) { _rel(_stag!); _stag = null; }
          _w = fw; _h = fh;
          if (!_makeStagingTexture(_w, _h)) {
            _rel(pTex); _rel(pRes); _callReleaseFrame();
            _ready = false;
            return null;
          }
        }
      } finally {
        calloc.free(texDesc);
      }

      if (_fastlane) {
        final mapped = calloc<_MappedRect>();
        try {
          final hrMap = _vt(_dupl!, _iMapDesktopSurface)
              .cast<Pointer<NativeFunction<_MapDesktopSurfaceN>>>()
              .value
              .asFunction<_MapDesktopSurfaceD>()(_this(_dupl!), mapped);
          if (hrMap != _kHrOk) return null;

          final pData = mapped.ref.pBits;
          final rowPitch = mapped.ref.pitch;
          final stride = _w * 4;
          final bgraPixels = Uint8List(_w * _h * 4);

          for (int row = 0; row < _h; row++) {
            final srcOff = row * rowPitch;
            final dstOff = row * stride;
            bgraPixels.setRange(
              dstOff,
              dstOff + stride,
              pData.elementAt(srcOff).asTypedList(stride),
            );
          }

          _vt(_dupl!, _iUnmapDesktopSurface)
              .cast<Pointer<NativeFunction<_UnmapDesktopSurfaceN>>>()
              .value
              .asFunction<_UnmapDesktopSurfaceD>()(_this(_dupl!));

          _rel(pTex);
          _rel(pRes);
          _callReleaseFrame();
          return DxgiCaptureResult(bgraPixels, _w, _h);
        } finally {
          calloc.free(mapped);
        }
      }

      _vt(_ctx!, _iCopyR)
          .cast<Pointer<NativeFunction<_CopyN>>>()
          .value
          .asFunction<_CopyD>()(
              _this(_ctx!), _stag!.cast(), pTex.cast());

      _rel(pTex);
      _rel(pRes);
      _callReleaseFrame();

      final mapped = calloc<_Mapped>();
      try {
        final hrMap = _vt(_ctx!, _iMap)
            .cast<Pointer<NativeFunction<_MapN>>>()
            .value
            .asFunction<_MapD>()(
                _this(_ctx!), _stag!.cast(), 0, _kMapRead, 0, mapped);
        if (hrMap != _kHrOk) return null;

        final pData    = mapped.ref.pData;
        final rowPitch = mapped.ref.rowPitch;
        final stride   = _w * 4;
        final bgraPixels = Uint8List(_w * _h * 4);

        for (int row = 0; row < _h; row++) {
          final srcOff = row * rowPitch;
          final dstOff = row * stride;
          bgraPixels.setRange(
            dstOff,
            dstOff + stride,
            pData.elementAt(srcOff).asTypedList(stride),
          );
        }

        _vt(_ctx!, _iUnmap)
            .cast<Pointer<NativeFunction<_UnmapN>>>()
            .value
            .asFunction<_UnmapD>()(_this(_ctx!), _stag!.cast(), 0);

        return DxgiCaptureResult(bgraPixels, _w, _h);
      } finally {
        calloc.free(mapped);
      }
    } finally {
      calloc.free(frameInfoBuf);
      calloc.free(ppRes);
    }
  }

  void dispose() => _disposeAll();

  // ─── Initialization helpers ────────────────────────────────────────────────

  bool _createDevice() {
    final createDev =
        _d3d11!.lookupFunction<_CreateDevN, _CreateDevD>('D3D11CreateDevice');
    final ppDev  = calloc<Pointer<_COM>>();
    final ppCtx  = calloc<Pointer<_COM>>();
    final pLevel = calloc<Uint32>();
    try {
      final hr = createDev(nullptr, _kHwDriver, nullptr, _kBgraFlag,
          nullptr, 0, _kSdkVer, ppDev, pLevel, ppCtx);
      if (hr != _kHrOk) return false;
      _dev = ppDev.value;
      _ctx = ppCtx.value;
      return _dev!.address != 0 && _ctx!.address != 0;
    } finally {
      calloc.free(ppDev);
      calloc.free(ppCtx);
      calloc.free(pLevel);
    }
  }

  bool _buildDuplication(int monitorIndex) {
    final pDxgiDev = _qi(_dev!, _iidDxgiDevice);
    if (pDxgiDev == null) return false;

    final ppAdp = calloc<Pointer<_COM>>();
    try {
      final hr = _vt(pDxgiDev, _iGetAdp)
          .cast<Pointer<NativeFunction<_GetAdpN>>>()
          .value
          .asFunction<_GetAdpD>()(_this(pDxgiDev), ppAdp);
      _rel(pDxgiDev);
      if (hr != _kHrOk) return false;
      final pAdp = ppAdp.value;
      if (pAdp.address == 0) return false;

      final ppOut = calloc<Pointer<_COM>>();
      try {
        final hr2 = _vt(pAdp, _iEnumOut)
            .cast<Pointer<NativeFunction<_EnumOutN>>>()
            .value
            .asFunction<_EnumOutD>()(_this(pAdp), monitorIndex, ppOut);
        _rel(pAdp);
        if (hr2 != _kHrOk) return false;
        final pOut = ppOut.value;
        if (pOut.address == 0) return false;

        final pOut1 = _qi(pOut, _iidOutput1);
        _rel(pOut);
        if (pOut1 == null) return false;

        final ppDupl = calloc<Pointer<_COM>>();
        try {
          final hr3 = _vt(pOut1, _iDuplOut)
              .cast<Pointer<NativeFunction<_DuplN>>>()
              .value
              .asFunction<_DuplD>()(_this(pOut1), _dev!.cast(), ppDupl);
          _rel(pOut1);
          if (hr3 != _kHrOk) return false;
          _dupl = ppDupl.value;
          return _dupl!.address != 0;
        } finally {
          calloc.free(ppDupl);
        }
      } finally {
        calloc.free(ppOut);
      }
    } finally {
      calloc.free(ppAdp);
    }
  }

  bool _readDimensions() {
    final desc = calloc<_OutDuplDesc>();
    try {
      _vt(_dupl!, _iGetDesc)
          .cast<Pointer<NativeFunction<_GetOutDuplDescN>>>()
          .value
          .asFunction<_GetOutDuplDescD>()(_this(_dupl!), desc);
      _w = desc.ref.modeDesc.width;
      _h = desc.ref.modeDesc.height;
      _fastlane = desc.ref.desktopImageInSystemMemory != 0;
      return _w > 0 && _h > 0;
    } finally {
      calloc.free(desc);
    }
  }

  bool _makeStagingTexture(int w, int h) {
    final desc  = calloc<_TexDesc>();
    final ppTex = calloc<Pointer<_COM>>();
    try {
      desc.ref
        ..width          = w
        ..height         = h
        ..mipLevels      = 1
        ..arraySize      = 1
        ..format         = _kFmtBgra
        ..sampleCount    = 1
        ..sampleQuality  = 0
        ..usage          = _kStaging
        ..bindFlags      = 0
        ..cpuAccessFlags = _kCpuRead
        ..miscFlags      = 0;
      final hr = _vt(_dev!, _iCrTex2)
          .cast<Pointer<NativeFunction<_CrTexN>>>()
          .value
          .asFunction<_CrTexD>()(_this(_dev!), desc, nullptr, ppTex);
      if (hr != _kHrOk) return false;
      _stag = ppTex.value;
      return _stag!.address != 0;
    } finally {
      calloc.free(desc);
      calloc.free(ppTex);
    }
  }

  void _callReleaseFrame() {
    if (_dupl == null) return;
    _vt(_dupl!, _iRelFrm)
        .cast<Pointer<NativeFunction<_RelFrmN>>>()
        .value
        .asFunction<_RelFrmD>()(_this(_dupl!));
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────────

  void _disposeAll() {
    if (_stag != null) { _rel(_stag!); _stag = null; }
    if (_dupl != null) { _rel(_dupl!); _dupl = null; }
    if (_ctx  != null) { _rel(_ctx!);  _ctx  = null; }
    if (_dev  != null) { _rel(_dev!);  _dev  = null; }
    _w = 0; _h = 0;
    _fastlane = false;
    _ready = false;
  }

  // ─── COM helpers ───────────────────────────────────────────────────────────

  Pointer<_COM>? _qi(Pointer<_COM> pObj, _Iid iid) {
    final guid  = calloc<_GUID>();
    final ppOut = calloc<Pointer<Void>>();
    try {
      _fillGuid(guid, iid);
      final hr = _vt(pObj, _iQI)
          .cast<Pointer<NativeFunction<_QIN>>>()
          .value
          .asFunction<_QID>()(_this(pObj), guid, ppOut);
      if (hr != _kHrOk || ppOut.value.address == 0) return null;
      return ppOut.value.cast<_COM>();
    } finally {
      calloc.free(guid);
      calloc.free(ppOut);
    }
  }

  void _rel(Pointer<_COM> pObj) =>
      _vt(pObj, _iRel)
          .cast<Pointer<NativeFunction<_RelN>>>()
          .value
          .asFunction<_RelD>()(_this(pObj));

  /// COM `this` pointer: the COM interface pointer = pObj.address retyped as _VP.
  ///
  /// We store COM pointers as Pointer<_COM> (direct COM interface pointers).
  /// COM methods expect `this` = the COM interface address, not the vtable address.
  /// pObj.ref.lpVtbl.address = vtable array address (wrong for `this`).
  /// pObj.cast<Pointer<IntPtr>>() has .address = pObj.address = COM interface address (correct).
  _VP _this(Pointer<_COM> pObj) => pObj.cast<Pointer<IntPtr>>();

  /// Pointer to vtable slot [idx] for [pObj].
  ///
  /// pObj.ref.lpVtbl.address = vtable array address (read from first field of COM object).
  /// Adding [idx] gives the Nth slot in the vtable array.
  Pointer<IntPtr> _vt(Pointer<_COM> pObj, int idx) =>
      Pointer<IntPtr>.fromAddress(pObj.ref.lpVtbl.address) + idx;

  void _fillGuid(Pointer<_GUID> p, _Iid iid) {
    p.ref.data1 = iid.d1;
    p.ref.data2 = iid.d2;
    p.ref.data3 = iid.d3;
    for (int i = 0; i < 8; i++) p.ref.data4[i] = iid.d4[i];
  }
}
