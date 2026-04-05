import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart' as win32;
import '../services/signaling_client_service.dart';
import '../services/remote_audio_service.dart';
import '../services/keyboard/keyboard_services.dart';
import '../native/overlay_window.dart';

bool _globalHostKeyboardBlocked = false;
bool _globalHostMouseBlocked = false;

bool _isKeyboardInputMessage(int message) {
  switch (message) {
    case win32.WM_KEYDOWN:
    case win32.WM_KEYUP:
    case win32.WM_SYSKEYDOWN:
    case win32.WM_SYSKEYUP:
      return true;
    default:
      return false;
  }
}

int _globalKeyboardHookProc(int nCode, int wParam, int lParam) {
  if (nCode >= 0 && _globalHostKeyboardBlocked && _isKeyboardInputMessage(wParam)) {
    final keyboard = Pointer<_KbdLlHookStruct>.fromAddress(lParam).ref;
    final injected = (keyboard.flags & win32.LLKHF_INJECTED) != 0;
    if (!injected) {
      return 1;
    }
  }
  return win32.CallNextHookEx(0, nCode, wParam, lParam);
}

bool _isMouseInputMessage(int message) {
  switch (message) {
    case win32.WM_MOUSEMOVE:
    case win32.WM_LBUTTONDOWN:
    case win32.WM_LBUTTONUP:
    case win32.WM_LBUTTONDBLCLK:
    case win32.WM_RBUTTONDOWN:
    case win32.WM_RBUTTONUP:
    case win32.WM_RBUTTONDBLCLK:
    case win32.WM_MBUTTONDOWN:
    case win32.WM_MBUTTONUP:
    case win32.WM_MBUTTONDBLCLK:
    case win32.WM_MOUSEWHEEL:
    case win32.WM_XBUTTONDOWN:
    case win32.WM_XBUTTONUP:
    case win32.WM_XBUTTONDBLCLK:
    case win32.WM_MOUSEHWHEEL:
      return true;
    default:
      return false;
  }
}

int _globalMouseHookProc(int nCode, int wParam, int lParam) {
  if (nCode >= 0 && _globalHostMouseBlocked && _isMouseInputMessage(wParam)) {
    final mouse = Pointer<_MsLlHookStruct>.fromAddress(lParam).ref;
    const llmhfInjected = 0x00000001;
    final injected = (mouse.flags & llmhfInjected) != 0;
    if (!injected) {
      return 1;
    }
  }
  return win32.CallNextHookEx(0, nCode, wParam, lParam);
}

final Pointer<NativeFunction<win32.HOOKPROC>> _globalKeyboardHookProcPointer =
    Pointer.fromFunction<win32.HOOKPROC>(_globalKeyboardHookProc, 0);
final Pointer<NativeFunction<win32.HOOKPROC>> _globalMouseHookProcPointer =
    Pointer.fromFunction<win32.HOOKPROC>(_globalMouseHookProc, 0);

final class _CursorInfoNative extends Struct {
  @Uint32()
  external int cbSize;

  @Uint32()
  external int flags;

  @IntPtr()
  external int hCursor;

  @Int32()
  external int x;

  @Int32()
  external int y;
}

final class _IconInfoNative extends Struct {
  @Int32()
  external int fIcon;

  @Uint32()
  external int xHotspot;

  @Uint32()
  external int yHotspot;

  @IntPtr()
  external int hbmMask;

  @IntPtr()
  external int hbmColor;
}

final class _KbdLlHookStruct extends Struct {
  @Uint32()
  external int vkCode;

  @Uint32()
  external int scanCode;

  @Uint32()
  external int flags;

  @Uint32()
  external int time;

  @IntPtr()
  external int dwExtraInfo;
}

final class _MsLlHookStruct extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;

  @Uint32()
  external int mouseData;

  @Uint32()
  external int flags;

  @Uint32()
  external int time;

  @IntPtr()
  external int dwExtraInfo;
}

class RemoteSupportPage extends StatefulWidget {
  final String deviceName;
  final String deviceId;
  final bool sendLocalScreen;
  final int hostInputLockMinutes;
  final VoidCallback? onExitToRemoteControl;
  final String? sessionId;
  final String? currentUserId;
  final SignalingClientService? signalingService;
  final bool isDarkMode;
  final String Function(String) translate;

  const RemoteSupportPage({
    super.key,
    required this.deviceName,
    required this.deviceId,
    required this.sendLocalScreen,
    this.hostInputLockMinutes = 10,
    this.onExitToRemoteControl,
    this.sessionId,
    this.currentUserId,
    this.signalingService,
    required this.isDarkMode,
    required this.translate,
  });

  @override
  State<RemoteSupportPage> createState() => _RemoteSupportPageState();
}

class _RemoteSupportPageState extends State<RemoteSupportPage> {
  static const int _defaultCaptureMaxWidth = 1280;
  static const int _defaultJpegQuality = 50;
  static const int _defaultCaptureIntervalMs = 55;
  static const bool _remoteAudioFeatureEnabled = false;

  // ===== NEW: Performance Tracking & Diagnostics =====
  int _captureTimeMs = 0;
  int _encodeTimeMs = 0;
  int _sendTimeMs = 0;
  int _networkLatencyMs = 0;
  double _frameAvgLatencyMs = 0.0;
  int _framesDropped = 0;
  Uint8List? _lastFrameBytes;
  int _lastFrameHash = 0;
  DateTime? _lastFrameCaptureTime;
  final List<int> _latencyHistogram = List.filled(20, 0);
  // ===== END: Performance Tracking =====

  // ===== NEW: Cursor Optimization =====
  double _cursorPredictX = 0.5;
  double _cursorPredictY = 0.5;
  int _cursorUpdateFreqMs = 6; // Low-latency but more stable under rapid clicking
  final List<Offset> _cursorPositionHistory = [];
  // ===== END: Cursor Optimization =====

  // ===== NEW: Screen Dimension Tracking (Cursor Coordinate Fix) =====
  int _screenWidthActual = 1920;      // Receiver's actual screen width (for proper cursor positioning)
  int _screenHeightActual = 1080;     // Receiver's actual screen height (for proper cursor positioning)
  // ===== END: Screen Dimension Tracking =====

  // ===== NEW: TeamViewer-Style Cursor Channel (Independent of Video) =====
  Timer? _cursorUpdateTimer;                    // High-frequency cursor update timer (60-120Hz)
  double _localCursorX = 0.5;                   // Local cursor position (normalized)
  double _localCursorY = 0.5;                   // Local cursor position (normalized)
  double _lastSentCursorX = 0.5;                // Last sent cursor position
  double _lastSentCursorY = 0.5;                // Last sent cursor position
  double _remoteCursorDisplayX = 0.5;           // Remote cursor display position for rendering
  double _remoteCursorDisplayY = 0.5;           // Remote cursor display position for rendering
  double _remoteCursorPredictX = 0.5;           // Predicted cursor position (smoothing)
  double _remoteCursorPredictY = 0.5;           // Predicted cursor position (smoothing)
  double _remoteCursorVelocityX = 0.0;          // Cursor velocity for prediction
  double _remoteCursorVelocityY = 0.0;          // Cursor velocity for prediction
  int _lastRemoteCursorUpdateMs = 0;            // Last time we received cursor update
  bool _showRemoteCursor = false;               // Show/hide remote cursor overlay
  String _cursorShapeType = 'arrow';            // Current cursor shape (arrow, hand, text, etc)
  int? _lastCursorShapeUpdateMs = 0;            // Last time we detected cursor shape (cache: every 200ms)
  bool _cursorShapeDetectionInFlight = false;   // Prevent overlapping cursor-shape probes
  final Stopwatch _cursorMovementStopwatch = Stopwatch();
  // ===== END: TeamViewer-Style Cursor Channel =====

  bool _isConnected = true;
  String _connectionStatus = 'Connected';
  bool _isEncrypted = true;
  String _sessionTime = '00:00:00';
  String _encryptionType = 'AES-256 Encrypted';
  bool _isFullScreen = false;
  bool _isRecording = false;
  bool _audioEnabled = false;
  bool _isBlackoutMode = false;
  bool _isPrivacyModeForRemote = false;
  bool _isLockedForRemoteUser = false;
  bool _isDeviceLocked = false;
  bool _isRebooting = false;
  bool _isScreenSharing = false;
  bool _isCapturing = false;
  bool _isSessionPaused = false;
  bool _isSessionPausedRemote = false;
  bool _keyboardInputEnabledForUser2 = true;
  bool _mouseInputEnabledForUser2 = true;
  Timer? _keyboardAutoRestoreTimer;
  Timer? _mouseAutoRestoreTimer;
  Timer? _hostInputLockTimer;
  DateTime? _hostKeyboardLockedUntil;
  DateTime? _hostMouseLockedUntil;
  int _keyboardHookHandle = 0;
  int _mouseHookHandle = 0;
  int _framesSent = 0;
  int _framesReceived = 0;
  String _captureError = '';
  String _panelMode = 'none';
  final TextEditingController _composerController = TextEditingController();
  final List<String> _chatMessages = [];
  final ScrollController _chatScrollController = ScrollController();
  final List<Map<String, String>> _transfers = [];
  final List<Map<String, String>> _recordedFrames = [];
  Uint8List? _remoteScreenFrame;
  String? _pendingRemoteFrameData;
  int? _pendingRemoteFrameWidth;
  int? _pendingRemoteFrameHeight;
  int? _pendingRemoteScreenCount;
  int? _pendingRemoteScreenIndex;
  Timer? _pendingRemoteFrameTimer;
  Timer? _sessionTimer;
  Timer? _screenShareTimer;
  Timer? _overlayHideTimer;
  Timer? _diagnosticsTimer;
  Timer? _recordingTimer;
  Timer? _reconnectTimer;
  StreamSubscription<SignalEvent>? _signalSubscription;
  int _sessionSeconds = 0;
  final FocusNode _remoteControlFocusNode = FocusNode();
  int _lastPointerMoveMs = 0;
  bool _rightButtonPressed = false;
  bool _mouseButtonDown = false;
  bool _isClosingSession = false;
  int _remoteFrameWidth = 16;
  int _remoteFrameHeight = 9;
  int _virtualWidth = 1920;
  int _virtualHeight = 1080;
  int _remoteRealWidth = 0;
  int _remoteRealHeight = 0;
  int _remoteVirtualWidth = 1920;
  int _remoteVirtualHeight = 1080;
  double _remoteScaleRatio = 1.0;
  int _localFrameWidth = 0;
  int _localFrameHeight = 0;
  int _localCaptureLeft = 0;
  int _localCaptureTop = 0;
  int _localCaptureWidth = 0;
  int _localCaptureHeight = 0;
  bool _fillRemoteViewport = true;
  int _lastInputSentAtMs = 0;
  int _inputSequence = 0;
  int _lastAppliedInputSequence = 0;
  int _lastAppliedMoveSequence = 0;
  int _lastCaptureStatusSentMs = 0;
  double? _lastSentMoveX;
  double? _lastSentMoveY;
  int _lastMoveSentAtMs = 0;
  int _moveDeltaSinceKeyframe = 0;
  double _remoteCursorNormX = 0.5;
  double _remoteCursorNormY = 0.5;
  bool _remoteCursorInitialized = false;
  int _inputPacketsReceived = 0;
  int _inputPacketsDropped = 0;
  String _packetLossText = '0.0%';
  String _fpsText = '0';
  int _lastFrameSentHash = 0;
  int _lastFrameSentAtMs = 0;
  int _lastViewportHintAtMs = 0;
  double _lastViewportHintW = 0;
  double _lastViewportHintH = 0;
  double _lastViewportHintDpr = 0;
  int _remoteProtocolVersion = 1;
  bool _remoteSupportsMoveDelta = false;
  bool _remoteSupportsViewportHint = false;
  double? _pendingRemoteMoveX;
  double? _pendingRemoteMoveY;
  Timer? _pendingRemoteMoveTimer;
  bool _remoteMoveInFlight = false;
  Offset? _pendingMove;
  Timer? _pendingMoveTimer;
  double _wheelAccumulator = 0.0;

  // ===== NEW KEYBOARD SYSTEM v2 =====
  late KeyboardLayoutTranslator _keyboardLayoutTranslator;
  late KeyboardStateManager _keyboardStateManager;
  late KeyboardRepeatController _keyboardRepeatController;
  late KeyboardTransportLayer _keyboardTransportLayer;
  late KeyboardHostInjectionEngine _keyboardInjectionEngine;
  // ===== END KEYBOARD SYSTEM v2 =====

  Timer? _keyboardLayoutTimer;
  Timer? _keyStateSyncTimer;
  final Set<int> _pressedLogicalKeys = <int>{};
  final Map<int, Timer> _repeatStartTimers = <int, Timer>{};
  final Map<int, Timer> _repeatTickTimers = <int, Timer>{};
  Future<void> _remoteInputQueue = Future<void>.value();
  final Map<String, String> _sendKeysStrokeCache = <String, String>{};
  String _localKeyboardLayout = 'unknown';
  String _localKeyboardLayoutFamily = 'unknown';
  String _remoteKeyboardLayout = 'unknown';
  String _remoteKeyboardLayoutFamily = 'unknown';
  bool _showTopOverlay = true;
  bool _showLeftFloatingButtons = true;
  bool _hideAllHud = false;
  Timer? _hostMouseButtonSafetyTimer;
  String? _hostMouseButtonDownType;
  DynamicLibrary? _user32Lib;
  DynamicLibrary? _gdi32Lib;
  void Function(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo)? _nativeMouseEvent;
  bool _nativeMouseEventInitFailed = false;
  int Function(Pointer<_CursorInfoNative>)? _nativeGetCursorInfo;
  int Function(int, Pointer<Utf16>)? _nativeLoadCursorW;
  int Function(int, Pointer<_IconInfoNative>)? _nativeGetIconInfo;
  int Function(int)? _nativeDeleteObject;
  bool _nativeCursorApiInitFailed = false;
  int _captureMaxWidth = _defaultCaptureMaxWidth;
  int _captureJpegQuality = _defaultJpegQuality;
  String _captureResolutionLabel = 'Full Screen';
  String _qualityLabel = 'Medium';
  String _autoQualityMode = 'Manual';
  int _captureFrameIntervalMs = _defaultCaptureIntervalMs;
  bool _forceNativeScreenCapture = false;
  String _screenshotPath = '';
  String _recordingsPath = '';
  int _selectedRemoteScreenIndex = 0;
  int _selectedLocalScreenIndex = 0;
  int _remoteScreenCount = 1;
  int _localScreenCount = 1;
  int _pingMs = 0;
  String _bandwidthText = '0 kb/s';
  String _connectionQualityText = 'Stable';
  int _lastNetFrameCounter = 0;
  DateTime? _lastNetSampleAt;
  late final RemoteAudioService _remoteAudioService;
  bool _remoteAudioActive = false;
  bool _remoteAudioPeerCompatible = false;
  bool _remoteAudioCompatWarned = false;
  Timer? _remoteAudioCompatTimer;
  double _remoteAudioVolume = 0.8;
  int _remoteAudioBitrateKbps = 96;
  io.RawDatagramSocket? _audioUdpSocket;
  io.InternetAddress? _audioPeerAddress;
  int? _audioPeerPort;
  bool _audioUdpReady = false;
  String _audioUdpToken = '';
  Timer? _audioUdpOfferTimer;
  int _audioUdpOfferAttempts = 0;
  bool _audioUdpAckSent = false;
  String _transferMode = 'send';
  String _receiveTargetPath = '';
  int _reconnectAttempts = 0;
  int _recordingFps = 1;

  String tr(String key) => widget.translate(key);

  @override
  void initState() {
    super.initState();
    _audioUdpToken = _buildAudioUdpToken();
    _remoteAudioService = RemoteAudioService(
      isHost: widget.sendLocalScreen,
      sendPayload: _sendRemoteAudioPayload,
      pingProvider: () => _pingMs,
    );
    _initializeUserPaths();
    _initializeKeyboardSystemV2();
    _onKeyboardSessionConnected();
    _syncFullScreenState();
    _startSessionTimer();
    HostSessionOverlay.bindDisconnectHandler(_handleOverlayDisconnectRequested);
    if (widget.sendLocalScreen) {
      unawaited(
        HostSessionOverlay.startOverlay(
          label: 'Connected with: ${widget.deviceName}',
        ),
      );
    }
    _connectSessionSignalIfAvailable();
    _startAutomaticScreenShareIfPossible();
    _startDiagnosticsTimer();
    _startKeyboardLayoutSync();
    _startKeyStateSync();
    _startCursorUpdateTimer();  // CRITICAL: Separate high-frequency cursor channel (TeamViewer-style)
    _revealOverlayTemporarily();
    _refreshLocalScreenInfo();
    _autoEnterFullscreenForController();
    _pinRemoteAgentWindowIfNeeded();
    if (widget.sendLocalScreen && _isConnected) {
      unawaited(_minimizeHostWindowForConnectedState());
    }
    if (_remoteAudioFeatureEnabled) {
      unawaited(_initAudioUdpSocket());
      unawaited(_syncRemoteAudioPipeline());
    }
    _remoteControlFocusNode.addListener(() {
      if (!_remoteControlFocusNode.hasFocus) {
        _stopAllManagedRepeats();
        _pressedLogicalKeys.clear();
        _sendResetAllKeys();
      }
    });
    if (!widget.sendLocalScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _remoteControlFocusNode.requestFocus();
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _sendResolutionUpdate();
      }
    });
  }

  void _handleOverlayDisconnectRequested() {
    unawaited(_closeSession());
  }

  void _initializeUserPaths() {
    try {
      final userProfile = io.Platform.environment['USERPROFILE'] ?? '';
      if (userProfile.isNotEmpty) {
        _screenshotPath = '$userProfile\\screenshot';
        _recordingsPath = '$userProfile\\records';
        io.Directory(_screenshotPath).createSync(recursive: true);
        io.Directory(_recordingsPath).createSync(recursive: true);
      }
    } catch (_) {
      // Fall back to BimStreaming defaults if path creation fails
      final baseDir = io.Directory('${io.Platform.environment['USERPROFILE'] ?? '.'}\\BimStreaming');
      try {
        baseDir.createSync(recursive: true);
        _screenshotPath = '${baseDir.path}\\screenshot';
        _recordingsPath = '${baseDir.path}\\records';
        io.Directory(_screenshotPath).createSync(recursive: true);
        io.Directory(_recordingsPath).createSync(recursive: true);
      } catch (_) {
        // Use temp directory as last resort
        _screenshotPath = io.Directory.systemTemp.path;
        _recordingsPath = io.Directory.systemTemp.path;
      }
    }
  }

  Future<void> _autoEnterFullscreenForController() async {
    if (widget.sendLocalScreen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final isFs = await windowManager.isFullScreen();
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      if (!isFs) {
        await windowManager.setFullScreen(true);
      }
      if (!mounted) return;
      setState(() => _isFullScreen = true);
      _revealOverlayTemporarily();
    });
  }
  Future<void> _pinRemoteAgentWindowIfNeeded() async {
  }

  void _initializeKeyboardSystemV2() {
    try {
      // === Layout Translator ===
      _keyboardLayoutTranslator = KeyboardLayoutTranslator(
        onClientLayoutChanged: (old, newLayout) {
          if (old?.layoutId != newLayout?.layoutId) {
            print('[Keyboard] Client layout changed to ${newLayout?.displayName}');
            _sendInputEvent('layout_sync', extra: {
              'layout': newLayout?.layoutId ?? 'unknown',
              'layoutFamily': newLayout?.family ?? 'unknown',
            });
          }
        },
        onHostLayoutChanged: (old, newLayout) {
          print('[Keyboard] Host layout updated to ${newLayout?.displayName}');
        },
      );

      // === State Manager ===
      _keyboardStateManager = KeyboardStateManager(
        onKeyStateChanged: (key) {
          // Optional: log state changes
        },
        onStuckKeyForceReleased: (code, reason) {
          print('[Keyboard] WARNING: Stuck key 0x${code.toRadixString(16)} released: $reason');
        },
      );

      // === Repeat Controller ===
      _keyboardRepeatController = KeyboardRepeatController(
        initialDelayMs: 320,
        repeatIntervalMs: 42,
        onRepeat: (physicalCode, payload) {
          _keyboardTransportLayer.enqueueEvent(KeyboardKeyEvent.fromJson(payload));
        },
      );

      // === Transport Layer ===
      _keyboardTransportLayer = KeyboardTransportLayer(
        onSendEvent: (event) {
          _sendInputEvent('key_event', extra: event.toJson());
          return true;
        },
        onPacketLost: (lostSequence) {
          print('[Keyboard] Packet loss detected at sequence: $lostSequence');
        },
        onRequestStateSync: () {
          _syncKeyboardState();
        },
      );

      // === Injection Engine ===
      _keyboardInjectionEngine = KeyboardHostInjectionEngine(
        layoutTranslator: _keyboardLayoutTranslator,
        stateManager: _keyboardStateManager,
        executePowerShell: (args, {timeout}) async {
          final result = await _runPowerShell(
            args,
            timeout: timeout ?? const Duration(seconds: 10),
          );
          return '${result.stdout}';
        },
        onInjectionOccurred: (code, strategy) {
          // Optional: log injections
        },
        onInjectionFailed: (code, reason) {
          print('[Keyboard] Injection FAILED: $reason');
        },
      );

      // Startup
      unawaited(_keyboardLayoutTranslator.detectClientLayout());
      _startKeyboardLayoutSyncV2();
      print('[Keyboard] System V2 initialized successfully');
    } catch (e) {
      print('[Keyboard] Initialization error: $e');
    }
  }

  Future<void> _minimizeHostWindowForConnectedState() async {
    if (!widget.sendLocalScreen) return;
    try {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      final isFs = await windowManager.isFullScreen();
      if (isFs) {
        await windowManager.setFullScreen(false);
      }
      final isMin = await windowManager.isMinimized();
      if (!isMin) {
        await windowManager.minimize();
      }
      if (!mounted) return;
      setState(() => _isFullScreen = false);
    } catch (_) {
      // Best-effort host window minimize when session is connected.
    }
  }

  bool get _hasHostSessionError {
    if (!_isConnected) return true;
    if (_captureError.trim().isNotEmpty) return true;
    if (_nativeMouseEventInitFailed) return true;
    if (_connectionStatus.toLowerCase().contains('failed')) return true;
    if (_connectionStatus.toLowerCase().contains('reconnect')) return true;
    return false;
  }

  String get _hostSessionBannerText {
    final peerName = widget.deviceName.trim().isEmpty ? widget.deviceId : widget.deviceName;

    if (!_isConnected) {
      return 'Error: disconnected from $peerName';
    }

    if (_captureError.trim().isNotEmpty) {
      return 'Error: $_captureError';
    }

    if (_nativeMouseEventInitFailed) {
      return 'Error: mouse control initialization failed';
    }

    if (!_mouseInputEnabledForUser2) {
      return 'Warning: mouse input is disabled';
    }

    if (_isSessionPausedRemote) {
      return 'Warning: session paused by remote operator';
    }

    if (_connectionStatus.isNotEmpty && _connectionStatus != 'Connected') {
      return _connectionStatus;
    }

    return 'Connected successfully to: $peerName';
  }

  void _refreshLocalScreenInfoFromFlutterView() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final size = views.first.physicalSize;
    final width = size.width.round();
    final height = size.height.round();
    if (width <= 0 || height <= 0) return;

    if (!mounted) {
      _screenWidthActual = width;
      _screenHeightActual = height;
      return;
    }

    setState(() {
      _screenWidthActual = width;
      _screenHeightActual = height;
      if (_captureResolutionLabel == 'Full Screen') {
        _setVirtualResolutionFromLongEdge(_recommendedFullScreenCaptureWidth());
        _fillRemoteViewport = true;
      }
    });
  }

  Future<void> _refreshLocalScreenInfo() async {
    if (!io.Platform.isWindows) return;
    // Prefer a local Flutter API baseline so resolution remains valid even if
    // external PowerShell scripts are blocked by antivirus.
    _refreshLocalScreenInfoFromFlutterView();
    
    // OPTIMIZATION: Also capture screen dimensions for proper cursor coordinate transformation
    final script = r'''
Add-Type -AssemblyName System.Windows.Forms
$primary = [System.Windows.Forms.Screen]::PrimaryScreen
$count = [System.Windows.Forms.Screen]::AllScreens.Count
$width = $primary.Bounds.Width
$height = $primary.Bounds.Height
Write-Output "$count,$width,$height"
''';
    try {
      final result = await _runPowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        timeout: const Duration(seconds: 4),
      );
      if (result.exitCode != 0) {
        _refreshLocalScreenInfoFromFlutterView();
        return;
      }
      
      final output = '${result.stdout}'.trim();
      final parts = output.split(',');
      
      if (!mounted) return;
      setState(() {
        // Parse screen count
        if (parts.length >= 1) {
          _localScreenCount = int.tryParse(parts[0]) ?? 1;
        }
        // OPTIMIZATION: Capture actual screen dimensions for cursor coordinate fixing
        if (parts.length >= 3) {
          _screenWidthActual = int.tryParse(parts[1]) ?? _screenWidthActual;
          _screenHeightActual = int.tryParse(parts[2]) ?? _screenHeightActual;
          if (_captureResolutionLabel == 'Full Screen') {
            _setVirtualResolutionFromLongEdge(_recommendedFullScreenCaptureWidth());
            _fillRemoteViewport = true;
          }
          _sendResolutionUpdate();
        }
        
        if (_selectedLocalScreenIndex >= _localScreenCount) {
          _selectedLocalScreenIndex = 0;
        }
      });
    } catch (_) {
      _refreshLocalScreenInfoFromFlutterView();
    }
  }

  bool get _canSignal =>
      widget.signalingService != null &&
      (widget.currentUserId ?? '').isNotEmpty;

  void _connectSessionSignalIfAvailable() {
    if (!_canSignal) return;
    _signalSubscription = widget.signalingService!.events.listen(_handleSignalEvent);
    _sendSessionPayload(
      messageType: 'transport_capabilities',
      payload: {
        'protocolVersion': 2,
        'supportsMoveDelta': true,
        'supportsViewportHint': true,
        'videoMode': 'ws_jpeg_adaptive',
        'inputMode': 'ws_input_v2',
      },
    );
  }

  void _startAutomaticScreenShareIfPossible() {
    if (!widget.sendLocalScreen || widget.signalingService == null || !_isConnected) {
      return;
    }
    _isScreenSharing = true;
    _screenShareTimer?.cancel();
    _screenShareTimer = Timer.periodic(Duration(milliseconds: _captureFrameIntervalMs), (_) {
      _sendScreenFrame();
    });
    _sendScreenFrame();
  }

  void _restartScreenShareTimerIfNeeded() {
    if (!widget.sendLocalScreen || !_isScreenSharing) return;
    _screenShareTimer?.cancel();
    _screenShareTimer = Timer.periodic(Duration(milliseconds: _captureFrameIntervalMs), (_) {
      _sendScreenFrame();
    });
  }

  void _revealOverlayTemporarily() {
    if (_hideAllHud) return;
    if (!mounted) return;
    setState(() {
      _showTopOverlay = true;
      _showLeftFloatingButtons = true;
    });
    _overlayHideTimer?.cancel();
    _overlayHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _showTopOverlay = false;
        _showLeftFloatingButtons = false;
      });
    });
  }

  void _toggleHudVisibility() {
    if (!mounted) return;
    setState(() {
      _hideAllHud = !_hideAllHud;
      if (_hideAllHud) {
        _showTopOverlay = false;
        _showLeftFloatingButtons = false;
        _panelMode = 'none';
      }
    });
    if (_hideAllHud) {
      _overlayHideTimer?.cancel();
      return;
    }
    _revealOverlayTemporarily();
  }

  void _startDiagnosticsTimer() {
    _lastNetSampleAt = DateTime.now();
    _lastNetFrameCounter = _framesReceived;
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final now = DateTime.now();
      final prev = _lastNetSampleAt ?? now;
      final elapsed = now.difference(prev).inMilliseconds.clamp(1, 1000000);
      final frameDelta = _framesReceived - _lastNetFrameCounter;
      final kbps = ((frameDelta * 140.0 * 8.0) / (elapsed / 1000.0)).toStringAsFixed(0);
      final fps = ((frameDelta * 1000.0) / elapsed).clamp(0, 120).toStringAsFixed(1);
      final processedInputs = _inputPacketsReceived + _inputPacketsDropped;
      final packetLoss = processedInputs == 0
          ? 0.0
          : (_inputPacketsDropped * 100.0 / processedInputs);
      final q = _pingMs <= 50
          ? 'Excellent'
          : (_pingMs <= 100 ? 'Good' : (_pingMs <= 180 ? 'Fair' : 'Poor'));
      setState(() {
        _bandwidthText = '$kbps kb/s';
        _fpsText = fps;
        _packetLossText = '${packetLoss.toStringAsFixed(1)}%';
        _connectionQualityText = q;
        _lastNetFrameCounter = _framesReceived;
        _lastNetSampleAt = now;
      });
      await _refreshPing();
      _applyAutoQuality();
    });
    _refreshPing();
  }

  void _startKeyboardLayoutSync() {
    _keyboardLayoutTimer?.cancel();
    unawaited(_refreshKeyboardLayout(sendSync: true));
    _keyboardLayoutTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshKeyboardLayout(sendSync: true));
    });
  }

  Future<void> _refreshKeyboardLayout({required bool sendSync}) async {
    if (!io.Platform.isWindows) return;
    final result = await _runPowerShell(
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r"$v=(Get-ItemProperty -Path 'HKCU:\Keyboard Layout\Preload' -ErrorAction SilentlyContinue).'1'; if([string]::IsNullOrWhiteSpace($v)){$v='unknown'}; Write-Output $v",
      ],
      timeout: const Duration(seconds: 3),
    );
    var layout = '${result.stdout}'.trim();
    if (layout.isEmpty) {
      layout = 'unknown';
    }
    final family = _classifyLayoutFamily(layout);
    final changed = layout != _localKeyboardLayout || family != _localKeyboardLayoutFamily;
    if (!changed) return;
    if (mounted) {
      setState(() {
        _localKeyboardLayout = layout;
        _localKeyboardLayoutFamily = family;
      });
    } else {
      _localKeyboardLayout = layout;
      _localKeyboardLayoutFamily = family;
    }
    _sendKeysStrokeCache.clear();
    if (sendSync && _canSignal) {
      _sendInputEvent(
        'layout_sync',
        extra: {
          'layout': _localKeyboardLayout,
          'layoutFamily': _localKeyboardLayoutFamily,
        },
      );
    }
  }

  String _classifyLayoutFamily(String layout) {
    final normalized = layout.toLowerCase();
    if (normalized.contains('040c') || normalized.contains('080c') || normalized.contains('0c0c') || normalized.contains('100c')) {
      return 'azerty';
    }
    if (normalized.contains('0407') || normalized.contains('0807')) {
      return 'qwertz';
    }
    if (normalized.contains('0409') || normalized.contains('0809') || normalized.contains('0c09') || normalized.contains('1009')) {
      return 'qwerty';
    }
    return 'unknown';
  }

  Future<void> _refreshPing() async {
    final sw = Stopwatch()..start();
    try {
      final client = io.HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:8080/healthz'));
      final res = await req.close();
      await res.drain<void>();
      sw.stop();
      if (!mounted) return;
      setState(() {
        _pingMs = sw.elapsedMilliseconds;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pingMs = 999;
      });
    }
  }

  void _setResolutionPreset(String preset) {
    setState(() {
      _captureResolutionLabel = preset;
      switch (preset) {
        case 'Full Screen':
          _fillRemoteViewport = true;
          _setVirtualResolutionFromLongEdge(_recommendedFullScreenCaptureWidth());
          break;
        case 'Adapter':
          _fillRemoteViewport = false;
          _captureMaxWidth = _defaultCaptureMaxWidth;
          break;
        default:
          _captureMaxWidth = _defaultCaptureMaxWidth;
      }
    });
    _sendDisplayConfig();
  }

  void _setVirtualResolutionFromLongEdge(int longEdge) {
    final safeLongEdge = longEdge.clamp(960, 3840);
    final sourceW = _localCaptureWidth > 0 ? _localCaptureWidth : _screenWidthActual;
    final sourceH = _localCaptureHeight > 0 ? _localCaptureHeight : _screenHeightActual;
    final aspect = sourceW <= 0 || sourceH <= 0 ? (16.0 / 9.0) : sourceW / sourceH;
    int vw;
    int vh;
    if (aspect >= 1.0) {
      vw = safeLongEdge;
      vh = (safeLongEdge / aspect).round().clamp(540, 2160);
    } else {
      vh = safeLongEdge;
      vw = (safeLongEdge * aspect).round().clamp(540, 2160);
    }
    _virtualWidth = vw;
    _virtualHeight = vh;
    _captureMaxWidth = safeLongEdge;
  }

  void _applyAdaptiveResolutionFromController({
    required double viewportWidth,
    required double viewportHeight,
    required double dpr,
  }) {
    if (!widget.sendLocalScreen) return;
    if (viewportWidth <= 0 || viewportHeight <= 0) return;

    final safeDpr = dpr <= 0 ? 1.0 : dpr;
    final targetPixelWidth = (viewportWidth * safeDpr).round().clamp(320, 7680);
    final targetPixelHeight = (viewportHeight * safeDpr).round().clamp(320, 4320);
    final targetLongEdge = (targetPixelWidth > targetPixelHeight ? targetPixelWidth : targetPixelHeight)
        .clamp(960, 3840);

    final previousMaxWidth = _captureMaxWidth;
    final previousVirtualWidth = _virtualWidth;
    final previousVirtualHeight = _virtualHeight;

    setState(() {
      _captureResolutionLabel = 'Adaptive Device Fit';
      _setVirtualResolutionFromLongEdge(targetLongEdge);
      _fillRemoteViewport = true;
    });

    final changed =
        (previousMaxWidth - _captureMaxWidth).abs() >= 24 ||
        (previousVirtualWidth - _virtualWidth).abs() >= 24 ||
        (previousVirtualHeight - _virtualHeight).abs() >= 24;

    if (changed) {
      _restartScreenShareTimerIfNeeded();
      _sendResolutionUpdate();
    }
  }

  void _applyVirtualResolutionPolicy() {
    if (_captureResolutionLabel != 'Full Screen') return;
    if (_autoQualityMode == 'Auto') {
      final target = _pingMs <= 50
          ? _recommendedFullScreenCaptureWidth()
          : (_pingMs <= 100 ? 1600 : (_pingMs <= 180 ? 1366 : 1280));
      _setVirtualResolutionFromLongEdge(target);
      return;
    }
    switch (_qualityLabel) {
      case 'Low':
        _setVirtualResolutionFromLongEdge(1280);
        break;
      case 'Medium':
        _setVirtualResolutionFromLongEdge(1600);
        break;
      case 'High':
        _setVirtualResolutionFromLongEdge(1920);
        break;
      case 'Ultra':
        _setVirtualResolutionFromLongEdge(_recommendedFullScreenCaptureWidth());
        break;
      default:
        _setVirtualResolutionFromLongEdge(_recommendedFullScreenCaptureWidth());
    }
  }

  int _recommendedFullScreenCaptureWidth() {
    final longEdge = _screenWidthActual > _screenHeightActual
        ? _screenWidthActual
        : _screenHeightActual;
    return longEdge.clamp(_defaultCaptureMaxWidth, 3200);
  }

  void _setQualityPreset(String preset) {
    setState(() {
      _qualityLabel = preset;
      _autoQualityMode = preset;
      switch (preset) {
        case 'Auto':
          // Auto will be handled by _applyAutoQuality() during diagnostics
          _autoQualityMode = 'Auto';
          break;
        case 'Low':
          _captureJpegQuality = 45;
          _captureFrameIntervalMs = 65;
          _autoQualityMode = 'Manual';
          break;
        case 'Medium':
          _captureJpegQuality = _defaultJpegQuality;
          _captureFrameIntervalMs = 45;
          _autoQualityMode = 'Manual';
          break;
        case 'High':
          _captureJpegQuality = 92;
          _captureFrameIntervalMs = 33;
          _captureMaxWidth = _defaultCaptureMaxWidth;
          _autoQualityMode = 'Manual';
          break;
        case 'Ultra':
          _captureJpegQuality = 96;
          _captureFrameIntervalMs = 25;
          _captureMaxWidth = 3200;
          _autoQualityMode = 'Manual';
          break;
        default:
          _captureJpegQuality = _defaultJpegQuality;
          _captureFrameIntervalMs = _defaultCaptureIntervalMs;
          _autoQualityMode = 'Manual';
      }
      _applyVirtualResolutionPolicy();
    });
    _restartScreenShareTimerIfNeeded();
    _sendDisplayConfig();
  }

  void _applyAutoQuality() {
    if (_autoQualityMode != 'Auto') return;
    final inputBurst = DateTime.now().millisecondsSinceEpoch - _lastInputSentAtMs < 80;
    // Auto-adjust quality based on bandwidth and ping
    // Excellent (ping <= 50ms): Medium quality
    // Good (ping <= 100ms): Low quality
    // Fair (ping <= 180ms): Very Low quality
    // Poor (ping > 180ms): Ultra Low quality
    final newQuality = _pingMs <= 40
        ? 60
        : (_pingMs <= 80
            ? 50
            : (_pingMs <= 140
                ? 45
                : 40));
    final newIntervalMs = _pingMs <= 40
      ? 33
        : (_pingMs <= 80
        ? 45
            : (_pingMs <= 140
          ? 65
          : 95));
    final tunedIntervalMs = inputBurst
      ? (newIntervalMs + 20).clamp(40, 140)
      : newIntervalMs.clamp(25, 120);
    setState(() {
      _captureJpegQuality = newQuality;
      _captureFrameIntervalMs = tunedIntervalMs;
      _applyVirtualResolutionPolicy();
    });
    _restartScreenShareTimerIfNeeded();
  }

  void _sendDisplayConfig() {
    _sendSessionPayload(
      messageType: 'display_config',
      payload: {
        'screenIndex': _selectedRemoteScreenIndex,
        'resolution': _captureResolutionLabel,
        'quality': _qualityLabel,
      },
    );
  }

  void _sendResolutionUpdate() {
    if (!_canSignal) return;
    final effectiveWidth = _localFrameWidth > 0
        ? _localFrameWidth
        : (_localCaptureWidth > 0 ? _localCaptureWidth : _screenWidthActual);
    final effectiveHeight = _localFrameHeight > 0
        ? _localFrameHeight
        : (_localCaptureHeight > 0 ? _localCaptureHeight : _screenHeightActual);
    _sendSessionPayload(
      messageType: 'resolution_update',
      payload: {
        'width': effectiveWidth,
        'height': effectiveHeight,
        // Keep virtual dimensions aligned with real frame dimensions to avoid
        // aspect drift on heterogeneous controller machines.
        'virtualWidth': effectiveWidth,
        'virtualHeight': effectiveHeight,
      },
    );
  }

  void _maybeSendViewportHint(Size viewportSize) {
    if (widget.sendLocalScreen) return;
    if (!_canSignal) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final dx = (viewportSize.width - _lastViewportHintW).abs();
    final dy = (viewportSize.height - _lastViewportHintH).abs();
    final ddpr = (dpr - _lastViewportHintDpr).abs();
    final changed = dx >= 16 || dy >= 16 || ddpr >= 0.05;
    if (!changed && (now - _lastViewportHintAtMs) < 1200) return;
    if ((now - _lastViewportHintAtMs) < 350) return;
    _lastViewportHintAtMs = now;
    _lastViewportHintW = viewportSize.width;
    _lastViewportHintH = viewportSize.height;
    _lastViewportHintDpr = dpr;
    _sendSessionPayload(
      messageType: 'viewport_hint',
      payload: {
        'viewportWidth': viewportSize.width,
        'viewportHeight': viewportSize.height,
        'viewportDpr': dpr,
      },
    );
    _sendSessionPayload(
      messageType: 'resolution_request',
      payload: {
        'width': viewportSize.width,
        'height': viewportSize.height,
        'dpr': dpr,
      },
    );
  }

  void _sendInputPolicy() {
    _sendSessionPayload(
      messageType: 'input_policy',
      payload: {
        'keyboardEnabled': _keyboardInputEnabledForUser2,
        'mouseEnabled': _mouseInputEnabledForUser2,
        'lockDurationSeconds': _hostInputLockDurationSeconds,
      },
    );
  }

  int get _hostInputLockDurationSeconds {
    final safeMinutes = widget.hostInputLockMinutes <= 0 ? 10 : widget.hostInputLockMinutes;
    return safeMinutes * 60;
  }

  void _toggleUser2KeyboardPolicy() {
    final next = !_keyboardInputEnabledForUser2;
    setState(() {
      _keyboardInputEnabledForUser2 = next;
    });
    if (next) {
      _keyboardAutoRestoreTimer?.cancel();
      _keyboardAutoRestoreTimer = null;
    } else {
      _scheduleKeyboardAutoRestore();
      _showMessage(
        context,
        'Keyboard OFF for ${widget.hostInputLockMinutes} minutes (host local time)',
        _getColors(context),
      );
    }
    _sendInputPolicy();
  }

  void _toggleUser2MousePolicy() {
    final next = !_mouseInputEnabledForUser2;
    setState(() {
      _mouseInputEnabledForUser2 = next;
    });
    if (next) {
      _mouseAutoRestoreTimer?.cancel();
      _mouseAutoRestoreTimer = null;
    } else {
      _scheduleMouseAutoRestore();
      _showMessage(
        context,
        'Mouse OFF for ${widget.hostInputLockMinutes} minutes (host local time)',
        _getColors(context),
      );
    }
    _sendInputPolicy();
  }

  void _scheduleKeyboardAutoRestore() {
    _keyboardAutoRestoreTimer?.cancel();
    final duration = Duration(seconds: _hostInputLockDurationSeconds);
    _keyboardAutoRestoreTimer = Timer(duration, () {
      if (!mounted || _keyboardInputEnabledForUser2) return;
      setState(() {
        _keyboardInputEnabledForUser2 = true;
      });
      _sendInputPolicy();
      _showMessage(context, 'Keyboard control automatically restored', _getColors(context));
    });
  }

  void _scheduleMouseAutoRestore() {
    _mouseAutoRestoreTimer?.cancel();
    final duration = Duration(seconds: _hostInputLockDurationSeconds);
    _mouseAutoRestoreTimer = Timer(duration, () {
      if (!mounted || _mouseInputEnabledForUser2) return;
      setState(() {
        _mouseInputEnabledForUser2 = true;
      });
      _sendInputPolicy();
      _showMessage(context, 'Mouse control automatically restored', _getColors(context));
    });
  }

  void _applyHostTimedInputLock({
    required bool keyboardEnabled,
    required bool mouseEnabled,
    required int lockDurationSeconds,
  }) {
    if (!widget.sendLocalScreen) return;
    final seconds = lockDurationSeconds > 0 ? lockDurationSeconds : _hostInputLockDurationSeconds;
    final now = DateTime.now();

    _hostKeyboardLockedUntil = keyboardEnabled ? null : now.add(Duration(seconds: seconds));
    _hostMouseLockedUntil = mouseEnabled ? null : now.add(Duration(seconds: seconds));

    _refreshHostInputLockState();
    if (_hostKeyboardLockedUntil != null || _hostMouseLockedUntil != null) {
      _hostInputLockTimer?.cancel();
      _hostInputLockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _refreshHostInputLockState();
      });
    } else {
      _hostInputLockTimer?.cancel();
      _hostInputLockTimer = null;
    }
  }

  void _refreshHostInputLockState() {
    final now = DateTime.now();
    if (_hostKeyboardLockedUntil != null && !now.isBefore(_hostKeyboardLockedUntil!)) {
      _hostKeyboardLockedUntil = null;
    }
    if (_hostMouseLockedUntil != null && !now.isBefore(_hostMouseLockedUntil!)) {
      _hostMouseLockedUntil = null;
    }

    final keyboardBlocked = _hostKeyboardLockedUntil != null;
    final mouseBlocked = _hostMouseLockedUntil != null;
    _setHostInputBlockModes(keyboardBlocked: keyboardBlocked, mouseBlocked: mouseBlocked);

    final shouldBlock = keyboardBlocked || mouseBlocked;

    if (!shouldBlock) {
      _hostInputLockTimer?.cancel();
      _hostInputLockTimer = null;
    }
  }

  bool _ensureHostInputHooksInstalled() {
    if (!io.Platform.isWindows) return false;
    if (_keyboardHookHandle != 0 && _mouseHookHandle != 0) return true;

    final moduleHandle = win32.GetModuleHandle(nullptr);
    if (_keyboardHookHandle == 0) {
      _keyboardHookHandle = win32.SetWindowsHookEx(
        win32.WH_KEYBOARD_LL,
        _globalKeyboardHookProcPointer,
        moduleHandle,
        0,
      );
      if (_keyboardHookHandle == 0) {
        final error = win32.GetLastError();
        print('[InputPolicy] Failed to install keyboard hook: $error');
      }
    }

    if (_mouseHookHandle == 0) {
      _mouseHookHandle = win32.SetWindowsHookEx(
        win32.WH_MOUSE_LL,
        _globalMouseHookProcPointer,
        moduleHandle,
        0,
      );
      if (_mouseHookHandle == 0) {
        final error = win32.GetLastError();
        print('[InputPolicy] Failed to install mouse hook: $error');
      }
    }

    return _keyboardHookHandle != 0 && _mouseHookHandle != 0;
  }

  void _uninstallHostInputHooks() {
    if (!io.Platform.isWindows) return;

    if (_keyboardHookHandle != 0) {
      final ok = win32.UnhookWindowsHookEx(_keyboardHookHandle) != 0;
      if (!ok) {
        final error = win32.GetLastError();
        print('[InputPolicy] Failed to uninstall keyboard hook: $error');
      }
      _keyboardHookHandle = 0;
    }

    if (_mouseHookHandle != 0) {
      final ok = win32.UnhookWindowsHookEx(_mouseHookHandle) != 0;
      if (!ok) {
        final error = win32.GetLastError();
        print('[InputPolicy] Failed to uninstall mouse hook: $error');
      }
      _mouseHookHandle = 0;
    }
  }

  void _setHostInputBlockModes({required bool keyboardBlocked, required bool mouseBlocked}) {
    if (!io.Platform.isWindows) return;

    final shouldBlockAny = keyboardBlocked || mouseBlocked;
    if (shouldBlockAny) {
      final installed = _ensureHostInputHooksInstalled();
      if (!installed) {
        _globalHostKeyboardBlocked = false;
        _globalHostMouseBlocked = false;
        return;
      }

      _globalHostKeyboardBlocked = keyboardBlocked;
      _globalHostMouseBlocked = mouseBlocked;
      return;
    }

    _globalHostKeyboardBlocked = false;
    _globalHostMouseBlocked = false;
    _uninstallHostInputHooks();
  }

  void _releaseHostInputLock() {
    _hostInputLockTimer?.cancel();
    _hostInputLockTimer = null;
    _hostKeyboardLockedUntil = null;
    _hostMouseLockedUntil = null;
    _setHostInputBlockModes(keyboardBlocked: false, mouseBlocked: false);
  }

  void _togglePauseSession() {
    final next = !_isSessionPaused;
    setState(() {
      _isSessionPaused = next;
    });
    _sendSessionPayload(
      messageType: 'session_pause',
      payload: {'enabled': next},
    );
    _showMessage(
      context,
      next ? 'Session paused (screen frozen)' : 'Session resumed',
      _getColors(context),
    );
  }

  void _restartInputControl() {
    _keyboardAutoRestoreTimer?.cancel();
    _keyboardAutoRestoreTimer = null;
    _mouseAutoRestoreTimer?.cancel();
    _mouseAutoRestoreTimer = null;
    setState(() {
      _keyboardInputEnabledForUser2 = true;
      _mouseInputEnabledForUser2 = true;
    });
    _sendInputPolicy();
    _showMessage(context, 'Input control restarted', _getColors(context));
  }

  String _timestampForFile() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  void _handleSignalEvent(SignalEvent event) {
    if (!mounted || event.type != 'session_message') return;

    final rawData = event.data['data'];
    if (rawData is! Map) return;

    final data = Map<String, dynamic>.from(rawData);
    final messageSessionId = (data['sessionId'] ?? data['session_id'] ?? '').toString();
    final expectedSessionId = (widget.sessionId ?? '').toString();
    if (expectedSessionId.isNotEmpty && messageSessionId.isNotEmpty && messageSessionId != expectedSessionId) {
      return;
    }

    final fromUserId = (data['fromUserId'] ?? data['from'] ?? '').toString();
    final fromInstanceId = (data['fromInstanceId'] ?? data['from_instance'] ?? '').toString();
    if (fromUserId.isEmpty) {
      return;
    }
    if (fromUserId == widget.currentUserId) {
      final localInstanceId = widget.signalingService?.clientInstanceId ?? '';
      if (localInstanceId.isEmpty || fromInstanceId.isEmpty || fromInstanceId == localInstanceId) {
        return;
      }
    }

    final messageType = (data['messageType'] ?? '').toString();
    final payload = data['payload'] is Map
        ? Map<String, dynamic>.from(data['payload'] as Map)
        : <String, dynamic>{};

    if (messageType == 'screen_frame' && _remoteAudioFeatureEnabled && _audioEnabled && !_remoteAudioActive) {
      unawaited(_syncRemoteAudioPipeline());
    }

    if (messageType == 'input_event') {
      if (widget.sendLocalScreen) {
        _inputPacketsReceived++;
        final seq = payload['seq'] is num ? (payload['seq'] as num).toInt() : 0;
        if (seq > 0 && seq <= _lastAppliedInputSequence) {
          _inputPacketsDropped++;
          return;
        }
        if (seq > 0) {
          _lastAppliedInputSequence = seq;
        }
        final action = (payload['action'] ?? '').toString();
        const fastMouseActions = <String>{
          'left_down',
          'left_up',
          'right_down',
          'right_up',
          'wheel',
        };
        const fastKeyboardActions = <String>{
          'key_event',
          'key_press',
          'key_state_sync',
          'reset_all_keys',
        };
        if (action == 'move' || action == 'move_delta') {
          _enqueueRemoteMove(payload);
        } else if (fastMouseActions.contains(action)) {
          // Apply click/wheel immediately to minimize perceived latency.
          unawaited(_applyRemoteInput(payload));
        } else if (fastKeyboardActions.contains(action)) {
          // Keep keyboard path low-latency and avoid queue backpressure.
          unawaited(_applyRemoteInput(payload));
        } else {
          _enqueueRemoteInput(() => _applyRemoteInput(payload));
        }
      }
      return;
    }

    if (messageType == 'session_end') {
      _closeSession(notifyPeer: false);
      return;
    }

    if (messageType == 'lock_mode') {
      if (widget.sendLocalScreen) {
        setState(() {
          _isLockedForRemoteUser = payload['enabled'] == true;
        });
      }
      return;
    }

    if (messageType == 'privacy_mode') {
      if (widget.sendLocalScreen) {
        setState(() {
          _isPrivacyModeForRemote = payload['enabled'] == true;
        });
      }
      return;
    }

    if (messageType == 'audio_toggle') {
      if (!_remoteAudioFeatureEnabled) {
        if (mounted) {
          setState(() {
            _audioEnabled = false;
          });
        }
        return;
      }
      if (widget.sendLocalScreen) {
        setState(() {
          _audioEnabled = payload['enabled'] == true;
        });
        unawaited(_syncRemoteAudioPipeline());
      } else {
        setState(() {
          _audioEnabled = payload['enabled'] == true;
        });
        unawaited(_syncRemoteAudioPipeline());
      }
      return;
    }

    if (messageType == 'remote_audio') {
      if (!_remoteAudioFeatureEnabled) return;
      unawaited(_handleRemoteAudioSignal(payload));
      return;
    }

    if (messageType == 'system_action') {
      if (widget.sendLocalScreen) {
        _applySystemAction(payload);
      }
      return;
    }

    if (messageType == 'session_pause') {
      final enabled = payload['enabled'] == true;
      if (widget.sendLocalScreen) {
        setState(() {
          _isSessionPausedRemote = enabled;
        });
        _applyPauseStateOnSender();
      } else {
        setState(() {
          _isSessionPaused = enabled;
        });
      }
      return;
    }

    if (messageType == 'input_policy') {
      final keyboard = payload['keyboardEnabled'] != false;
      final mouse = payload['mouseEnabled'] != false;
      final lockDurationSeconds = payload['lockDurationSeconds'] is num
          ? (payload['lockDurationSeconds'] as num).toInt()
          : _hostInputLockDurationSeconds;
      setState(() {
        _keyboardInputEnabledForUser2 = keyboard;
        _mouseInputEnabledForUser2 = mouse;
      });
      _applyHostTimedInputLock(
        keyboardEnabled: keyboard,
        mouseEnabled: mouse,
        lockDurationSeconds: lockDurationSeconds,
      );
      return;
    }

    if (messageType == 'transport_capabilities') {
      final protocol = payload['protocolVersion'] is num
          ? (payload['protocolVersion'] as num).toInt()
          : 1;
      setState(() {
        _remoteProtocolVersion = protocol;
        _remoteSupportsMoveDelta = payload['supportsMoveDelta'] == true;
        _remoteSupportsViewportHint = payload['supportsViewportHint'] == true;
      });
      return;
    }

    if (messageType == 'cursor_update') {
      _handleRemoteCursorUpdate(payload);
      return;
    }

    if (messageType == 'viewport_hint') {
      if (!widget.sendLocalScreen) return;
      final w = payload['viewportWidth'] is num
          ? (payload['viewportWidth'] as num).toDouble()
          : 0.0;
      final h = payload['viewportHeight'] is num
          ? (payload['viewportHeight'] as num).toDouble()
          : 0.0;
      final dpr = payload['viewportDpr'] is num
          ? (payload['viewportDpr'] as num).toDouble()
          : 1.0;
      _applyAdaptiveResolutionFromController(
        viewportWidth: w,
        viewportHeight: h,
        dpr: dpr,
      );
      return;
    }

    if (messageType == 'resolution_request') {
      if (!widget.sendLocalScreen) return;
      final width = payload['width'] is num ? (payload['width'] as num).toDouble() : 0.0;
      final height = payload['height'] is num ? (payload['height'] as num).toDouble() : 0.0;
      final dpr = payload['dpr'] is num ? (payload['dpr'] as num).toDouble() : 1.0;
      _applyAdaptiveResolutionFromController(
        viewportWidth: width,
        viewportHeight: height,
        dpr: dpr,
      );
      return;
    }

    if (messageType == 'resolution_update') {
      final width = payload['width'] is num ? (payload['width'] as num).toInt() : 0;
      final height = payload['height'] is num ? (payload['height'] as num).toInt() : 0;
      final virtualWidth = payload['virtualWidth'] is num ? (payload['virtualWidth'] as num).toInt() : 0;
      final virtualHeight = payload['virtualHeight'] is num ? (payload['virtualHeight'] as num).toInt() : 0;
      if (width > 0 && height > 0) {
        setState(() {
          _remoteRealWidth = width;
          _remoteRealHeight = height;
          if (virtualWidth > 0 && virtualHeight > 0) {
            _remoteVirtualWidth = virtualWidth;
            _remoteVirtualHeight = virtualHeight;
          } else {
            _remoteVirtualWidth = width;
            _remoteVirtualHeight = height;
          }
          _remoteScaleRatio = _remoteVirtualWidth > 0 ? (_remoteRealWidth / _remoteVirtualWidth) : 1.0;
        });
      }
      return;
    }

    if (messageType == 'display_config') {
      final idxRaw = payload['screenIndex'];
      final resolution = (payload['resolution'] ?? '').toString();
      final quality = (payload['quality'] ?? '').toString();
      if (widget.sendLocalScreen) {
        if (idxRaw is num) {
          final idx = idxRaw.toInt();
          if (idx >= 0 && idx < _localScreenCount) {
            _selectedLocalScreenIndex = idx;
          }
        }
        if (resolution.isNotEmpty) {
          _captureResolutionLabel = resolution;
          if (resolution == 'Full Screen') _setVirtualResolutionFromLongEdge(_recommendedFullScreenCaptureWidth());
          if (resolution == '720p') _captureMaxWidth = 1280;
          if (resolution == '1080p') _captureMaxWidth = 1920;
          if (resolution == '540p') _captureMaxWidth = 960;
          if (resolution == 'Adapted Resolution') _captureMaxWidth = _defaultCaptureMaxWidth;
          _fillRemoteViewport = resolution == 'Full Screen';
        }
        if (quality.isNotEmpty) {
          _qualityLabel = quality;
          if (quality == 'Low') _captureJpegQuality = 45;
          if (quality == 'Medium') _captureJpegQuality = _defaultJpegQuality;
          if (quality == 'High') _captureJpegQuality = 92;
          if (quality == 'Ultra') _captureJpegQuality = 96;
          if (quality == 'Low') _captureFrameIntervalMs = 65;
          if (quality == 'Medium') _captureFrameIntervalMs = 45;
          if (quality == 'High') _captureFrameIntervalMs = 33;
          if (quality == 'Ultra') _captureFrameIntervalMs = 25;
          _restartScreenShareTimerIfNeeded();
        }
      }
      return;
    }

    if (messageType == 'capture_status') {
      if (!widget.sendLocalScreen) {
        final status = (payload['status'] ?? '').toString();
        final detail = (payload['detail'] ?? '').toString();
        setState(() {
          if (status == 'ok') {
            _captureError = '';
          } else if (detail.isNotEmpty) {
            _captureError = detail;
          }
        });
      }
      return;
    }

    if (messageType != 'screen_frame' && messageType != 'input_event') {
      print('[RemoteSupportPage] Received $messageType from $fromUserId: $payload');
    }

    var shouldRestoreHostWindow = false;
    setState(() {
      switch (messageType) {
        case 'chat':
          final text = (payload['text'] ?? '').toString();
          if (text.isNotEmpty) {
            print('[Chat] Added from peer: $text');
            _isConnected = true;
            _connectionStatus = 'Connected';
            shouldRestoreHostWindow = true;
            _chatMessages.add('Peer::$text');
            _panelMode = 'chat';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_chatScrollController.hasClients) {
                _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
              }
            });
          }
          break;
        case 'upload':
          final fileName = (payload['fileName'] ?? '').toString();
          final fileData = (payload['fileData'] ?? '').toString();
          final rawSize = payload['fileSize'];
          final fileSize = rawSize is int ? rawSize : (rawSize is double ? rawSize.toInt() : 0);
          if (fileName.isNotEmpty) {
            _isConnected = true;
            _connectionStatus = 'Connected';
            shouldRestoreHostWindow = true;
            _transfers.add({
              'type': 'received',
              'fileName': fileName,
              'path': payload['path']?.toString() ?? 'Unknown path',
              'from': fromUserId,
              'fileData': fileData,
              'status': 'Received',
              'speed': payload['speed']?.toString() ?? 'n/a',
              'progress': '100',
              'fileSize': fileSize > 0
                  ? '${(fileSize / 1024).toStringAsFixed(1)} KB'
                  : '',
            });
          }
          break;
        case 'screen_frame':
          final frameData = (payload['frameData'] ?? '').toString();
          if (frameData.isNotEmpty) {
            _isConnected = true;
            _connectionStatus = 'Connected';
            shouldRestoreHostWindow = true;
            if (_reconnectTimer != null) {
              _stopReconnectLoop();
            }
            _pendingRemoteFrameData = frameData;
            final fw = payload['frameWidth'];
            final fh = payload['frameHeight'];
            final vw = payload['virtualWidth'];
            final vh = payload['virtualHeight'];
            final rw = payload['remoteWidth'];
            final rh = payload['remoteHeight'];
            final sc = payload['screenCount'];
            final si = payload['screenIndex'];
            if (fw is num && fh is num && fw > 0 && fh > 0) {
              _pendingRemoteFrameWidth = fw.toInt();
              _pendingRemoteFrameHeight = fh.toInt();
            }
            if (vw is num && vh is num && vw > 0 && vh > 0) {
              _remoteVirtualWidth = vw.toInt();
              _remoteVirtualHeight = vh.toInt();
            }
            if (rw is num && rh is num && rw > 0 && rh > 0) {
              _remoteRealWidth = rw.toInt();
              _remoteRealHeight = rh.toInt();
            }
            if (_remoteVirtualWidth > 0 && _remoteRealWidth > 0) {
              _remoteScaleRatio = _remoteRealWidth / _remoteVirtualWidth;
            }
            if (sc is num && sc.toInt() > 0) {
              _pendingRemoteScreenCount = sc.toInt();
            }
            if (si is num && si.toInt() >= 0) {
              _pendingRemoteScreenIndex = si.toInt();
            }
            _scheduleRemoteFrameApply();
          }
          break;
      }
    });

    if (shouldRestoreHostWindow) {
      unawaited(_minimizeHostWindowForConnectedState());
    }
  }

  Future<void> _closeSession({bool notifyPeer = true}) async {
    if (_isClosingSession) return;
    _isClosingSession = true;

    _stopAllManagedRepeats();
    _onKeyboardSessionDisconnected();
    _pressedLogicalKeys.clear();
    _sendResetAllKeys();
    _audioUdpOfferTimer?.cancel();
    _audioUdpOfferTimer = null;
    _remoteAudioCompatTimer?.cancel();
    _remoteAudioCompatTimer = null;
    _audioUdpSocket?.close();
    _audioUdpSocket = null;
    _audioUdpReady = false;
    await _remoteAudioService.stopHost();
    await _remoteAudioService.stopClient();
    _remoteAudioActive = false;

    if (notifyPeer) {
      _sendSessionPayload(
        messageType: 'session_end',
        payload: {'reason': 'disconnect'},
      );
    }

    _sessionTimer?.cancel();
    _screenShareTimer?.cancel();
    _stopReconnectLoop();
    _pendingMoveTimer?.cancel();
    _pendingMoveTimer = null;
    _pendingMove = null;
    _keyboardAutoRestoreTimer?.cancel();
    _keyboardAutoRestoreTimer = null;
    _mouseAutoRestoreTimer?.cancel();
    _mouseAutoRestoreTimer = null;
    _releaseHostInputLock();

    await _restoreWindowStateForSessionExit();

    if (!mounted) return;

    Navigator.of(context).pop();
    widget.onExitToRemoteControl?.call();
  }

  Future<void> _restoreWindowStateForSessionExit() async {
    try {
      await windowManager.setAlwaysOnTop(false);
      final isFs = await windowManager.isFullScreen();
      if (isFs) {
        await windowManager.setFullScreen(false);
      }
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      final isMin = await windowManager.isMinimized();
      if (isMin) {
        await windowManager.restore();
      }
    } catch (_) {
      // Best-effort window restore.
    }
  }

  void _applyPauseStateOnSender() {
    if (!widget.sendLocalScreen) return;
    if (_isSessionPausedRemote) {
      _screenShareTimer?.cancel();
      _screenShareTimer = null;
    } else {
      _startAutomaticScreenShareIfPossible();
    }
  }

  void _startReconnectLoop() {
    if (_reconnectTimer != null) return;
    _reconnectAttempts = 0;
    _reconnectTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) return;
      if (_isConnected || !_canSignal || _isClosingSession) {
        _stopReconnectLoop();
        return;
      }

      _reconnectAttempts++;
      setState(() {
        _connectionStatus = 'Reconnecting ($_reconnectAttempts)';
      });

      if (_reconnectAttempts > 20) {
        setState(() {
          _connectionStatus = 'Reconnect failed';
          _isRebooting = false;
        });
        _stopReconnectLoop();
        return;
      }

      try {
        final uid = (widget.currentUserId ?? '').trim();
        if (uid.isEmpty) return;
        final ok = await widget.signalingService!.connect(userId: uid);
        if (!mounted) return;
        if (ok) {
          setState(() {
            _isConnected = true;
            _connectionStatus = 'Auto-reconnected';
            _isRebooting = false;
          });
          unawaited(_minimizeHostWindowForConnectedState());
          _stopReconnectLoop();
        }
      } catch (_) {
        // keep loop alive
      }
    });
  }

  void _stopReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
  }

  bool get _canSendRemoteInput =>
      _canSignal &&
      _isConnected &&
      !widget.sendLocalScreen;

  void _startKeyStateSync() {
    _keyStateSyncTimer?.cancel();
    _keyStateSyncTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _sendKeyStateSync();
    });
  }

  void _sendKeyStateSync() {
    if (!_canSendRemoteInput) return;
    final hw = HardwareKeyboard.instance;
    _sendInputEvent(
      'key_state_sync',
      extra: {
        'shift': hw.isShiftPressed,
        'ctrl': hw.isControlPressed,
        'alt': hw.isAltPressed,
        'meta': hw.isMetaPressed,
        'pressedCount': _pressedLogicalKeys.length,
      },
    );
  }

  void _sendResetAllKeys() {
    if (!_canSendRemoteInput) return;
    _sendInputEvent('reset_all_keys');
  }

  void _startKeyboardLayoutSyncV2() {
    _keyboardLayoutTimer?.cancel();
    _keyboardLayoutTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        await _keyboardLayoutTranslator.detectClientLayout();
      } catch (e) {
        print('[Keyboard] Layout sync error: $e');
      }
    });
  }

  Future<void> _syncKeyboardState() async {
    try {
      _keyboardStateManager.forceReleaseAll(reason: 'state_sync');
      _keyboardRepeatController.stopAllRepeats();
      final hw = HardwareKeyboard.instance;
      _sendInputEvent('key_state_full_sync', extra: {
        'shift': hw.isShiftPressed,
        'ctrl': hw.isControlPressed,
        'alt': hw.isAltPressed,
        'meta': hw.isMetaPressed,
      });
    } catch (e) {
      print('[Keyboard] State sync error: $e');
    }
  }

  void _onKeyboardSessionConnected() {
    try {
      _keyboardTransportLayer.onConnected();
      unawaited(_syncKeyboardState());
      print('[Keyboard] Session connected - system ready');
    } catch (e) {
      print('[Keyboard] Connection handler error: $e');
    }
  }

  void _onKeyboardSessionDisconnected() {
    try {
      _keyboardTransportLayer.onDisconnected();
      _keyboardStateManager.forceReleaseAll(reason: 'session_disconnected');
      _keyboardRepeatController.stopAllRepeats();
      print('[Keyboard] Session disconnected - system reset');
    } catch (e) {
      print('[Keyboard] Disconnection handler error: $e');
    }
  }

  void _enqueueRemoteInput(Future<void> Function() task) {
    _remoteInputQueue = _remoteInputQueue.then((_) => task()).catchError((_) {
      // Keep later input events flowing if one injection fails.
    });
  }

  void _sendWheelFromDelta(double deltaY) {
    if (!_canSendRemoteInput) return;
    _wheelAccumulator += deltaY;
    const threshold = 8.0;
    var dispatched = false;
    while (_wheelAccumulator.abs() >= threshold) {
      final direction = _wheelAccumulator > 0 ? 1 : -1;
      // Flutter dy > 0 means scroll down, while Win32 wheel < 0 is down.
      final wheel = direction > 0 ? -120 : 120;
      _sendInputEvent(
        'wheel',
        wheelDelta: wheel,
        normalizedX: _localCursorX,
        normalizedY: _localCursorY,
      );
      _wheelAccumulator -= threshold * direction;
      dispatched = true;
    }

    // Touchpads can emit tiny deltas that never cross threshold; send one step.
    if (!dispatched && deltaY.abs() >= 1.0) {
      final wheel = deltaY > 0 ? -120 : 120;
      _sendInputEvent(
        'wheel',
        wheelDelta: wheel,
        normalizedX: _localCursorX,
        normalizedY: _localCursorY,
      );
      _wheelAccumulator = 0.0;
    }
  }

  bool _isModifierLogical(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.capsLock;
  }

  bool _isManagedRepeatKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete;
  }

  bool _isManagedRepeatKeyV2(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete;
  }

  void _startManagedRepeat(KeyEvent event) {
    if (!_canSendRemoteInput || !_isManagedRepeatKey(event.logicalKey)) return;
    final logical = event.logicalKey.keyId;
    _stopManagedRepeat(logical);
    _repeatStartTimers[logical] = Timer(const Duration(milliseconds: 320), () {
      _repeatStartTimers.remove(logical);
      if (!_pressedLogicalKeys.contains(logical) || !_canSendRemoteInput) return;
      _repeatTickTimers[logical] = Timer.periodic(const Duration(milliseconds: 42), (_) {
        if (!_pressedLogicalKeys.contains(logical) || !_canSendRemoteInput) {
          _stopManagedRepeat(logical);
          return;
        }
        _sendKeyboardEvent(event, phase: 'down');
      });
    });
  }

  void _stopManagedRepeat(int logical) {
    _repeatStartTimers.remove(logical)?.cancel();
    _repeatTickTimers.remove(logical)?.cancel();
  }

  void _stopAllManagedRepeats() {
    for (final t in _repeatStartTimers.values) {
      t.cancel();
    }
    for (final t in _repeatTickTimers.values) {
      t.cancel();
    }
    _repeatStartTimers.clear();
    _repeatTickTimers.clear();
  }

  bool _sendRemoteAudioPayload(Map<String, dynamic> payload) {
    if (!_remoteAudioFeatureEnabled) return false;
    if (_audioUdpReady && payload['kind'] == 'packet' && _audioUdpSocket != null && _audioPeerAddress != null && _audioPeerPort != null) {
      final envelope = {
        'type': 'remote_audio_udp',
        'sessionId': (widget.sessionId ?? '').toString(),
        'token': _audioUdpToken,
        'payload': payload,
      };
      try {
        final bytes = utf8.encode(jsonEncode(envelope));
        final sent = _audioUdpSocket!.send(bytes, _audioPeerAddress!, _audioPeerPort!);
        if (sent > 0) {
          return true;
        }
      } catch (_) {
        _audioUdpReady = false;
      }
    }
    return _sendSessionPayload(messageType: 'remote_audio', payload: payload);
  }

  String _buildAudioUdpToken() {
    final sid = (widget.sessionId ?? '').toString();
    final a = (widget.currentUserId ?? '').toString();
    final b = widget.deviceId;
    final seed = '$sid|$a|$b|bim-audio-v1';
    final hash = seed.codeUnits.fold<int>(0, (acc, v) => (acc * 131 + v) & 0x7fffffff);
    return hash.toRadixString(16);
  }

  Future<void> _initAudioUdpSocket() async {
    if (_audioUdpSocket != null) return;
    try {
      final socket = await io.RawDatagramSocket.bind(io.InternetAddress.anyIPv4, 0);
      socket.readEventsEnabled = true;
      socket.listen((event) {
        if (event != io.RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        Map<String, dynamic> decoded;
        try {
          decoded = Map<String, dynamic>.from(jsonDecode(utf8.decode(dg.data)) as Map);
        } catch (_) {
          return;
        }
        if ((decoded['type'] ?? '') != 'remote_audio_udp') return;
        if ((decoded['sessionId'] ?? '').toString() != (widget.sessionId ?? '').toString()) return;
        if ((decoded['token'] ?? '').toString() != _audioUdpToken) return;
        final payloadRaw = decoded['payload'];
        if (payloadRaw is! Map) return;
        final payload = Map<String, dynamic>.from(payloadRaw);
        unawaited(_handleRemoteAudioPayload(payload));
      });
      _audioUdpSocket = socket;
      _startAudioUdpOfferLoop();
    } catch (_) {
      _audioUdpSocket = null;
    }
  }

  void _startAudioUdpOfferLoop() {
    _audioUdpOfferTimer?.cancel();
    _audioUdpOfferAttempts = 0;
    _audioUdpAckSent = false;
    _audioUdpOfferTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_audioUdpReady || !_canSignal || _audioUdpSocket == null) {
        if (_audioUdpReady) {
          timer.cancel();
        }
        return;
      }
      if (_audioUdpOfferAttempts >= 12) {
        timer.cancel();
        return;
      }
      _audioUdpOfferAttempts++;
      unawaited(() async {
        final ip = await _pickLanIpAddress();
        _sendSessionPayload(
          messageType: 'remote_audio',
          payload: {
            'kind': 'udp_offer',
            'ip': ip.address,
            'port': _audioUdpSocket!.port,
            'token': _audioUdpToken,
          },
        );
      }());
    });
  }

  Future<io.InternetAddress> _pickLanIpAddress() async {
    try {
      final interfaces = await io.NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == io.InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr;
          }
        }
      }
    } catch (_) {
      return io.InternetAddress.loopbackIPv4;
    }
    return io.InternetAddress.loopbackIPv4;
  }

  Future<void> _handleRemoteAudioSignal(Map<String, dynamic> payload) async {
    _remoteAudioPeerCompatible = true;
    final kind = (payload['kind'] ?? '').toString();
    if (kind == 'cap_probe') {
      _sendRemoteAudioPayload({'kind': 'cap_ack', 'version': 1});
      return;
    }
    if (kind == 'cap_ack') {
      return;
    }
    if (kind == 'udp_offer') {
      final token = (payload['token'] ?? '').toString();
      if (token != _audioUdpToken) return;
      final ip = (payload['ip'] ?? '').toString();
      final portRaw = payload['port'];
      if (ip.isEmpty || portRaw is! num || portRaw.toInt() <= 0) return;
      _audioPeerAddress = io.InternetAddress.tryParse(ip);
      _audioPeerPort = portRaw.toInt();
      if (_audioPeerAddress != null && _audioPeerPort != null) {
        _audioUdpReady = true;
      }
      if (!_audioUdpAckSent && _audioUdpSocket != null) {
        _audioUdpAckSent = true;
        final localIp = await _pickLanIpAddress();
        _sendSessionPayload(
          messageType: 'remote_audio',
          payload: {
            'kind': 'udp_ack',
            'ip': localIp.address,
            'port': _audioUdpSocket!.port,
            'token': _audioUdpToken,
          },
        );
      }
      return;
    }

    if (kind == 'udp_ack') {
      final token = (payload['token'] ?? '').toString();
      if (token != _audioUdpToken) return;
      final ip = (payload['ip'] ?? '').toString();
      final portRaw = payload['port'];
      if (ip.isEmpty || portRaw is! num || portRaw.toInt() <= 0) return;
      _audioPeerAddress = io.InternetAddress.tryParse(ip);
      _audioPeerPort = portRaw.toInt();
      if (_audioPeerAddress != null && _audioPeerPort != null) {
        _audioUdpReady = true;
      }
      return;
    }

    await _handleRemoteAudioPayload(payload);
  }

  Future<void> _syncRemoteAudioPipeline() async {
    if (!_remoteAudioFeatureEnabled) {
      if (_remoteAudioActive) {
        await _remoteAudioService.stopHost();
        await _remoteAudioService.stopClient();
        _remoteAudioActive = false;
      }
      _remoteAudioCompatTimer?.cancel();
      _remoteAudioCompatTimer = null;
      return;
    }
    if (!_isConnected || !_audioEnabled || !_canSignal) {
      if (_remoteAudioActive) {
        await _remoteAudioService.stopHost();
        await _remoteAudioService.stopClient();
        _remoteAudioActive = false;
      }
      _remoteAudioCompatTimer?.cancel();
      _remoteAudioCompatTimer = null;
      return;
    }

    _remoteAudioPeerCompatible = false;
    _remoteAudioCompatWarned = false;
    _sendRemoteAudioPayload({'kind': 'cap_probe', 'version': 1});
    _remoteAudioCompatTimer?.cancel();
    _remoteAudioCompatTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _remoteAudioPeerCompatible || _remoteAudioCompatWarned) return;
      _remoteAudioCompatWarned = true;
      _showMessage(
        context,
        'Remote peer does not support this audio patch yet. Update both apps to the same version.',
        _getColors(context),
      );
    });

    if (widget.sendLocalScreen) {
      await _remoteAudioService.startHost(bitrateKbps: _remoteAudioBitrateKbps);
    } else {
      await _remoteAudioService.startClient(volume: _remoteAudioVolume);
      // Request host config as soon as client enables audio.
      _sendRemoteAudioPayload({'kind': 'config', 'bitrateKbps': _remoteAudioBitrateKbps});
    }
    _remoteAudioActive = true;
  }

  Future<void> _handleRemoteAudioPayload(Map<String, dynamic> payload) async {
    await _remoteAudioService.handleIncoming(payload);
  }

  void _sendInputEvent(
    String action, {
    double? normalizedX,
    double? normalizedY,
    int? wheelDelta,
    String? key,
    Map<String, dynamic>? extra,
  }) {
    if (!_canSendRemoteInput) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastInputSentAtMs = now;
    final payload = <String, dynamic>{
      'action': action,
      'seq': ++_inputSequence,
      'sentAt': now,
      'channel': 'input',
    };
    if (normalizedX != null) payload['x'] = normalizedX.clamp(0.0, 1.0);
    if (normalizedY != null) payload['y'] = normalizedY.clamp(0.0, 1.0);
    if (wheelDelta != null) payload['wheelDelta'] = wheelDelta;
    if (key != null && key.isNotEmpty) payload['key'] = key;
    if (extra != null && extra.isNotEmpty) payload.addAll(extra);
    _sendSessionPayload(messageType: 'input_event', payload: payload);
  }

  // ===== NEW: Native Win32 Input Handler (TeamViewer-style optimization) =====
  /// High-speed native Win32 cursor control using FFI
  /// Replaces slow PowerShell execution with direct Win32 API calls
  /// IMPORTANT: Always denormalizes against host capture bounds (virtual pipeline).
  void _ensureNativeMouseEvent() {
    if (_nativeMouseEvent != null || _nativeMouseEventInitFailed || !io.Platform.isWindows) {
      return;
    }
    try {
      _user32Lib ??= DynamicLibrary.open('user32.dll');
      _nativeMouseEvent = _user32Lib!.lookupFunction<
          Void Function(Uint32 dwFlags, Uint32 dx, Uint32 dy, Int32 dwData, IntPtr dwExtraInfo),
          void Function(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo)>('mouse_event');
    } catch (e) {
      _nativeMouseEventInitFailed = true;
      debugPrint('[Input] mouse_event init failed: $e');
    }
  }

  void _emitNativeMouseEvent(int flags, {int data = 0}) {
    _ensureNativeMouseEvent();
    final fn = _nativeMouseEvent;
    if (fn == null) return;
    try {
      fn(flags, 0, 0, data, 0);
    } catch (e) {
      debugPrint('[Input] mouse_event failed: $e');
    }
  }

  void _armHostMouseButtonSafety(String buttonType) {
    _hostMouseButtonDownType = buttonType;
    _hostMouseButtonSafetyTimer?.cancel();
    _hostMouseButtonSafetyTimer = Timer(const Duration(milliseconds: 1500), () {
      final downType = _hostMouseButtonDownType;
      if (downType == null) return;
      if (downType == 'left') {
        _emitNativeMouseEvent(win32.MOUSEEVENTF_LEFTUP);
      } else if (downType == 'right') {
        _emitNativeMouseEvent(win32.MOUSEEVENTF_RIGHTUP);
      }
      _hostMouseButtonDownType = null;
    });
  }

  void _clearHostMouseButtonSafety() {
    _hostMouseButtonSafetyTimer?.cancel();
    _hostMouseButtonSafetyTimer = null;
    _hostMouseButtonDownType = null;
  }

  void _applyRemoteInputNative(String action, double? normX, double? normY, int wheelDelta) {
    if (!io.Platform.isWindows) return;
    try {
      if (normX != null && normY != null) {
        final capLeft = _localCaptureLeft;
        final capTop = _localCaptureTop;
        final capWidth = _localCaptureWidth > 0 ? _localCaptureWidth : _screenWidthActual;
        final capHeight = _localCaptureHeight > 0 ? _localCaptureHeight : _screenHeightActual;
        final pos = denormalizeCoordinates(
          normX: normX,
          normY: normY,
          targetLeft: capLeft,
          targetTop: capTop,
          targetWidth: capWidth,
          targetHeight: capHeight,
        );
        win32.SetCursorPos(pos.dx.round(), pos.dy.round());

        _cursorPredictX = normX;
        _cursorPredictY = normY;
      }

      switch (action) {
        case 'left_down':
          _emitNativeMouseEvent(win32.MOUSEEVENTF_LEFTDOWN);
          _armHostMouseButtonSafety('left');
          break;
        case 'left_up':
          _emitNativeMouseEvent(win32.MOUSEEVENTF_LEFTUP);
          _clearHostMouseButtonSafety();
          break;
        case 'right_down':
          _emitNativeMouseEvent(win32.MOUSEEVENTF_RIGHTDOWN);
          _armHostMouseButtonSafety('right');
          break;
        case 'right_up':
          _emitNativeMouseEvent(win32.MOUSEEVENTF_RIGHTUP);
          _clearHostMouseButtonSafety();
          break;
        case 'wheel':
          _emitNativeMouseEvent(win32.MOUSEEVENTF_WHEEL, data: wheelDelta);
          break;
      }

    } catch (e) {
      print('[Input] Native handler exception: $e');
    }
  }
  // ===== END: Native Win32 Input Handler =====

  void _sendKeyboardEvent(KeyEvent event, {required String phase}) {
    if (!_canSendRemoteInput) return;
    final logicalId = event.logicalKey.keyId;
    final physicalId = event.physicalKey.usbHidUsage;
    final keyLabel = event.logicalKey.keyLabel.trim();
    final debugName = (event.logicalKey.debugName ?? '').trim();
    final keyName = keyLabel.isNotEmpty ? keyLabel : debugName;
    final character = event.character ?? '';
    final isSpace = character == ' ' || keyName.toLowerCase() == 'space';
    final hw = HardwareKeyboard.instance;
    final altGraphPressed = hw.logicalKeysPressed.contains(LogicalKeyboardKey.altGraph);
    final isNumpad = keyName.toLowerCase().contains('numpad') || (physicalId >= 0x00070059 && physicalId <= 0x00070063);
    final legacyKey = character.isNotEmpty
      ? (isSpace ? 'Space' : character)
        : (keyName.isNotEmpty ? keyName : event.logicalKey.keyLabel);
    final modernPayload = <String, dynamic>{
      'phase': phase,
      'logicalKeyId': logicalId,
      'physicalKey': physicalId,
      'keyName': keyName,
      'character': character,
      'isNumpad': isNumpad,
      'shift': hw.isShiftPressed,
      'ctrl': hw.isControlPressed,
      'alt': hw.isAltPressed,
      'meta': hw.isMetaPressed,
      'altGraph': altGraphPressed,
      'sourceLayout': _localKeyboardLayout,
      'sourceLayoutFamily': _localKeyboardLayoutFamily,
      'targetLayout': _remoteKeyboardLayout,
      'targetLayoutFamily': _remoteKeyboardLayoutFamily,
      'protocol': 'keyboard_v2',
    };

    // Primary protocol for updated peers.
    _sendInputEvent('key_event', extra: modernPayload);

    // Backward compatibility for older peers that only understand key_press.
    // Send only on key-down to avoid duplicate characters on old receivers.
    if (phase == 'down' && legacyKey.isNotEmpty && !_isModifierKey({'keyName': keyName})) {
      _sendInputEvent(
        'key_press',
        key: legacyKey,
        extra: {
          'legacyCompat': true,
        },
      );
    }
  }

  Future<void> _applyRemoteInput(Map<String, dynamic> payload) async {
    if (!io.Platform.isWindows) return;

    final action = (payload['action'] ?? '').toString();
    if (action.isEmpty) return;
    const mouseActions = {
      'move',
      'left_down',
      'left_up',
      'right_down',
      'right_up',
      'wheel',
    };
    if (!_mouseInputEnabledForUser2 && mouseActions.contains(action)) {
      return;
    }
    if (!_keyboardInputEnabledForUser2 && (action == 'key_press' || action == 'key_event')) {
      return;
    }
    if (action == 'key_press' && payload['legacyCompat'] == true) {
      return;
    }
    if (action == 'reset_all_keys') {
      await _resetRemoteInjectedKeys();
      return;
    }
    if (action == 'key_state_sync') {
      await _applyRemoteKeyStateSync(payload);
      return;
    }
    if (action == 'layout_sync') {
      _remoteKeyboardLayout = (payload['layout'] ?? 'unknown').toString();
      _remoteKeyboardLayoutFamily = (payload['layoutFamily'] ?? 'unknown').toString();
      _sendKeysStrokeCache.clear();
      return;
    }
    if (action == 'key_event' || (action == 'key_press' && payload.containsKey('phase'))) {
      await _applyRemoteKeyboardEvent(payload);
      return;
    }
    if (action == 'move' || action == 'move_delta') {
      _enqueueRemoteMove(payload);
      return;
    }

    final x = (payload['x'] is num) ? (payload['x'] as num).toDouble() : null;
    final y = (payload['y'] is num) ? (payload['y'] as num).toDouble() : null;
    final wheelDelta = (payload['wheelDelta'] is num)
        ? (payload['wheelDelta'] as num).toInt()
        : 0;
    final key = (payload['key'] ?? '').toString();

    // Handle all mouse actions natively to avoid PowerShell stalls/freezes.
    if (mouseActions.contains(action)) {
      _applyRemoteInputNative(action, x, y, wheelDelta);
      return;
    }

    // Keyboard input still uses PowerShell (acceptable latency for keyboard)
    final script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeInput {
  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int X, int Y);

  [DllImport("user32.dll")]
  public static extern void mouse_event(uint dwFlags, uint dx, uint dy, int dwData, UIntPtr dwExtraInfo);
}

public static class NativeDpi {
  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();
}
"@

$action = '__ACTION__'
$x = __X__
$y = __Y__
$wheel = __WHEEL__
$key = '__KEY__'
$capLeft = __CAP_LEFT__
$capTop = __CAP_TOP__
$capWidth = __CAP_WIDTH__
$capHeight = __CAP_HEIGHT__

[NativeDpi]::SetProcessDPIAware() | Out-Null

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
if ($capWidth -gt 0 -and $capHeight -gt 0) {
  $bounds = New-Object System.Drawing.Rectangle($capLeft, $capTop, $capWidth, $capHeight)
}
if ($x -ge 0 -and $y -ge 0) {
  $px = $bounds.Left + [int]([double]($bounds.Width - 1) * $x)
  $py = $bounds.Top + [int]([double]($bounds.Height - 1) * $y)
  [NativeInput]::SetCursorPos($px, $py) | Out-Null
}

switch ($action) {
  'left_down' { [NativeInput]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero) }
  'left_up' { [NativeInput]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero) }
  'right_down' { [NativeInput]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero) }
  'right_up' { [NativeInput]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero) }
  'wheel' { [NativeInput]::mouse_event(0x0800, 0, 0, [int]$wheel, [UIntPtr]::Zero) }
  'key_press' {
    if (-not [string]::IsNullOrWhiteSpace($key)) {
      $map = @{
        'Enter' = '{ENTER}';
        'Backspace' = '{BACKSPACE}';
        'Tab' = '{TAB}';
        'Escape' = '{ESC}';
        'Arrow Left' = '{LEFT}';
        'Arrow Right' = '{RIGHT}';
        'Arrow Up' = '{UP}';
        'Arrow Down' = '{DOWN}';
        'Delete' = '{DELETE}';
        'Home' = '{HOME}';
        'End' = '{END}';
        'Page Up' = '{PGUP}';
        'Page Down' = '{PGDN}';
        'Space' = ' ';
      }
      if ($map.ContainsKey($key)) {
        [System.Windows.Forms.SendKeys]::SendWait($map[$key])
      } elseif ($key.Length -eq 1) {
        [System.Windows.Forms.SendKeys]::SendWait($key)
      }
    }
  }
}
'''
        .replaceAll('__ACTION__', action.replaceAll("'", "''"))
        .replaceAll('__X__', x == null ? '-1' : x.toStringAsFixed(6))
        .replaceAll('__Y__', y == null ? '-1' : y.toStringAsFixed(6))
        .replaceAll('__WHEEL__', wheelDelta.toString())
        .replaceAll('__CAP_LEFT__', _localCaptureLeft.toString())
        .replaceAll('__CAP_TOP__', _localCaptureTop.toString())
        .replaceAll('__CAP_WIDTH__', _localCaptureWidth.toString())
        .replaceAll('__CAP_HEIGHT__', _localCaptureHeight.toString())
        .replaceAll('__KEY__', key.replaceAll("'", "''"));

    try {
      await _runPowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        timeout: const Duration(seconds: 2),
      );
    } catch (_) {
      // Ignore remote input injection failures silently to keep session alive.
    }
  }

  void _enqueueRemoteMove(Map<String, dynamic> payload) {
    final action = (payload['action'] ?? '').toString();
    if (action != 'move' && action != 'move_delta') return;
    final seq = payload['seq'] is num ? (payload['seq'] as num).toInt() : 0;
    if (seq > 0 && seq <= _lastAppliedMoveSequence) {
      _inputPacketsDropped++;
      return;
    }
    if (seq > 0) _lastAppliedMoveSequence = seq;

    double? x = (payload['x'] is num) ? (payload['x'] as num).toDouble() : null;
    double? y = (payload['y'] is num) ? (payload['y'] as num).toDouble() : null;
    if (action == 'move_delta') {
      final dx = payload['dx'] is num ? (payload['dx'] as num).toDouble() : 0.0;
      final dy = payload['dy'] is num ? (payload['dy'] as num).toDouble() : 0.0;
      final baseX = payload['baseX'] is num
          ? (payload['baseX'] as num).toDouble()
          : (_remoteCursorInitialized ? _remoteCursorNormX : 0.5);
      final baseY = payload['baseY'] is num
          ? (payload['baseY'] as num).toDouble()
          : (_remoteCursorInitialized ? _remoteCursorNormY : 0.5);
      x = (baseX + dx).clamp(0.0, 1.0);
      y = (baseY + dy).clamp(0.0, 1.0);
    }

    if (x == null || y == null) return;
    // Apply exact normalized coordinate to host pointer injection.
    // Avoid predictive extrapolation here because it causes click/hover mismatch.
    final clampedX = x.clamp(0.0, 1.0);
    final clampedY = y.clamp(0.0, 1.0);

    _remoteCursorNormX = clampedX;
    _remoteCursorNormY = clampedY;
    _remoteCursorInitialized = true;
    _pendingRemoteMoveX = clampedX;
    _pendingRemoteMoveY = clampedY;
    _schedulePendingRemoteMoveDispatch();
  }

  void _schedulePendingRemoteMoveDispatch() {
    if (_remoteMoveInFlight) return;
    if (_pendingRemoteMoveTimer?.isActive == true) return;
    _pendingRemoteMoveTimer = Timer(const Duration(milliseconds: 2), () {
      _pendingRemoteMoveTimer = null;
      unawaited(_dispatchPendingRemoteMove());
    });
  }

  Future<void> _dispatchPendingRemoteMove() async {
    if (_remoteMoveInFlight) return;
    final x = _pendingRemoteMoveX;
    final y = _pendingRemoteMoveY;
    if (x == null || y == null) return;
    _pendingRemoteMoveX = null;
    _pendingRemoteMoveY = null;
    _remoteMoveInFlight = true;
    try {
      await _applyRemotePointerMove(x, y);
    } finally {
      _remoteMoveInFlight = false;
      if (_pendingRemoteMoveX != null && _pendingRemoteMoveY != null) {
        _schedulePendingRemoteMoveDispatch();
      }
    }
  }

  Future<void> _applyRemotePointerMove(double x, double y) async {
    // Native cursor move is lower latency and avoids PowerShell DPI/runtime drift.
    _applyRemoteInputNative('move', x, y, 0);
  }
  Future<void> _applyRemoteKeyboardEventLegacy(Map<String, dynamic> payload) async {
    try {
      final keyboardEvent = KeyboardKeyEvent.fromJson(payload);
      final result = await _keyboardInjectionEngine.injectKeyboardEvent(
        keyboardEvent,
        hostLayout: _keyboardLayoutTranslator.hostLayout?.layoutId ?? 'unknown',
        hostLayoutFamily: _keyboardLayoutTranslator.hostLayoutFamily,
      );
      if (!result) {
        print('[Keyboard] Legacy native fallback failed for ${keyboardEvent.keyName}');
      }
    } catch (e) {
      print('[Keyboard] Legacy fallback exception: $e');
    }
  }

  Future<void> _applyRemoteKeyStateSync(Map<String, dynamic> payload) async {
    final desiredShift = payload['shift'] == true;
    final desiredCtrl = payload['ctrl'] == true;
    final desiredAlt = payload['alt'] == true;
    final desiredMeta = payload['meta'] == true;

    await _applyRemoteKeyboardEvent({'phase': desiredShift ? 'down' : 'up', 'keyName': 'shift'});
    await _applyRemoteKeyboardEvent({'phase': desiredCtrl ? 'down' : 'up', 'keyName': 'control'});
    await _applyRemoteKeyboardEvent({'phase': desiredAlt ? 'down' : 'up', 'keyName': 'alt'});
    await _applyRemoteKeyboardEvent({'phase': desiredMeta ? 'down' : 'up', 'keyName': 'meta'});
  }

  Future<void> _resetRemoteInjectedKeys() async {
    await _applyRemoteKeyboardEvent({'phase': 'up', 'keyName': 'shift'});
    await _applyRemoteKeyboardEvent({'phase': 'up', 'keyName': 'control'});
    await _applyRemoteKeyboardEvent({'phase': 'up', 'keyName': 'alt'});
    await _applyRemoteKeyboardEvent({'phase': 'up', 'keyName': 'meta'});
  }

  int _resolveVirtualKey(Map<String, dynamic> payload) {
    final physical = payload['physicalKey'] is num ? (payload['physicalKey'] as num).toInt() : 0;
    const physicalVkMap = {
      0x00070059: 0x61,
      0x0007005A: 0x62,
      0x0007005B: 0x63,
      0x0007005C: 0x64,
      0x0007005D: 0x65,
      0x0007005E: 0x66,
      0x0007005F: 0x67,
      0x00070060: 0x68,
      0x00070061: 0x69,
      0x00070062: 0x60,
      0x00070063: 0x6E,
      0x00070054: 0x6F,
      0x00070055: 0x6A,
      0x00070056: 0x6D,
      0x00070057: 0x6B,
      0x00070058: 0x0D,
    };
    if (physicalVkMap.containsKey(physical)) return physicalVkMap[physical]!;

    final keyName = (payload['keyName'] ?? '').toString().toLowerCase();
    if (keyName.isEmpty) return 0;
    const vkMap = {
      'shift left': 0xA0,
      'shift right': 0xA1,
      'shift': 0x10,
      'control left': 0xA2,
      'control right': 0xA3,
      'control': 0x11,
      'alt left': 0xA4,
      'alt right': 0xA5,
      'alt': 0x12,
      'meta': 0x5B,
      'meta left': 0x5B,
      'meta right': 0x5C,
      'enter': 0x0D,
      'tab': 0x09,
      'escape': 0x1B,
      'backspace': 0x08,
      'delete': 0x2E,
      'insert': 0x2D,
      'home': 0x24,
      'end': 0x23,
      'page up': 0x21,
      'page down': 0x22,
      'arrow left': 0x25,
      'arrow up': 0x26,
      'arrow right': 0x27,
      'arrow down': 0x28,
      'f1': 0x70,
      'f2': 0x71,
      'f3': 0x72,
      'f4': 0x73,
      'f5': 0x74,
      'f6': 0x75,
      'f7': 0x76,
      'f8': 0x77,
      'f9': 0x78,
      'f10': 0x79,
      'f11': 0x7A,
      'f12': 0x7B,
      'space': 0x20,
      'caps lock': 0x14,
      'minus': 0xBD,
      'equal': 0xBB,
      'bracket left': 0xDB,
      'bracket right': 0xDD,
      'backslash': 0xDC,
      'semicolon': 0xBA,
      'quote': 0xDE,
      'comma': 0xBC,
      'period': 0xBE,
      'slash': 0xBF,
      'backquote': 0xC0,
      'numpad enter': 0x0D,
      'numpad decimal': 0x6E,
      'numpad divide': 0x6F,
      'numpad multiply': 0x6A,
      'numpad subtract': 0x6D,
      'numpad add': 0x6B,
    };
    if (vkMap.containsKey(keyName)) return vkMap[keyName]!;

    final keyLetter = RegExp(r'^key\s+([a-z])$').firstMatch(keyName);
    if (keyLetter != null) {
      return keyLetter.group(1)!.toUpperCase().codeUnitAt(0);
    }

    final digit = RegExp(r'^digit\s+([0-9])$').firstMatch(keyName);
    if (digit != null) {
      return digit.group(1)!.codeUnitAt(0);
    }

    final numpadDigit = RegExp(r'^numpad\s*([0-9])$').firstMatch(keyName);
    if (numpadDigit != null) {
      return 0x60 + int.parse(numpadDigit.group(1)!);
    }

    final label = (payload['character'] ?? '').toString();
    if (label.length == 1) {
      final c = label.codeUnitAt(0);
      if ((c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) {
        return c >= 0x61 && c <= 0x7A ? c - 32 : c;
      }
    }
    return 0;
  }

  String _buildSendKeysStroke(Map<String, dynamic> payload) {
    final phase = (payload['phase'] ?? 'down').toString();
    if (phase != 'down') return '';
    if (_isModifierKey(payload)) return '';

    final keyName = (payload['keyName'] ?? '').toString();
    final character = (payload['character'] ?? '').toString();
    final isNumpad = payload['isNumpad'] == true;
    final ctrl = payload['ctrl'] == true;
    final alt = payload['alt'] == true;
    final shift = payload['shift'] == true;
    final meta = payload['meta'] == true;
    final altGraph = payload['altGraph'] == true;

    final cacheKey = [
      _localKeyboardLayout,
      _localKeyboardLayoutFamily,
      _remoteKeyboardLayout,
      _remoteKeyboardLayoutFamily,
      keyName,
      character,
      isNumpad,
      ctrl,
      alt,
      shift,
      meta,
      altGraph,
    ].join('|');
    final cached = _sendKeysStrokeCache[cacheKey];
    if (cached != null) return cached;

    String token = '';
    final mappedChar = _mapCharacterForLayout(character, payload);
    if (_isPrintableCharacter(mappedChar) && !(ctrl || meta) && (altGraph || !alt)) {
      token = _escapeSendKeysChar(mappedChar);
    } else {
      token = _specialKeyToSendKeysToken(keyName);
      if (token.isEmpty) {
        final lower = keyName.toLowerCase();
        final keyLetter = RegExp(r'^key\s+([a-z])$').firstMatch(lower);
        if (keyLetter != null) {
          token = _escapeSendKeysChar(keyLetter.group(1)!);
        }
        final digit = RegExp(r'^digit\s+([0-9])$').firstMatch(lower);
        if (token.isEmpty && digit != null) {
          token = _escapeSendKeysChar(digit.group(1)!);
        }
      }
      if (token.isEmpty && keyName.length == 1) {
        token = _escapeSendKeysChar(keyName);
      }
      if (token.isEmpty && isNumpad) {
        final digit = RegExp(r'([0-9])').firstMatch(keyName);
        if (digit != null) {
          token = '{NUMPAD${digit.group(1)!}}';
        }
      }
    }

    if (token.isEmpty) {
      _sendKeysStrokeCache[cacheKey] = '';
      return '';
    }

    final mods = StringBuffer();
    if (ctrl) mods.write('^');
    if (alt && !altGraph) mods.write('%');
    if (shift) mods.write('+');
    final stroke = '${mods}${token}';
    _sendKeysStrokeCache[cacheKey] = stroke;
    return stroke;
  }

  String _mapCharacterForLayout(String character, [Map<String, dynamic>? payload]) {
    if (!_isPrintableCharacter(character)) return character;
    final sourceFamily = (payload?['sourceLayoutFamily'] ?? _remoteKeyboardLayoutFamily).toString();
    final targetFamily = _localKeyboardLayoutFamily;
    if (sourceFamily == targetFamily || sourceFamily == 'unknown' || targetFamily == 'unknown') {
      return character;
    }
    return character;
  }

  bool _isModifierKey(Map<String, dynamic> payload) {
    final keyName = (payload['keyName'] ?? '').toString().toLowerCase();
    return keyName.contains('shift') ||
        keyName.contains('control') ||
        keyName.contains('ctrl') ||
        keyName.contains('alt') ||
        keyName.contains('meta') ||
        keyName.contains('command') ||
        keyName.contains('caps lock');
  }

  bool _isPrintableCharacter(String value) {
    if (value.length != 1) return false;
    final unit = value.codeUnitAt(0);
    return unit >= 0x20 && unit != 0x7F;
  }

  String _escapeSendKeysChar(String value) {
    if (value.isEmpty) return '';
    const escaped = r'+^%~(){}[]';
    if (escaped.contains(value)) {
      return '{$value}';
    }
    return value;
  }

  String _specialKeyToSendKeysToken(String keyName) {
    final normalized = keyName.toLowerCase();
    const map = {
      'enter': '{ENTER}',
      'backspace': '{BACKSPACE}',
      'tab': '{TAB}',
      'escape': '{ESC}',
      'arrow left': '{LEFT}',
      'arrow right': '{RIGHT}',
      'arrow up': '{UP}',
      'arrow down': '{DOWN}',
      'delete': '{DELETE}',
      'home': '{HOME}',
      'end': '{END}',
      'page up': '{PGUP}',
      'page down': '{PGDN}',
      'space': ' ',
      'f1': '{F1}',
      'f2': '{F2}',
      'f3': '{F3}',
      'f4': '{F4}',
      'f5': '{F5}',
      'f6': '{F6}',
      'f7': '{F7}',
      'f8': '{F8}',
      'f9': '{F9}',
      'f10': '{F10}',
      'f11': '{F11}',
      'f12': '{F12}',
      'numpad add': '{ADD}',
      'numpad subtract': '{SUBTRACT}',
      'numpad multiply': '{MULTIPLY}',
      'numpad divide': '{DIVIDE}',
      'numpad decimal': '{DECIMAL}',
      'numpad enter': '{ENTER}',
    };
    return map[normalized] ?? '';
  }

  bool _sendSessionPayload({
    required String messageType,
    required Map<String, dynamic> payload,
  }) {
    if (!_canSignal) {
      print('[RemoteSupportPage] Cannot signal: signalingService=${widget.signalingService}, userId=${widget.currentUserId}, sessionId=${widget.sessionId}');
      return false;
    }
    if (messageType != 'screen_frame' && messageType != 'input_event') {
      print('[RemoteSupportPage] Sending $messageType to ${widget.deviceId} via session ${widget.sessionId}');
    }
    final payloadWithChannel = Map<String, dynamic>.from(payload);
    payloadWithChannel.putIfAbsent(
      'channel',
      () => messageType == 'screen_frame'
          ? 'video'
          : (messageType == 'input_event' ? 'input' : 'control'),
    );
    return widget.signalingService!.sendSessionMessage(
      sessionId: (widget.sessionId ?? '').toString(),
      toUserId: widget.deviceId,
      messageType: messageType,
      payload: payloadWithChannel,
    );
  }

  void _sendCaptureStatus(String status, String detail) {
    if (!widget.sendLocalScreen) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final minIntervalMs = status == 'ok' ? 4000 : 1200;
    if (now - _lastCaptureStatusSentMs < minIntervalMs) return;
    _lastCaptureStatusSentMs = now;
    _sendSessionPayload(
      messageType: 'capture_status',
      payload: {
        'status': status,
        'detail': detail,
      },
    );
  }

  Future<io.ProcessResult> _runPowerShell(
    List<String> args, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final commands = <String>['powershell', 'powershell.exe', 'pwsh', 'pwsh.exe'];
    Object? lastError;
    for (final cmd in commands) {
      try {
        final process = await io.Process.start(cmd, args);
        final stdoutFuture = process.stdout.transform(utf8.decoder).join();
        final stderrFuture = process.stderr.transform(utf8.decoder).join();

        int exitCode;
        try {
          exitCode = await process.exitCode.timeout(timeout);
        } on TimeoutException {
          process.kill(io.ProcessSignal.sigterm);
          return io.ProcessResult(
            process.pid,
            124,
            '',
            'PowerShell timed out after ${timeout.inSeconds}s',
          );
        }

        final stdoutText = await stdoutFuture;
        final stderrText = await stderrFuture;
        return io.ProcessResult(process.pid, exitCode, stdoutText, stderrText);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('PowerShell executable not found');
  }

  Future<void> _applyRemoteKeyboardEvent(Map<String, dynamic> payload) async {
    // Keyboard System V2 - Remote Handler
    try {
      final keyboardEvent = KeyboardKeyEvent.fromJson(payload);

      // Inject the key using the best strategy for this layout
      final result = await _keyboardInjectionEngine.injectKeyboardEvent(
        keyboardEvent,
        hostLayout: _keyboardLayoutTranslator.hostLayout?.layoutId ?? 'unknown',
        hostLayoutFamily: _keyboardLayoutTranslator.hostLayoutFamily,
      );

      if (!result) {
        print('[Keyboard] V2 injection failed for ${keyboardEvent.keyName}, falling back to legacy injector');
        await _applyRemoteKeyboardEventLegacy(payload);
      }
    } catch (e) {
      print('[Keyboard] Remote handler error: $e. Falling back to legacy injector');
      try {
        await _applyRemoteKeyboardEventLegacy(payload);
      } catch (legacyError) {
        print('[Keyboard] Legacy fallback failed: $legacyError');
      }
    }
  }

  void _sendMoveIfNeeded(Offset p) {
    _localCursorX = p.dx;
    _localCursorY = p.dy;
    _pendingMove = p;
    if (_pendingMoveTimer?.isActive == true) return;

    // OPTIMIZATION: Increased frequency from 4ms to 10-15ms for better cursor responsiveness
    // while maintaining reasonable bandwidth usage
    _pendingMoveTimer = Timer(Duration(milliseconds: _cursorUpdateFreqMs), () {
      _pendingMoveTimer = null;
      _dispatchPendingMove();
    });
  }

  void _dispatchPendingMove() {
    final pending = _pendingMove;
    _pendingMove = null;
    if (pending == null) return;

    const epsilon = 0.0008;
    final sameAsLast = _lastSentMoveX != null &&
        _lastSentMoveY != null &&
        (pending.dx - _lastSentMoveX!).abs() < epsilon &&
        (pending.dy - _lastSentMoveY!).abs() < epsilon;
    if (sameAsLast) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final dtMs = (_lastMoveSentAtMs == 0)
        ? 0
        : (now - _lastMoveSentAtMs).clamp(1, 1000);
    final dx = _lastSentMoveX == null ? 0.0 : (pending.dx - _lastSentMoveX!);
    final dy = _lastSentMoveY == null ? 0.0 : (pending.dy - _lastSentMoveY!);
    final vx = dtMs > 0 ? (dx * 1000.0 / dtMs) : 0.0;
    final vy = dtMs > 0 ? (dy * 1000.0 / dtMs) : 0.0;
    final sendAbsolute = _lastSentMoveX == null ||
      !_remoteSupportsMoveDelta ||
      _moveDeltaSinceKeyframe >= 8 ||
      dx.abs() > 0.25 ||
      dy.abs() > 0.25;

    if (sendAbsolute) {
      _sendInputEvent(
        'move',
        normalizedX: pending.dx,
        normalizedY: pending.dy,
        extra: {
          'vx': vx,
          'vy': vy,
          'dtMs': dtMs,
        },
      );
      _moveDeltaSinceKeyframe = 0;
    } else {
      _sendInputEvent(
        'move_delta',
        extra: {
          'dx': dx,
          'dy': dy,
          'baseX': _lastSentMoveX,
          'baseY': _lastSentMoveY,
          'vx': vx,
          'vy': vy,
          'dtMs': dtMs,
        },
      );
      _moveDeltaSinceKeyframe++;
    }

    _lastSentMoveX = pending.dx;
    _lastSentMoveY = pending.dy;
    _lastMoveSentAtMs = now;
  }

  void _flushPendingMove() {
    if (_pendingMove == null) return;
    _pendingMoveTimer?.cancel();
    _pendingMoveTimer = null;
    _dispatchPendingMove();
  }

  void _scheduleRemoteFrameApply() {
    if (_pendingRemoteFrameTimer?.isActive == true) return;
    _pendingRemoteFrameTimer = Timer(const Duration(milliseconds: 16), () {
      _pendingRemoteFrameTimer = null;
      final frameData = _pendingRemoteFrameData;
      if (frameData == null || frameData.isEmpty) return;

      try {
        _remoteScreenFrame = base64Decode(frameData);
        if (_pendingRemoteFrameWidth != null && _pendingRemoteFrameHeight != null) {
          _remoteFrameWidth = _pendingRemoteFrameWidth!;
          _remoteFrameHeight = _pendingRemoteFrameHeight!;
          if (_remoteVirtualWidth <= 0 || _remoteVirtualHeight <= 0) {
            _remoteVirtualWidth = _remoteFrameWidth;
            _remoteVirtualHeight = _remoteFrameHeight;
          }
          if (_remoteRealWidth <= 0 || _remoteRealHeight <= 0) {
            _remoteRealWidth = _remoteFrameWidth;
            _remoteRealHeight = _remoteFrameHeight;
          }
          _remoteScaleRatio = _remoteVirtualWidth > 0
              ? (_remoteRealWidth / _remoteVirtualWidth)
              : 1.0;
        }
        if (_pendingRemoteScreenCount != null) {
          _remoteScreenCount = _pendingRemoteScreenCount!;
        }
        if (_pendingRemoteScreenIndex != null) {
          _selectedRemoteScreenIndex = _pendingRemoteScreenIndex!;
        }
        _pendingRemoteFrameData = null;
        _pendingRemoteFrameWidth = null;
        _pendingRemoteFrameHeight = null;
        _pendingRemoteScreenCount = null;
        _pendingRemoteScreenIndex = null;
        _framesReceived++;
        if (_framesReceived % 30 == 0) {
          print('[ScreenShare] Frame applied #$_framesReceived (${_remoteScreenFrame!.length} bytes)');
        }
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        print('[ScreenShare] Decode error: $e');
        _remoteScreenFrame = null;
      }
    });
  }

  void _startSessionTimer() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _sessionSeconds++;
        _sessionTime = _formatSessionTime(_sessionSeconds);
      });
    });
  }

  String _formatSessionTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _syncFullScreenState() async {
    final isFullScreen = await windowManager.isFullScreen();
    if (!mounted) return;
    setState(() => _isFullScreen = isFullScreen);
    await windowManager.setTitleBarStyle(
      isFullScreen ? TitleBarStyle.hidden : TitleBarStyle.normal,
    );
    if (isFullScreen) {
      _revealOverlayTemporarily();
    }
  }

  Future<void> _toggleFullScreen() async {
    final nextValue = !_isFullScreen;
    await windowManager.setTitleBarStyle(
      nextValue ? TitleBarStyle.hidden : TitleBarStyle.normal,
    );
    await windowManager.setFullScreen(nextValue);
    if (!mounted) return;
    setState(() => _isFullScreen = nextValue);
    if (_isFullScreen) {
      _revealOverlayTemporarily();
    }
    _showMessage(context, _isFullScreen ? tr('full_screen') : tr('exit_full_screen'), _getColors(context));
  }

  @override
  void dispose() {
    HostSessionOverlay.bindDisconnectHandler(null);
    _onKeyboardSessionDisconnected();
    if (widget.sendLocalScreen) {
      unawaited(HostSessionOverlay.stopOverlay());
    }

    // Cleanup cursor update timer and stopwatch
    _cursorUpdateTimer?.cancel();
    _cursorMovementStopwatch.stop();
    
    // Cleanup other resources
    _stopAllManagedRepeats();
    _pressedLogicalKeys.clear();
    _sendResetAllKeys();
    _audioUdpOfferTimer?.cancel();
    _audioUdpOfferTimer = null;
    _remoteAudioCompatTimer?.cancel();
    _remoteAudioCompatTimer = null;
    _audioUdpSocket?.close();
    _audioUdpSocket = null;
    _audioUdpReady = false;
    unawaited(_remoteAudioService.dispose());
    _sessionTimer?.cancel();
    _screenShareTimer?.cancel();
    _overlayHideTimer?.cancel();
    _diagnosticsTimer?.cancel();
    _recordingTimer?.cancel();
    _reconnectTimer?.cancel();
    _pendingMoveTimer?.cancel();
    _pendingMoveTimer = null;
    _pendingMove = null;
    _pendingRemoteFrameTimer?.cancel();
    _pendingRemoteFrameTimer = null;
    _pendingRemoteFrameData = null;
    _pendingRemoteMoveTimer?.cancel();
    _pendingRemoteMoveTimer = null;
    _pendingRemoteMoveX = null;
    _pendingRemoteMoveY = null;
    _keyboardAutoRestoreTimer?.cancel();
    _keyboardAutoRestoreTimer = null;
    _mouseAutoRestoreTimer?.cancel();
    _mouseAutoRestoreTimer = null;
    _releaseHostInputLock();
    _hostMouseButtonSafetyTimer?.cancel();
    _hostMouseButtonSafetyTimer = null;
    _hostMouseButtonDownType = null;
    _keyboardLayoutTimer?.cancel();
    _keyStateSyncTimer?.cancel();
    _signalSubscription?.cancel();
    _composerController.dispose();
    _chatScrollController.dispose();
    _remoteControlFocusNode.dispose();
        _keyboardLayoutTimer?.cancel();
        _keyboardLayoutTimer = null;
        _keyboardRepeatController.stopAllRepeats();
        _keyboardStateManager.forceReleaseAll(reason: 'dispose');
        _keyboardTransportLayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _getColors(context);
    final isController = !widget.sendLocalScreen;

    return Scaffold(
      appBar: isController || !_isFullScreen
          ? null
          : AppBar(
              backgroundColor: colors['bg']!,
              elevation: 0,
              title: Text(
                tr('remote_support_title'),
                style: TextStyle(color: colors['text']!),
              ),
            ),
      body: isController ? _buildControllerView(colors) : _buildRemoteAgentView(colors),
    );
  }

  Widget _buildControllerView(Map<String, Color> colors) {
    return MouseRegion(
      onHover: (event) {
        if (_hideAllHud) return;
        if (event.position.dy <= 42) {
          _revealOverlayTemporarily();
        }
      },
      onEnter: (_) => _revealOverlayTemporarily(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_panelMode != 'none') {
            setState(() => _panelMode = 'none');
          }
          _revealOverlayTemporarily();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent && event.position.dy <= 70) {
                    _revealOverlayTemporarily();
                  }
                },
                child: _buildRemoteCanvas(colors),
              ),
            ),
            if (_showTopOverlay && !_hideAllHud)
              Positioned(
                top: 10,
                left: 70,
                right: 16,
                child: _buildTopOverlayBar(colors),
              ),
            if (_showLeftFloatingButtons && !_hideAllHud)
              Positioned(
                top: 84,
                left: 12,
                child: _buildFloatingButtons(colors),
              ),
            if (_panelMode != 'none' && !_hideAllHud)
              Positioned(
                top: 76,
                left: 74,
                bottom: 20,
                width: 360,
                child: _buildContextPanel(colors),
              ),
            Positioned(
              top: 10,
              left: 12,
              child: Tooltip(
                message: _hideAllHud ? 'Show bars' : 'Hide bars',
                child: _buildSmallOverlayButton(
                  _hideAllHud ? Icons.visibility : Icons.visibility_off,
                  _toggleHudVisibility,
                  colors,
                ),
              ),
            ),
            if (_isDeviceLocked)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Lock mode enabled: remote user controls are restricted',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            if (_isSessionPaused)
              const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteAgentView(Map<String, Color> colors) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: Colors.black,
            child: Container(
              margin: EdgeInsets.zero,
              child: Stack(
                children: [
                  Positioned.fill(child: _buildRemoteCanvas(colors)),
                  if (_isLockedForRemoteUser)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black87,
                        alignment: Alignment.center,
                        child: const Text(
                          'This machine is locked by remote operator',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (_isSessionPausedRemote)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.6),
                        alignment: Alignment.center,
                        child: const Text(
                          'Session paused by remote operator',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopOverlayBar(Map<String, Color> colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors['bg']!.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors['border']!),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 9, color: _isConnected ? Colors.green : Colors.redAccent),
          const SizedBox(width: 6),
          Text(_connectionStatus, style: TextStyle(color: colors['text']!, fontSize: 12)),
          const SizedBox(width: 10),
          Text('Session $_sessionTime', style: TextStyle(color: colors['textSecondary']!, fontSize: 12)),
          const SizedBox(width: 10),
          Icon(_isEncrypted ? Icons.lock : Icons.lock_open, size: 12, color: _isEncrypted ? Colors.green : Colors.orange),
          const SizedBox(width: 4),
          Text(_encryptionType, style: TextStyle(color: colors['textSecondary']!, fontSize: 12)),
          const SizedBox(width: 10),
          Text('Ping $_pingMs ms', style: TextStyle(color: colors['textSecondary']!, fontSize: 12)),
          const SizedBox(width: 10),
          Text(_bandwidthText, style: TextStyle(color: colors['textSecondary']!, fontSize: 12)),
          const SizedBox(width: 10),
          Text('FPS $_fpsText', style: TextStyle(color: colors['textSecondary']!, fontSize: 12)),
          const SizedBox(width: 10),
          Text('Loss $_packetLossText', style: TextStyle(color: colors['textSecondary']!, fontSize: 12)),
          const Spacer(),
          _buildSmallOverlayButton(Icons.screenshot_monitor, _takeScreenshot, colors),
          const SizedBox(width: 6),
          _buildSmallOverlayButton(
            _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
            _toggleRecording,
            colors,
            isActive: _isRecording,
          ),
          const SizedBox(width: 6),
          _buildSmallOverlayButton(
            _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
            _toggleFullScreen,
            colors,
          ),
          const SizedBox(width: 6),
          _buildSmallOverlayButton(Icons.close, () => _closeSession(), colors, isDanger: true),
        ],
      ),
    );
  }

  Widget _buildSmallOverlayButton(
    IconData icon,
    VoidCallback onTap,
    Map<String, Color> colors, {
    bool isActive = false,
    bool isDanger = false,
  }) {
    final bg = isDanger
        ? Colors.redAccent
        : (isActive ? colors['accent']! : colors['cardBg']!);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }

  Widget _buildFloatingButtons(Map<String, Color> colors) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors['bg']!.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors['border']!),
      ),
      child: Column(
        children: [
          _buildRoundToolButton(Icons.swap_horiz, 'Transfer', () => _togglePanel('transfer'), colors),
          const SizedBox(height: 8),
          _buildRoundToolButton(Icons.settings_remote, 'System', () => _togglePanel('system'), colors),
          const SizedBox(height: 8),
          _buildRoundToolButton(Icons.network_check, 'Network', () => _togglePanel('network'), colors),
        ],
      ),
    );
  }

  Widget _buildRoundToolButton(
    IconData icon,
    String label,
    VoidCallback onTap,
    Map<String, Color> colors,
  ) {
    final selected = _panelMode == label.toLowerCase();
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: selected ? colors['accent']! : colors['cardBg']!,
            shape: BoxShape.circle,
            border: Border.all(color: colors['border']!),
          ),
          child: Icon(icon, color: selected ? Colors.white : colors['text']!, size: 18),
        ),
      ),
    );
  }

  void _togglePanel(String mode) {
    setState(() {
      _panelMode = _panelMode == mode ? 'none' : mode;
    });
    _revealOverlayTemporarily();
  }

  Widget _buildContextPanel(Map<String, Color> colors) {
    Widget content;
    switch (_panelMode) {
      case 'chat':
        content = _buildChatContent(colors);
        break;
      case 'transfer':
        content = _buildTransferContent(colors);
        break;
      case 'network':
        content = _buildNetworkPanel(colors);
        break;
      default:
        content = _buildSystemPanel(colors);
        break;
    }
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors['bg']!.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors['border']!),
        ),
        child: content,
      ),
    );
  }

  Widget _buildRemoteCanvas(Map<String, Color> colors) {
    if (_isPrivacyModeForRemote) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.visibility_off, size: 72, color: Colors.white),
            SizedBox(height: 14),
            Text('Screen is hidden for privacy', style: TextStyle(color: Colors.white, fontSize: 17)),
          ],
        ),
      );
    }

    if (_remoteScreenFrame == null) {
      final statusText = widget.sendLocalScreen
          ? _hostSessionBannerText
          : (_captureError.isNotEmpty
              ? 'Error: $_captureError'
              : (_isConnected ? 'Connected successfully' : 'Error: disconnected'));
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _captureError.isEmpty ? 'Waiting for remote stream...' : 'Capture issue: $_captureError',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: statusText.toLowerCase().startsWith('error')
                    ? Colors.redAccent.withValues(alpha: 0.9)
                    : Colors.black54,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        IgnorePointer(
          ignoring: _isSessionPaused,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: KeyboardListener(
              focusNode: _remoteControlFocusNode,
              autofocus: !widget.sendLocalScreen,
              onKeyEvent: (event) {
                if (!_canSendRemoteInput || _isDeviceLocked || _isSessionPaused || !_keyboardInputEnabledForUser2) {
                  return;
                }

                if (event is KeyDownEvent) {
                  final logical = event.logicalKey.keyId;
                  final managed = _isManagedRepeatKey(event.logicalKey);
                  final modifier = _isModifierLogical(event.logicalKey);
                  if ((managed || modifier) && _pressedLogicalKeys.contains(logical)) return;
                  _pressedLogicalKeys.add(logical);

                  // TeamViewer-style: forward controller keydown directly to host.
                  _sendKeyboardEvent(event, phase: 'down');

                  if (managed) {
                    _startManagedRepeat(event);
                  }
                }

                if (event is KeyUpEvent) {
                  _stopManagedRepeat(event.logicalKey.keyId);
                  _pressedLogicalKeys.remove(event.logicalKey.keyId);

                  // TeamViewer-style: forward controller keyup directly to host.
                  _sendKeyboardEvent(event, phase: 'up');
                }
              },
              child: Builder(
                builder: (localContext) {
                  Offset? normalize(Offset local) {
                    final box = localContext.findRenderObject();
                    if (box is! RenderBox) return null;
                    final w = box.size.width;
                    final h = box.size.height;
                    if (w <= 0 || h <= 0) return null;
                    _maybeSendViewportHint(Size(w, h));
                    return _normalizeLocalToRemote(local, Size(w, h));
                  }

                  return Listener(
                    onPointerDown: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                        ? (event) {
                            _revealOverlayTemporarily();
                            final p = normalize(event.localPosition);
                            if (p == null) return;
                            _localCursorX = p.dx;
                            _localCursorY = p.dy;
                            _flushPendingMove();
                            _rightButtonPressed = event.buttons == kSecondaryMouseButton;
                            _mouseButtonDown = true;
                            _sendInputEvent(
                              _rightButtonPressed ? 'right_down' : 'left_down',
                              normalizedX: p.dx,
                              normalizedY: p.dy,
                            );
                            _remoteControlFocusNode.requestFocus();
                          }
                        : (_) => _revealOverlayTemporarily(),
                    onPointerHover: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                        ? (event) {
                            final now = DateTime.now().millisecondsSinceEpoch;
                          if (now - _lastPointerMoveMs < 1) return;
                            _lastPointerMoveMs = now;
                            final p = normalize(event.localPosition);
                            if (p == null) return;
                            _sendMoveIfNeeded(p);
                          }
                        : null,
                    onPointerMove: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                        ? (event) {
                            final now = DateTime.now().millisecondsSinceEpoch;
                          if (now - _lastPointerMoveMs < 1) return;
                            _lastPointerMoveMs = now;
                            final p = normalize(event.localPosition);
                            if (p == null) return;
                            _sendMoveIfNeeded(p);
                          }
                        : null,
                    onPointerUp: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                        ? (event) {
                          if (!_mouseButtonDown) return;
                            final p = normalize(event.localPosition);
                            if (p == null) return;
                            _localCursorX = p.dx;
                            _localCursorY = p.dy;
                            _flushPendingMove();
                            _sendInputEvent(
                              _rightButtonPressed ? 'right_up' : 'left_up',
                              normalizedX: p.dx,
                              normalizedY: p.dy,
                            );
                            _mouseButtonDown = false;
                            _rightButtonPressed = false;
                          }
                        : null,
                    onPointerCancel: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                        ? (event) {
                            if (!_mouseButtonDown) return;
                            _flushPendingMove();
                            _sendInputEvent(
                              _rightButtonPressed ? 'right_up' : 'left_up',
                              normalizedX: _localCursorX,
                              normalizedY: _localCursorY,
                            );
                            _mouseButtonDown = false;
                            _rightButtonPressed = false;
                          }
                        : null,
                    onPointerSignal: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                        ? (event) {
                            if (event is PointerScrollEvent) {
                              _flushPendingMove();
                              _sendWheelFromDelta(event.scrollDelta.dy);
                            }
                          }
                        : null,
                    onPointerPanZoomUpdate: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                        ? (event) {
                            final panDy = event.panDelta.dy;
                            if (panDy.abs() > 0.01) {
                              _flushPendingMove();
                              _sendWheelFromDelta(panDy);
                            }

                            // Trackpad pinch fallback: map scale changes to wheel steps.
                            final scaleDelta = event.scale - 1.0;
                            if (scaleDelta.abs() >= 0.01) {
                              final wheel = scaleDelta > 0 ? 120 : -120;
                              _sendInputEvent(
                                'wheel',
                                wheelDelta: wheel,
                                normalizedX: _localCursorX,
                                normalizedY: _localCursorY,
                              );
                            }
                          }
                        : null,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                        final viewportWidth = constraints.maxWidth;
                        final viewportHeight = constraints.maxHeight;
                        if (viewportWidth <= 0 || viewportHeight <= 0) {
                          return const SizedBox.shrink();
                        }

                        // Keep host scaling in sync after window/fullscreen transitions.
                        _maybeSendViewportHint(Size(viewportWidth, viewportHeight));

                        final sourceWidth = _remoteFrameWidth > 0 ? _remoteFrameWidth : _remoteVirtualWidth;
                        final sourceHeight = _remoteFrameHeight > 0 ? _remoteFrameHeight : _remoteVirtualHeight;

                        return Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: sourceWidth.toDouble(),
                              height: sourceHeight.toDouble(),
                              child: _buildRemoteCursorOverlay(
                                Image.memory(
                                  _remoteScreenFrame!,
                                  width: sourceWidth.toDouble(),
                                  height: sourceHeight.toDouble(),
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                          ),
                        );
                        },
                      ),
                  );
                },
              ),
            ),
          ),
        ),
        // Pause overlay
        if (_isSessionPaused)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.pause, size: 64, color: Colors.white),
                    const SizedBox(height: 16),
                    const Text(
                      'Session Paused',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _togglePauseSession,
                          icon: const Icon(Icons.play_circle),
                          label: const Text('Resume'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () => _closeSession(notifyPeer: true),
                          icon: const Icon(Icons.close),
                          label: const Text('Disconnect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChatContent(Map<String, Color> colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Chat', style: TextStyle(color: colors['text']!, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.close, color: colors['textSecondary']!),
              onPressed: () => setState(() => _panelMode = 'none'),
            ),
          ],
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors['bg']!,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors['border']!),
            ),
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
              controller: _chatScrollController,
              itemCount: _chatMessages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_chatMessages[index], colors);
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colors['cardBg']!,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: colors['border']!),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composerController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  style: TextStyle(color: colors['text']!),
                  decoration: InputDecoration(
                    hintText: tr('chat_message_hint'),
                    hintStyle: TextStyle(color: colors['textSecondary']!),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors['accent']!,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, size: 20),
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransferContent(Map<String, Color> colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('File Transfer', style: TextStyle(color: colors['text']!, fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.close, color: colors['textSecondary']!),
              onPressed: () => setState(() => _panelMode = 'none'),
            ),
          ],
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors['bg']!,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors['border']!),
            ),
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
              itemCount: _transfers.length,
              itemBuilder: (context, index) {
                return _buildTransferItem(index, _transfers[index], colors);
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                Icons.upload,
                'Send',
                () => setState(() => _transferMode = 'send'),
                colors,
                isActive: _transferMode == 'send',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                Icons.download,
                'Receive',
                () => setState(() => _transferMode = 'receive'),
                colors,
                isActive: _transferMode == 'receive',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors['cardBg']!,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors['border']!),
          ),
          child: Text(
            _transferMode == 'send'
                ? 'Send mode: choose a file to upload. Name, size, path, speed and progress are tracked.'
                : 'Receive mode: choose destination path. Incoming files are saved to this location.',
            style: TextStyle(color: colors['textSecondary']!, fontSize: 12),
          ),
        ),
        const SizedBox(height: 10),
        if (_transferMode == 'send')
          _buildFileButton(
            icon: Icons.cloud_upload_outlined,
            label: tr('btn_upload_file'),
            onPressed: _handleUpload,
            colors: colors,
          )
        else
          _buildFileButton(
            icon: Icons.folder_open,
            label: 'Select receive folder',
            onPressed: _selectReceiveTargetPath,
            colors: colors,
          ),
        if (_transferMode == 'receive' && _receiveTargetPath.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Receive path: $_receiveTargetPath',
            style: TextStyle(color: colors['textSecondary']!, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildSystemPanel(Map<String, Color> colors) {
    return ListView(
      children: [
        Text('System Controls', style: TextStyle(color: colors['text']!, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text('Session Management', style: TextStyle(color: colors['text']!, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                _isSessionPaused ? Icons.play_circle : Icons.pause_circle,
                _isSessionPaused ? 'Resume Session' : 'Pause Session',
                _togglePauseSession,
                colors,
                isActive: _isSessionPaused,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                Icons.restart_alt,
                'Restart Input Control',
                _restartInputControl,
                colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('User 2 Input Control', style: TextStyle(color: colors['text']!, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                _keyboardInputEnabledForUser2 ? Icons.keyboard : Icons.keyboard_hide,
                _keyboardInputEnabledForUser2 ? 'Keyboard ON' : 'Keyboard OFF',
                _toggleUser2KeyboardPolicy,
                colors,
                isActive: _keyboardInputEnabledForUser2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                _mouseInputEnabledForUser2 ? Icons.mouse : Icons.mouse_outlined,
                _mouseInputEnabledForUser2 ? 'Mouse ON' : 'Mouse OFF',
                _toggleUser2MousePolicy,
                colors,
                isActive: _mouseInputEnabledForUser2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildActionButton(Icons.task_alt, 'Task Manager', () => _sendSystemAction('task_manager'), colors),
            _buildActionButton(Icons.folder_open, 'File Explorer', () => _sendSystemAction('file_explorer'), colors),
            _buildActionButton(Icons.terminal, 'Terminal', () => _sendSystemAction('terminal'), colors),
            _buildActionButton(Icons.settings, 'Control Panel / Settings', () => _sendSystemAction('control_panel'), colors),
            _buildActionButton(Icons.playlist_play, 'Run Dialog', () => _sendSystemAction('run_dialog'), colors),
            _buildActionButton(Icons.lock_outline, 'Lock Screen', () => _sendSystemAction('lock_screen'), colors),
            _buildActionButton(Icons.logout, 'Log Out', () => _sendSystemAction('logout'), colors),
          ],
        ),
        const SizedBox(height: 14),
        Text('Display', style: TextStyle(color: colors['text']!, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _buildPresetSelectors(colors),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                _audioEnabled ? Icons.volume_up : Icons.volume_off,
                _audioEnabled ? 'Audio ON' : 'Audio OFF',
                _toggleAudio,
                colors,
                isActive: _audioEnabled,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                _isBlackoutMode ? Icons.visibility_off : Icons.visibility,
                'Privacy',
                _toggleBlackout,
                colors,
                isActive: _isBlackoutMode,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Remote Audio Volume', style: TextStyle(color: colors['text']!, fontWeight: FontWeight.w600)),
        Slider(
          value: _remoteAudioVolume,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          label: '${(_remoteAudioVolume * 100).round()}%',
          onChanged: (value) {
            setState(() => _remoteAudioVolume = value);
            unawaited(_remoteAudioService.setClientVolume(value));
          },
        ),
        Text('Remote Audio Bitrate (${_remoteAudioBitrateKbps} kbps)', style: TextStyle(color: colors['text']!, fontWeight: FontWeight.w600)),
        Slider(
          value: _remoteAudioBitrateKbps.toDouble(),
          min: 64,
          max: 256,
          divisions: 12,
          label: '$_remoteAudioBitrateKbps kbps',
          onChanged: (value) {
            final next = ((value / 16).round() * 16).clamp(64, 256);
            setState(() => _remoteAudioBitrateKbps = next);
            if (widget.sendLocalScreen) {
              unawaited(_remoteAudioService.updateHostBitrate(next));
            } else {
              _sendRemoteAudioPayload({'kind': 'config', 'bitrateKbps': next});
            }
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                _isDeviceLocked ? Icons.lock : Icons.lock_open,
                'Lock Mode',
                _lockDevice,
                colors,
                isActive: _isDeviceLocked,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                Icons.restart_alt,
                _isRebooting ? 'Rebooting...' : 'Reboot',
                _rebootDevice,
                colors,
                isActive: _isRebooting,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text('File Paths', style: TextStyle(color: colors['text']!, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors['cardBg']!,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors['border']!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Screenshots: $_screenshotPath',
                style: TextStyle(color: colors['textSecondary']!, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Recordings: $_recordingsPath',
                style: TextStyle(color: colors['textSecondary']!, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                Icons.folder,
                'Change Paths',
                _showPathCustomizationDialog,
                colors,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showPathCustomizationDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        String tempScreenshot = _screenshotPath;
        String tempRecordings = _recordingsPath;
        return AlertDialog(
          title: const Text('Customize File Paths'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Screenshots Path:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: tempScreenshot),
                  decoration: const InputDecoration(hintText: 'Enter screenshots path'),
                  onChanged: (v) => tempScreenshot = v,
                ),
                const SizedBox(height: 16),
                const Text('Recordings Path:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: tempRecordings),
                  decoration: const InputDecoration(hintText: 'Enter recordings path'),
                  onChanged: (v) => tempRecordings = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (tempScreenshot.trim().isNotEmpty && tempRecordings.trim().isNotEmpty) {
                  try {
                    io.Directory(tempScreenshot).createSync(recursive: true);
                    io.Directory(tempRecordings).createSync(recursive: true);
                    setState(() {
                      _screenshotPath = tempScreenshot;
                      _recordingsPath = tempRecordings;
                    });
                    _showMessage(context, 'Paths updated successfully', _getColors(context));
                    Navigator.pop(ctx);
                  } catch (e) {
                    _showMessage(context, 'Error creating directories: $e', _getColors(context));
                  }
                } else {
                  _showMessage(context, 'Both paths cannot be empty', _getColors(context));
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPresetSelectors(Map<String, Color> colors) {
    return Column(
      children: [
        _buildScreenTabs(colors),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _captureResolutionLabel,
          style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            labelText: 'Resolution',
            labelStyle: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700),
          ),
          items: const [
            DropdownMenuItem(value: 'Full Screen', child: Text('Full Screen')),
            DropdownMenuItem(value: 'Adapter', child: Text('Adapter')),
          ],
          onChanged: (v) {
            if (v != null) _setResolutionPreset(v);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _qualityLabel,
          style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(
            labelText: 'Quality',
            labelStyle: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w700),
          ),
          items: const [
            DropdownMenuItem(value: 'Auto', child: Text('Auto (connection-based)')),
            DropdownMenuItem(value: 'Low', child: Text('Low (performance)')),
            DropdownMenuItem(value: 'Medium', child: Text('Medium')),
            DropdownMenuItem(value: 'High', child: Text('High (quality)')),
            DropdownMenuItem(value: 'Ultra', child: Text('Ultra (max bandwidth)')),
          ],
          onChanged: (v) {
            if (v != null) _setQualityPreset(v);
          },
        ),
      ],
    );
  }

  Widget _buildScreenTabs(Map<String, Color> colors) {
    final tabs = List<int>.generate(_remoteScreenCount, (i) => i);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Remote Screens (${_remoteScreenCount})',
          style: TextStyle(color: colors['textSecondary']!, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: tabs.map((i) {
            final selected = i == _selectedRemoteScreenIndex;
            return InkWell(
              onTap: () {
                setState(() => _selectedRemoteScreenIndex = i);
                _sendDisplayConfig();
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? colors['accent']! : colors['cardBg']!,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors['border']!),
                ),
                child: Text(
                  'Screen ${i + 1}',
                  style: TextStyle(
                    color: selected ? Colors.white : colors['text']!,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildNetworkPanel(Map<String, Color> colors) {
    return ListView(
      children: [
        Text('Network Tools', style: TextStyle(color: colors['text']!, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _buildMetricLine('Ping', '$_pingMs ms', colors),
        _buildMetricLine('Connection', _isConnected ? 'Connected' : 'Disconnected', colors),
        _buildMetricLine('Bitrate', _bandwidthText, colors),
        _buildMetricLine('FPS', _fpsText, colors),
        _buildMetricLine('Frame latency', '${_frameAvgLatencyMs.toStringAsFixed(1)} ms', colors),
        _buildMetricLine('Packet loss', _packetLossText, colors),
        _buildMetricLine('Protocol', 'v$_remoteProtocolVersion', colors),
        _buildMetricLine(
          'Remote (real)',
          '${_remoteRealWidth > 0 ? _remoteRealWidth : _remoteFrameWidth}x${_remoteRealHeight > 0 ? _remoteRealHeight : _remoteFrameHeight}',
          colors,
        ),
        _buildMetricLine(
          'Remote (virtual)',
          '${_remoteVirtualWidth > 0 ? _remoteVirtualWidth : _remoteFrameWidth}x${_remoteVirtualHeight > 0 ? _remoteVirtualHeight : _remoteFrameHeight}',
          colors,
        ),
        _buildMetricLine('Scale ratio', _remoteScaleRatio.toStringAsFixed(3), colors),
        _buildMetricLine(
          'Peer Capabilities',
          'delta=${_remoteSupportsMoveDelta ? 'on' : 'off'} viewport=${_remoteSupportsViewportHint ? 'on' : 'off'}',
          colors,
        ),
        _buildMetricLine('Quality', _connectionQualityText, colors),
        _buildMetricLine('Frames RX', '$_framesReceived', colors),
        _buildMetricLine('Frames TX', '$_framesSent', colors),
        const SizedBox(height: 10),
        _buildActionButton(Icons.refresh, 'Refresh Diagnostics', () => _refreshPing(), colors),
      ],
    );
  }

  Widget _buildMetricLine(String label, String value, Map<String, Color> colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: colors['cardBg']!,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors['border']!),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: colors['textSecondary']!)),
          const Spacer(),
          Text(value, style: TextStyle(color: colors['text']!, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildTransferItem(
    int index,
    Map<String, String> transfer,
    Map<String, Color> colors,
  ) {
    final type = transfer['type'] ?? 'sent';
    final fileName = transfer['fileName'] ?? '';
    final from = transfer['from'] ?? '';
    final fileSize = transfer['fileSize'] ?? '';
    final path = transfer['path'] ?? '-';
    final status = transfer['status'] ?? '';
    final speed = transfer['speed'] ?? '';
    final progress = transfer['progress'] ?? '';
    final isReceived = type == 'received';
    final icon = isReceived ? Icons.get_app : Icons.upload_file;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isReceived ? colors['bg']! : colors['cardBg']!,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isReceived ? colors['accent']! : colors['border']!,
            width: isReceived ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors['accent'], size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      color: colors['text'],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isReceived
                        ? 'Reâ”œÂºu de: $from${fileSize.isNotEmpty ? '  Î“Ã‡Ã³  $fileSize' : ''}'
                        : 'Envoyâ”œâŒ${fileSize.isNotEmpty ? '  Î“Ã‡Ã³  $fileSize' : ''}',
                    style: TextStyle(color: colors['textSecondary'], fontSize: 10),
                  ),
                  if (path.isNotEmpty)
                    Text(
                      'Path: $path',
                      style: TextStyle(color: colors['textSecondary'], fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (status.isNotEmpty || speed.isNotEmpty || progress.isNotEmpty)
                    Text(
                      'Status: $status  ${progress.isNotEmpty ? 'Î“Ã‡Ã³ $progress%' : ''}  ${speed.isNotEmpty ? 'Î“Ã‡Ã³ $speed' : ''}',
                      style: TextStyle(color: colors['textSecondary'], fontSize: 10),
                    ),
                ],
              ),
            ),
            if (isReceived)
              Tooltip(
                message: 'Sauvegarder sur disque',
                child: InkWell(
                  onTap: () => _saveReceivedFile(transfer),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors['accent']!,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.save_alt, color: Colors.white, size: 14),
                  ),
                ),
              )
            else ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Retry',
                child: InkWell(
                  onTap: () => _retryTransfer(index),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors['cardBg']!,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors['border']!),
                    ),
                    child: Icon(Icons.refresh, color: colors['text'], size: 14),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Cancel',
                child: InkWell(
                  onTap: () => _cancelTransfer(index),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade500,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _cancelTransfer(int index) {
    if (index < 0 || index >= _transfers.length) return;
    final removed = _transfers[index]['fileName'] ?? 'transfer';
    setState(() {
      _transfers.removeAt(index);
    });
    _showMessage(context, 'Canceled: $removed', _getColors(context));
  }

  void _retryTransfer(int index) {
    if (index < 0 || index >= _transfers.length) return;
    final fileName = _transfers[index]['fileName'] ?? '';
    if (fileName.isEmpty) return;
    setState(() {
      _transfers[index]['status'] = 'Retried';
      _transfers[index]['progress'] = '100';
    });
    _showMessage(context, 'Retried: $fileName', _getColors(context));
  }

  Widget _buildFileButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Map<String, Color> colors,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors['accent']!,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String message, Map<String, Color> colors) {
    final isPeer = message.startsWith('Peer::');
    final clean = isPeer ? message.substring('Peer::'.length) : message.replaceFirst('You: ', '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isPeer ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isPeer ? Colors.black : Colors.blue,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                clean,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final value = _composerController.text.trim();
    if (value.isEmpty) return;

    print('[RemoteSupportPage] Sending chat: $value');

    setState(() {
      _chatMessages.add('You: $value');
      _sendSessionPayload(
        messageType: 'chat',
        payload: {'text': value},
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.jumpTo(_chatScrollController.position.maxScrollExtent);
      }
    });
    _composerController.clear();
  }

  Future<void> _handleUpload() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) {
      _showMessage(context, tr('upload_canceled'), _getColors(context));
      return;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _showMessage(context, tr('upload_canceled'), _getColors(context));
      return;
    }
    const maxSize = 8 * 1024 * 1024; // 8 MB
    if (bytes.length > maxSize) {
      _showMessage(context, 'Fichier trop grand (max 8 MB)', _getColors(context));
      return;
    }
    final fileName = file.name;
    final base64Data = base64Encode(bytes);
    _sendSessionPayload(
      messageType: 'upload',
      payload: {
        'fileName': fileName,
        'fileSize': bytes.length,
        'fileData': base64Data,
      },
    );
    setState(() {
      _transfers.add({
        'type': 'sent',
        'fileName': fileName,
        'from': 'You',
        'path': file.path ?? 'Unknown path',
        'status': 'Sent',
        'speed': '${(bytes.length / 1024).toStringAsFixed(1)} KB/s',
        'progress': '100',
        'fileSize': '${(bytes.length / 1024).toStringAsFixed(1)} KB',
        'fileData': '',
      });
    });
    _showMessage(context, '${tr('selected_for_upload')}: $fileName', _getColors(context));
  }

  Future<void> _saveReceivedFile(Map<String, String> transfer) async {
    final fileData = transfer['fileData'] ?? '';
    if (fileData.isEmpty) {
      _showMessage(context, 'Aucune donnâ”œâŒe disponible', _getColors(context));
      return;
    }
    String? outputPath;
    if (_receiveTargetPath.isNotEmpty) {
      final fileName = transfer['fileName'] ?? 'fichier_recu';
      outputPath = '$_receiveTargetPath\\$fileName';
    } else {
      outputPath = await FilePicker.platform.saveFile(
        dialogTitle: tr('save_downloaded_file'),
        fileName: transfer['fileName'] ?? 'fichier_recu',
      );
    }
    if (!mounted || outputPath == null || outputPath.isEmpty) return;
    try {
      final bytes = base64Decode(fileData);
      await io.File(outputPath).writeAsBytes(bytes);
      if (!mounted) return;
      _showMessage(context, 'Fichier sauvegardâ”œâŒ: $outputPath', _getColors(context));
    } catch (e) {
      if (!mounted) return;
      _showMessage(context, 'Erreur sauvegarde: $e', _getColors(context));
    }
  }

  void _showMessage(BuildContext context, String message, Map<String, Color> colors) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colors['accent']!,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _selectReceiveTargetPath() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose receive folder',
    );
    if (!mounted || dir == null || dir.isEmpty) return;
    setState(() => _receiveTargetPath = dir);
    
    // Request list of files from remote machine for browsing
    _sendSessionPayload(
      messageType: 'list_files',
      payload: {'path': ''},
    );
    
    _showMessage(context, 'Receive folder set: $dir', _getColors(context));
  }

  Future<void> _takeScreenshot() async {
    if (!_isConnected) return;

    if (_remoteScreenFrame == null || _remoteScreenFrame!.isEmpty) {
      _showMessage(context, tr('screenshot_failed'), _getColors(context));
      return;
    }

    try {
      final screenshotsDir = io.Directory(_screenshotPath);
      if (!screenshotsDir.existsSync()) {
        screenshotsDir.createSync(recursive: true);
      }
      final outputPath = '${screenshotsDir.path}\\remote_screenshot_${_timestampForFile()}.jpg';

      await io.File(outputPath).writeAsBytes(_remoteScreenFrame!, flush: true);
      if (!mounted) return;
      final time = DateTime.now().toIso8601String();
      setState(() {
        _chatMessages.add('You: Screenshot saved at $time');
      });
      _showMessage(
        context,
        '${tr('screenshot_saved_to')}: $outputPath',
        _getColors(context),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      _showMessage(context, tr('screenshot_failed'), _getColors(context));
    }
  }

  Future<void> _sendScreenFrame() async {
    if (!_canSignal || !_isScreenSharing || _isCapturing) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    
    // OPTIMIZATION: Reduced latency check from 24ms to 8ms
    // Previously: if (nowMs - _lastInputSentAtMs < 24) return;
    // This allows video to send more frequently while still respecting input priority
    if (nowMs - _lastInputSentAtMs < 8) return;
    
    _isCapturing = true;
    final captureStartMs = DateTime.now().millisecondsSinceEpoch;
    
    try {
      final bytes = await _captureLocalScreenToJpegBytes();
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        print('[ScreenShare] Capture returned null/empty');
        final detail = _captureError.isNotEmpty ? _captureError : 'capture null';
        if (mounted && _captureError.isEmpty) {
          setState(() => _captureError = detail);
        }
        _sendCaptureStatus('error', detail);
        return;
      }
      
      const maxFrameBytes = 20 * 1024 * 1024;
      if (bytes.length > maxFrameBytes) {
        print('[ScreenShare] Frame too large: ${bytes.length} bytes');
        if (mounted) setState(() => _captureError = 'too large: ${bytes.length}');
        _sendCaptureStatus('error', 'Frame too large: ${bytes.length} bytes');
        return;
      }
      
      // OPTIMIZATION: Enhanced frame differencing
      // Check if frame is identical to last sent frame
      final hash = _quickFrameHashAdvanced(bytes);
      final captureTimeMs = DateTime.now().millisecondsSinceEpoch - captureStartMs;
      
      if (hash == _lastFrameHash && (nowMs - _lastFrameSentAtMs) < 1000) {
        // Frame hasn't changed - skip sending (saves bandwidth)
        _framesDropped++;
        _captureTimeMs = captureTimeMs;
        return;
      }
      
      // OPTIMIZATION: Adaptive JPEG quality based on frame size and network
      int quality = _captureJpegQuality;
      if (bytes.length > 512 * 1024) {
        quality = (quality * 0.8).toInt().clamp(30, 90);
      }
      
      final b64 = base64Encode(bytes);
      final encodeTimeMs = DateTime.now().millisecondsSinceEpoch - captureStartMs - captureTimeMs;
      final sent = _sendSessionPayload(
        messageType: 'screen_frame',
        payload: {
          'frameData': b64,
          'channel': 'video',
          'sentAt': nowMs,
          'frameHash': hash,
          'frameWidth': _localFrameWidth,
          'frameHeight': _localFrameHeight,
          'virtualWidth': _localFrameWidth > 0 ? _localFrameWidth : _virtualWidth,
          'virtualHeight': _localFrameHeight > 0 ? _localFrameHeight : _virtualHeight,
          'remoteWidth': _localCaptureWidth > 0 ? _localCaptureWidth : _screenWidthActual,
          'remoteHeight': _localCaptureHeight > 0 ? _localCaptureHeight : _screenHeightActual,
          'screenCount': _localScreenCount,
          'screenIndex': _selectedLocalScreenIndex,
          'captureLeft': _localCaptureLeft,
          'captureTop': _localCaptureTop,
          'captureWidth': _localCaptureWidth,
          'captureHeight': _localCaptureHeight,
          // OPTIMIZATION: Add diagnostic metadata
          'captureTimeMs': captureTimeMs,
          'encodeTimeMs': encodeTimeMs,
          'quality': quality,
        },
      );
      if (!sent) {
        if (mounted) setState(() => _captureError = 'session send failed');
        _sendCaptureStatus('error', 'Session send failed');
        return;
      }
      
      _lastFrameHash = hash;
      _lastFrameSentHash = hash;
      _lastFrameSentAtMs = nowMs;
      _lastFrameBytes = bytes;
      _lastFrameCaptureTime = DateTime.now();
      
      if (mounted) setState(() { 
        _framesSent++; 
        _captureError = '';
        _captureTimeMs = captureTimeMs;
        _encodeTimeMs = encodeTimeMs;
      });
      
      _sendCaptureStatus('ok', '');
      _sendResolutionUpdate();
      if (_framesSent % 30 == 0) {
        print('[ScreenShare] Sent frame #$_framesSent (${bytes.length} bytes) ${_localFrameWidth}x$_localFrameHeight quality=$quality');
      }
    } catch (e) {
      if (mounted) setState(() => _captureError = 'capture/send exception: $e');
      _sendCaptureStatus('error', 'Capture/send exception: $e');
    } finally {
      _isCapturing = false;
    }
  }

  int _quickFrameHash(Uint8List bytes) {
    if (bytes.isEmpty) return 0;
    final step = (bytes.length ~/ 32).clamp(1, 4096);
    var h = bytes.length;
    for (var i = 0; i < bytes.length; i += step) {
      h = ((h * 33) ^ bytes[i]) & 0x7fffffff;
    }
    return h;
  }

  // OPTIMIZATION: Advanced frame hashing for better change detection
  /// Uses multi-level hashing to detect frame changes at different granularities
  int _quickFrameHashAdvanced(Uint8List bytes) {
    if (bytes.isEmpty) return 0;
    
    // Sample from multiple regions: start, middle, end, and scattered points
    var hash = bytes.length * 33;
    
    // Start region (first 1%)
    final startLen = (bytes.length ~/ 100).clamp(256, 2048);
    for (var i = 0; i < startLen && i < bytes.length; i += 4) {
      hash = ((hash * 33) ^ bytes[i]) & 0x7fffffff;
    }
    
    // Middle region
    final mid = bytes.length ~/ 2;
    for (var i = mid; i < mid + startLen && i < bytes.length; i += 4) {
      hash = ((hash * 33) ^ bytes[i]) & 0x7fffffff;
    }
    
    // End region
    final endStart = (bytes.length - startLen).clamp(0, bytes.length);
    for (var i = endStart; i < bytes.length; i += 4) {
      hash = ((hash * 33) ^ bytes[i]) & 0x7fffffff;
    }
    
    return hash;
  }

  // OPTIMIZATION: Add diagnostics tracking function
  void _updateDiagnostics() {
    // Track performance metrics for visibility
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastFrameCaptureTime != null) {
      final latency = now - _lastFrameCaptureTime!.millisecondsSinceEpoch;
      _frameAvgLatencyMs = (_frameAvgLatencyMs * 0.9) + (latency * 0.1);
      
      // Histogram for latency distribution
      final bucket = (latency ~/ 50).clamp(0, 19);
      _latencyHistogram[bucket]++;
    }
  }

  // ===== NEW: System Cursor Shape Detection (native WinAPI) =====
  /// Detects the current system cursor shape on host using GetCursorInfo/GetIconInfo.
  /// Returns logical cursor type (pointer, text, hand, resize-x, resize-y, loading).
  void _ensureNativeCursorApi() {
    if (_nativeCursorApiInitFailed) return;
    if (_nativeGetCursorInfo != null && _nativeLoadCursorW != null) return;
    if (!io.Platform.isWindows) {
      _nativeCursorApiInitFailed = true;
      return;
    }
    try {
      _user32Lib ??= DynamicLibrary.open('user32.dll');
      _gdi32Lib ??= DynamicLibrary.open('gdi32.dll');
      _nativeGetCursorInfo ??= _user32Lib!.lookupFunction<
          Int32 Function(Pointer<_CursorInfoNative>),
          int Function(Pointer<_CursorInfoNative>)>('GetCursorInfo');
      _nativeLoadCursorW ??= _user32Lib!.lookupFunction<
          IntPtr Function(IntPtr, Pointer<Utf16>),
          int Function(int, Pointer<Utf16>)>('LoadCursorW');
      _nativeGetIconInfo ??= _user32Lib!.lookupFunction<
          Int32 Function(IntPtr, Pointer<_IconInfoNative>),
          int Function(int, Pointer<_IconInfoNative>)>('GetIconInfo');
      _nativeDeleteObject ??= _gdi32Lib!.lookupFunction<
          Int32 Function(IntPtr),
          int Function(int)>('DeleteObject');
    } catch (e) {
      _nativeCursorApiInitFailed = true;
      debugPrint('[Cursor] Native API init failed: $e');
    }
  }

  Pointer<Utf16> _makeCursorResource(int id) => Pointer<Utf16>.fromAddress(id);

  String _detectSystemCursorShape() {
    if (!io.Platform.isWindows) return 'pointer';
    _ensureNativeCursorApi();
    final getCursorInfo = _nativeGetCursorInfo;
    final loadCursorW = _nativeLoadCursorW;
    if (getCursorInfo == null || loadCursorW == null) return 'pointer';

    final ci = calloc<_CursorInfoNative>();
    try {
      ci.ref.cbSize = sizeOf<_CursorInfoNative>();
      final ok = getCursorInfo(ci);
      if (ok == 0) return 'pointer';
      if ((ci.ref.flags & 0x00000001) == 0) return 'pointer';

      final current = ci.ref.hCursor;
      if (current == 0) return 'pointer';

      final arrow = loadCursorW(0, _makeCursorResource(32512));
      if (current == arrow) return 'pointer';
      final ibeam = loadCursorW(0, _makeCursorResource(32513));
      if (current == ibeam) return 'text';
      final wait = loadCursorW(0, _makeCursorResource(32514));
      if (current == wait) return 'loading';
      final sizewe = loadCursorW(0, _makeCursorResource(32644)); // IDC_SIZEWE
      if (current == sizewe) return 'resize-x';
      final sizens = loadCursorW(0, _makeCursorResource(32645)); // IDC_SIZENS
      if (current == sizens) return 'resize-y';
      final hand = loadCursorW(0, _makeCursorResource(32649));
      if (current == hand) return 'hand';

      // Fallback probe using GetIconInfo to keep shape-sync robust for themed cursors.
      final getIconInfo = _nativeGetIconInfo;
      final deleteObject = _nativeDeleteObject;
      if (getIconInfo != null && deleteObject != null) {
        final icon = calloc<_IconInfoNative>();
        try {
          final iconOk = getIconInfo(current, icon);
          if (iconOk != 0) {
            final hx = icon.ref.xHotspot;
            final hy = icon.ref.yHotspot;
            if (hx <= 2 && hy <= 2) return 'pointer';
            if (hx >= 8 && hx <= 12 && hy >= 8 && hy <= 12) return 'text';
          }
        } finally {
          final mask = icon.ref.hbmMask;
          final color = icon.ref.hbmColor;
          if (mask != 0) deleteObject(mask);
          if (color != 0) deleteObject(color);
          calloc.free(icon);
        }
      }

      return 'pointer';
    } catch (e) {
      debugPrint('[Cursor] Native detection failed: $e');
      return 'pointer';
    } finally {
      calloc.free(ci);
    }
  }
  // ===== END: System Cursor Shape Detection =====

  // ===== NEW: TeamViewer-Style Cursor Channel (Independent of Video) =====
  /// Implements separate high-frequency cursor updates (60-120Hz)
  /// This is the KEY difference from naive implementations - cursor is NOT tied to frame updates!
  void _startCursorUpdateTimer() {
    // Cancel existing timer
    _cursorUpdateTimer?.cancel();
    
    // Start high-frequency cursor update loop
    // 60-120Hz = 8-16ms interval (NOT tied to frame refresh rate)
    final cursorFreqMs = _cursorUpdateFreqMs;  // 250 Hz target
    
    _cursorUpdateTimer = Timer.periodic(Duration(milliseconds: cursorFreqMs), (_) {
      _cursorUpdateLoop();
    });
  }

  /// Main cursor update loop - runs independently of frame capture
  /// This is what makes it feel "real-time" like TeamViewer
  void _cursorUpdateLoop() {
    if (!_canSignal) return;
    if (!widget.sendLocalScreen && !_remoteControlFocusNode.hasFocus) return;

    if (widget.sendLocalScreen) {
      _syncLocalCursorFromSystem();
    }
    
    // Avoid extra UI churn while actively holding mouse button down.
    if (!_mouseButtonDown) {
      _updateCursorPredictionFrame();
    }
    
    // Check if cursor position has changed significantly
    final dx = (_localCursorX - _lastSentCursorX).abs();
    final dy = (_localCursorY - _lastSentCursorY).abs();
    
    // Send update if cursor moved (even slightly) or hasn't been sent recently
    final timeSinceLastSend = _cursorMovementStopwatch.elapsedMilliseconds;
    final significantMovement = dx > 0.001 || dy > 0.001;
    final timeoutElapsed = timeSinceLastSend > 120;  // Keep alive updates
    
    if (significantMovement || timeoutElapsed) {
      _sendCursorUpdate();
    }
  }

  void _syncLocalCursorFromSystem() {
    if (!io.Platform.isWindows) return;
    final capWidth = _localCaptureWidth > 0 ? _localCaptureWidth : _screenWidthActual;
    final capHeight = _localCaptureHeight > 0 ? _localCaptureHeight : _screenHeightActual;
    if (capWidth <= 0 || capHeight <= 0) return;

    final point = calloc<win32.POINT>();
    try {
      final ok = win32.GetCursorPos(point);
      if (ok == 0) return;
      final relX = point.ref.x - _localCaptureLeft;
      final relY = point.ref.y - _localCaptureTop;
      _localCursorX = (relX / capWidth).clamp(0.0, 1.0);
      _localCursorY = (relY / capHeight).clamp(0.0, 1.0);
    } finally {
      calloc.free(point);
    }
  }

  /// Send cursor position update on SEPARATE channel with detected system cursor shape
  /// CRITICAL DIFFERENCE: This is NOT part of the frame transmission!
  /// Also sends cursor type (light: ~30 bytes total, not icon data)
  void _sendCursorUpdate() {
    if (!_canSignal) return;
    
    // Native cursor-shape polling.
    // Keep this moderate to avoid adding jitter during heavy click bursts.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_mouseButtonDown && now - (_lastCursorShapeUpdateMs ?? 0) > 220) {
      _lastCursorShapeUpdateMs = now;
      _cursorShapeType = _detectSystemCursorShape();
    }
    
    // Build cursor payload (very small: 2 floats + type string = ~30-50 bytes)
    final payload = <String, dynamic>{
      'action': 'move',
      'x': _localCursorX.clamp(0.0, 1.0),
      'y': _localCursorY.clamp(0.0, 1.0),
      'channel': 'cursor_input',  // 🔑 SEPARATE CHANNEL (not 'input' or 'video')
      'cursorShape': _cursorShapeType,  // Light: just the type string (pointer, text, hand, etc)
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'seq': ++_inputSequence,
    };
    
    // Send immediately (high priority, tiny packet)
    _sendSessionPayload(messageType: 'cursor_update', payload: payload);
    
    // Update tracking
    _lastSentCursorX = _localCursorX;
    _lastSentCursorY = _localCursorY;
    _cursorMovementStopwatch.reset();
    _cursorMovementStopwatch.start();
  }

  /// Remote cursor rendering - Draw cursor locally WHILE waiting for video
  /// This is the "magic trick" that makes TeamViewer feel instant!
  Rect computeDisplayBounds({
    required Size viewportSize,
    required int sourceWidth,
    required int sourceHeight,
    required bool fillViewport,
  }) {
    final w = viewportSize.width;
    final h = viewportSize.height;
    if (w <= 0 || h <= 0) return Rect.zero;

    final frameW = sourceWidth <= 0 ? w : sourceWidth.toDouble();
    final frameH = sourceHeight <= 0 ? h : sourceHeight.toDouble();
    final frameAspect = frameW / frameH;
    final viewAspect = w / h;

    double drawW;
    double drawH;
    double offsetX = 0;
    double offsetY = 0;

    if (fillViewport) {
      if (frameAspect > viewAspect) {
        drawH = h;
        drawW = h * frameAspect;
        offsetX = (w - drawW) / 2;
      } else {
        drawW = w;
        drawH = w / frameAspect;
        offsetY = (h - drawH) / 2;
      }
    } else {
      if (frameAspect > viewAspect) {
        drawW = w;
        drawH = w / frameAspect;
        offsetY = (h - drawH) / 2;
      } else {
        drawH = h;
        drawW = h * frameAspect;
        offsetX = (w - drawW) / 2;
      }
    }

    return Rect.fromLTWH(offsetX, offsetY, drawW, drawH);
  }

  Offset? normalizeCoordinates({
    required Offset local,
    required Size viewportSize,
    required int sourceWidth,
    required int sourceHeight,
    required bool fillViewport,
  }) {
    final frameRect = computeDisplayBounds(
      viewportSize: viewportSize,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      fillViewport: fillViewport,
    );
    if (frameRect.width <= 0 || frameRect.height <= 0) return null;

    final inX = local.dx - frameRect.left;
    final inY = local.dy - frameRect.top;
    if (!fillViewport &&
        (inX < 0 || inY < 0 || inX > frameRect.width || inY > frameRect.height)) {
      return null;
    }

    final nx = (inX / frameRect.width).clamp(0.0, 1.0);
    final ny = (inY / frameRect.height).clamp(0.0, 1.0);
    return Offset(nx, ny);
  }

  Offset denormalizeCoordinates({
    required double normX,
    required double normY,
    required int targetLeft,
    required int targetTop,
    required int targetWidth,
    required int targetHeight,
  }) {
    final nx = normX.clamp(0.0, 1.0);
    final ny = normY.clamp(0.0, 1.0);
    final safeWidth = targetWidth.clamp(1, 32768);
    final safeHeight = targetHeight.clamp(1, 32768);
    final px = targetLeft + ((safeWidth - 1) * nx).round().clamp(0, safeWidth - 1);
    final py = targetTop + ((safeHeight - 1) * ny).round().clamp(0, safeHeight - 1);
    return Offset(px.toDouble(), py.toDouble());
  }

  Rect _computeRemoteFrameDrawRect(Size viewportSize) {
    return computeDisplayBounds(
      viewportSize: viewportSize,
      sourceWidth: _remoteFrameWidth > 0 ? _remoteFrameWidth : _remoteVirtualWidth,
      sourceHeight: _remoteFrameHeight > 0 ? _remoteFrameHeight : _remoteVirtualHeight,
      fillViewport: _fillRemoteViewport,
    );
  }

  Offset? _normalizeLocalToRemote(Offset local, Size viewportSize) {
    return normalizeCoordinates(
      local: local,
      viewportSize: viewportSize,
      sourceWidth: _remoteFrameWidth > 0 ? _remoteFrameWidth : _remoteVirtualWidth,
      sourceHeight: _remoteFrameHeight > 0 ? _remoteFrameHeight : _remoteVirtualHeight,
      // Rendering is always BoxFit.contain; keep input mapping identical.
      fillViewport: false,
    );
  }

  Offset _cursorHotspotForShape(String shapeType) {
    switch (shapeType) {
      case 'text':
        return const Offset(10, 10);
      case 'hand':
        return const Offset(5, 2);
      case 'resize-x':
      case 'resize-y':
        return const Offset(10, 10);
      case 'loading':
      case 'wait':
        return const Offset(9, 9);
      case 'pointer':
      case 'arrow':
      default:
        // Arrow hotspot is near the top-left tip, not center.
        return const Offset(1, 1);
    }
  }

  MouseCursor _systemCursorForShape(String shapeType) {
    switch (shapeType) {
      case 'text':
        return SystemMouseCursors.text;
      case 'hand':
        return SystemMouseCursors.click;
      case 'resize-x':
        return SystemMouseCursors.resizeLeftRight;
      case 'resize-y':
        return SystemMouseCursors.resizeUpDown;
      case 'loading':
      case 'wait':
        return SystemMouseCursors.progress;
      case 'pointer':
      case 'arrow':
      default:
        return SystemMouseCursors.basic;
    }
  }

  Widget _buildRemoteCursorOverlay(Widget child) {
    return MouseRegion(
      cursor: _systemCursorForShape(_cursorShapeType),
      child: child,
    );
  }

  /// Build cursor shape widget based on remote system's cursor type
  /// Maps detected system cursor types to visual indicators
  Widget _buildCursorShape(String shapeType) {
    // Different cursor types from remote system
    // These shapes are synced via the system cursor detection API
    switch (shapeType) {
      case 'pointer':
      case 'arrow':
        // Standard arrow pointer
        return CustomPaint(
          painter: _ArrowCursorPainter(),
          size: const Size(20, 20),
        );
      case 'text':
        // Text input cursor (I-beam)
        return CustomPaint(
          painter: _TextCursorPainter(),
          size: const Size(20, 20),
        );
      case 'hand':
        // Hand cursor (clickable items)
        return const Icon(Icons.pan_tool, color: Colors.white, size: 18);
      case 'resize-x':
        // Horizontal resize cursor
        return CustomPaint(
          painter: _ResizeXCursorPainter(),
          size: const Size(20, 20),
        );
      case 'resize-y':
        // Vertical resize cursor
        return CustomPaint(
          painter: _ResizeYCursorPainter(),
          size: const Size(20, 20),
        );
      case 'loading':
      case 'wait':
        // Wait/loading cursor (animated would be ideal, but static for now)
        return const Icon(Icons.hourglass_bottom, color: Colors.white, size: 18);
      default:
        // Fallback to arrow
        return CustomPaint(
          painter: _ArrowCursorPainter(),
          size: const Size(20, 20),
        );
    }
  }

  /// Handle remote cursor position update
  void _handleRemoteCursorUpdate(Map<String, dynamic> payload) {
    final x = (payload['x'] is num) ? (payload['x'] as num).toDouble() : 0.5;
    final y = (payload['y'] is num) ? (payload['y'] as num).toDouble() : 0.5;
    final shape = (payload['cursorShape'] ?? 'arrow').toString();
    
    // Calculate velocity for smooth prediction
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    int deltaMs = nowMs - _lastRemoteCursorUpdateMs;
    if (deltaMs == 0) deltaMs = 1;
    
    // Clamp new position
    final newX = x.clamp(0.0, 1.0);
    final newY = y.clamp(0.0, 1.0);
    
    // Calculate velocity (pixels/second)
    final oldX = _remoteCursorDisplayX;
    final oldY = _remoteCursorDisplayY;
    _remoteCursorVelocityX = ((newX - oldX) / (deltaMs / 1000.0)).clamp(-5.0, 5.0);
    _remoteCursorVelocityY = ((newY - oldY) / (deltaMs / 1000.0)).clamp(-5.0, 5.0);
    
    if (mounted) {
      setState(() {
        // Update remote cursor display position with smooth animation
        _remoteCursorDisplayX = newX;
        _remoteCursorDisplayY = newY;
        _remoteCursorPredictX = newX;
        _remoteCursorPredictY = newY;
        _lastRemoteCursorUpdateMs = nowMs;
        _cursorShapeType = shape;
        _showRemoteCursor = false;
      });
      
      // Trigger animation frame updates for smooth motion
      _updateCursorPredictionFrame();
    }
  }
  
  void _updateCursorPredictionFrame() {
    // Called frequently to animate cursor toward predicted position
    // This creates smooth interpolation between updates instead of jumpy movement
    if (!mounted) return;
    
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final deltaMs = (nowMs - _lastRemoteCursorUpdateMs).toDouble();

    if (_showRemoteCursor && deltaMs > 1200) {
      setState(() {
        _showRemoteCursor = false;
      });
      return;
    }
    
    // Apply velocity prediction (extrapolate where cursor should be)
    // This anticipates the cursor movement based on velocity
    if (deltaMs < 50 && (
        (_remoteCursorVelocityX.abs() > 0.01 || _remoteCursorVelocityY.abs() > 0.01)
    )) {
      final predictDeltaSec = deltaMs / 1000.0;
      final predictX = (_remoteCursorDisplayX + _remoteCursorVelocityX * predictDeltaSec).clamp(0.0, 1.0);
      final predictY = (_remoteCursorDisplayY + _remoteCursorVelocityY * predictDeltaSec).clamp(0.0, 1.0);
      
      if (mounted && (
          (predictX - _remoteCursorPredictX).abs() > 0.001 ||
          (predictY - _remoteCursorPredictY).abs() > 0.001
      )) {
        setState(() {
          // Smoothly update predicted position
          _remoteCursorPredictX = _remoteCursorPredictX + (predictX - _remoteCursorPredictX) * 0.3;
          _remoteCursorPredictY = _remoteCursorPredictY + (predictY - _remoteCursorPredictY) * 0.3;
        });
      }
    }
  }
  // ===== END: TeamViewer-Style Cursor Channel =====

  Future<Uint8List?> _captureLocalScreenToJpegBytes() async {
    if (!io.Platform.isWindows) return null;

    if (_forceNativeScreenCapture) {
      return _captureLocalScreenNativeJpegBytes();
    }

    // Use stable paths so antivirus exclusions can target one precise location.
    final stableDir = io.Directory('${io.Platform.environment['LOCALAPPDATA']}\\BIMStreaming\\screenshare');
    if (!stableDir.existsSync()) {
      stableDir.createSync(recursive: true);
    }
    final outputPath = '${stableDir.path}\\frame.jpg';
    final scriptPath = '${stableDir.path}\\capture.ps1';
    final escapedOutput = outputPath.replaceAll("'", "''");

    // Script â”œâŒcrit dans un fichier (.ps1) pour â”œâŒviter tout problâ”œÂ¿me d'encodage en ligne de commande
    final scriptContent = r'''Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeDpi {
  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();
}
"@
[NativeDpi]::SetProcessDPIAware() | Out-Null
$all=[System.Windows.Forms.Screen]::AllScreens
$idx=SCREEN_INDEX
if ($idx -lt 0) { $idx = 0 }
if ($idx -ge $all.Count) { $idx = 0 }
$b=$all[$idx].Bounds
$src=New-Object System.Drawing.Bitmap $b.Width,$b.Height
$g=[System.Drawing.Graphics]::FromImage($src)
$g.CopyFromScreen($b.Left,$b.Top,0,0,$src.Size)
$maxW=MAX_WIDTH
$tw=$src.Width
$th=$src.Height
if ($tw -gt $maxW) {
  $ratio=[double]$maxW/[double]$tw
  $tw=[int]([Math]::Round($tw*$ratio))
  $th=[int]([Math]::Round($th*$ratio))
}
$sc=New-Object System.Drawing.Bitmap $tw,$th
$g2=[System.Drawing.Graphics]::FromImage($sc)
$g2.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g2.DrawImage($src,0,0,$tw,$th)
$encoder=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$params=New-Object System.Drawing.Imaging.EncoderParameters(1)
$params.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, JPEG_QUALITY)
$sc.Save('OUTPUT_PATH',$encoder,$params)
Write-Output "$tw,$th,$($b.Left),$($b.Top),$($b.Width),$($b.Height)"
$params.Dispose()
$g.Dispose();$g2.Dispose();$src.Dispose();$sc.Dispose()
'''
        .replaceAll('OUTPUT_PATH', escapedOutput)
        .replaceAll('MAX_WIDTH', _captureMaxWidth.toString())
        .replaceAll('SCREEN_INDEX', _selectedLocalScreenIndex.toString())
        .replaceAll('JPEG_QUALITY', '${_captureJpegQuality}L');

    await io.File(scriptPath).writeAsString(scriptContent);

    try {
      final result = await _runPowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath],
        timeout: const Duration(seconds: 12),
      );
      if (result.exitCode != 0) {
        var err = '${result.stderr}'.trim();
        if (err.isEmpty) {
          err = '${result.stdout}'.trim();
        }
        if (err.isEmpty && result.exitCode == 124) {
          err = 'capture timed out after 12s';
        }
        final lower = err.toLowerCase();
        final blockedBySecurity =
            lower.contains('scriptcontainedmaliciouscontent') ||
            lower.contains('malicious content') ||
            lower.contains('antivirus');
        if (blockedBySecurity) {
          _forceNativeScreenCapture = true;
          if (mounted) {
            setState(() => _captureError = 'PowerShell capture blocked by security policy; using native capture fallback.');
          }
          return _captureLocalScreenNativeJpegBytes();
        }
        print('[ScreenShare] PS1 failed (exit=${result.exitCode}): $err');
        if (mounted) setState(() => _captureError = 'PS1 exit=${result.exitCode}: ${err.substring(0, err.length.clamp(0, 120))}');
        return await _captureLocalScreenFallbackPngBytes(stableDir);
      }
      final file = io.File(outputPath);
      if (!file.existsSync()) {
        print('[ScreenShare] Output JPEG not found: $outputPath');
        if (mounted) setState(() => _captureError = 'file not found');
        return await _captureLocalScreenFallbackPngBytes(stableDir);
      }
      final out = '${result.stdout}'.trim();
      final line = out.split(RegExp(r'[\r\n]+')).firstWhere(
        (l) => l.contains(','),
        orElse: () => '',
      );
      if (line.isNotEmpty) {
        final parts = line.split(',');
        if (parts.length >= 2) {
          final w = int.tryParse(parts[0].trim()) ?? 0;
          final h = int.tryParse(parts[1].trim()) ?? 0;
          if (w > 0 && h > 0) {
            _localFrameWidth = w;
            _localFrameHeight = h;
          }
        }
        if (parts.length >= 6) {
          _localCaptureLeft = int.tryParse(parts[2].trim()) ?? _localCaptureLeft;
          _localCaptureTop = int.tryParse(parts[3].trim()) ?? _localCaptureTop;
          _localCaptureWidth = int.tryParse(parts[4].trim()) ?? _localCaptureWidth;
          _localCaptureHeight = int.tryParse(parts[5].trim()) ?? _localCaptureHeight;
        }
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) setState(() => _captureError = 'capture produced empty JPEG');
        return await _captureLocalScreenFallbackPngBytes(stableDir);
      }
      return bytes;
    } catch (e) {
      print('[ScreenShare] Exception: $e');
      if (mounted) setState(() => _captureError = e.toString());
      return await _captureLocalScreenFallbackPngBytes(stableDir);
    } finally {
      try { io.File(outputPath).deleteSync(); } catch (_) {}
    }
  }

  Uint8List? _captureLocalScreenNativeJpegBytes() {
    if (!io.Platform.isWindows) return null;

    int capLeft = 0;
    int capTop = 0;
    int capWidth = win32.GetSystemMetrics(win32.SM_CXSCREEN);
    int capHeight = win32.GetSystemMetrics(win32.SM_CYSCREEN);

    if (_selectedLocalScreenIndex > 0) {
      capLeft = win32.GetSystemMetrics(win32.SM_XVIRTUALSCREEN);
      capTop = win32.GetSystemMetrics(win32.SM_YVIRTUALSCREEN);
      capWidth = win32.GetSystemMetrics(win32.SM_CXVIRTUALSCREEN);
      capHeight = win32.GetSystemMetrics(win32.SM_CYVIRTUALSCREEN);
    }

    if (capWidth <= 0 || capHeight <= 0) {
      if (mounted) setState(() => _captureError = 'Native capture invalid screen bounds');
      return null;
    }

    final hScreenDc = win32.GetDC(0);
    if (hScreenDc == 0) {
      if (mounted) setState(() => _captureError = 'Native capture GetDC failed');
      return null;
    }

    final hMemoryDc = win32.CreateCompatibleDC(hScreenDc);
    if (hMemoryDc == 0) {
      win32.ReleaseDC(0, hScreenDc);
      if (mounted) setState(() => _captureError = 'Native capture CreateCompatibleDC failed');
      return null;
    }

    final hBitmap = win32.CreateCompatibleBitmap(hScreenDc, capWidth, capHeight);
    if (hBitmap == 0) {
      win32.DeleteDC(hMemoryDc);
      win32.ReleaseDC(0, hScreenDc);
      if (mounted) setState(() => _captureError = 'Native capture CreateCompatibleBitmap failed');
      return null;
    }

    final oldObject = win32.SelectObject(hMemoryDc, hBitmap);
    final copied = win32.BitBlt(
      hMemoryDc,
      0,
      0,
      capWidth,
      capHeight,
      hScreenDc,
      capLeft,
      capTop,
      win32.SRCCOPY | win32.CAPTUREBLT,
    );

    if (copied == 0) {
      win32.SelectObject(hMemoryDc, oldObject);
      win32.DeleteObject(hBitmap);
      win32.DeleteDC(hMemoryDc);
      win32.ReleaseDC(0, hScreenDc);
      if (mounted) setState(() => _captureError = 'Native capture BitBlt failed');
      return null;
    }

    final bmi = calloc<win32.BITMAPINFO>();
    final byteCount = capWidth * capHeight * 4;
    final pixelBuffer = calloc<Uint8>(byteCount);

    try {
      bmi.ref.bmiHeader.biSize = sizeOf<win32.BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = capWidth;
      bmi.ref.bmiHeader.biHeight = -capHeight;
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = win32.BI_RGB;

      final rows = win32.GetDIBits(
        hMemoryDc,
        hBitmap,
        0,
        capHeight,
        pixelBuffer.cast(),
        bmi,
        win32.DIB_RGB_COLORS,
      );

      if (rows == 0) {
        if (mounted) setState(() => _captureError = 'Native capture GetDIBits failed');
        return null;
      }

      final raw = pixelBuffer.asTypedList(byteCount);
      final source = img.Image.fromBytes(
        width: capWidth,
        height: capHeight,
        bytes: raw.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );

      img.Image output = source;
      if (capWidth > _captureMaxWidth) {
        final scale = _captureMaxWidth / capWidth;
        final targetW = _captureMaxWidth;
        final targetH = (capHeight * scale).round().clamp(1, 4320);
        output = img.copyResize(
          source,
          width: targetW,
          height: targetH,
          interpolation: img.Interpolation.cubic,
        );
      }

      _localFrameWidth = output.width;
      _localFrameHeight = output.height;
      _localCaptureLeft = capLeft;
      _localCaptureTop = capTop;
      _localCaptureWidth = capWidth;
      _localCaptureHeight = capHeight;

      final jpg = img.encodeJpg(output, quality: _captureJpegQuality);
      if (mounted) setState(() => _captureError = '');
      return Uint8List.fromList(jpg);
    } catch (e) {
      if (mounted) setState(() => _captureError = 'Native capture exception: $e');
      return null;
    } finally {
      calloc.free(pixelBuffer);
      calloc.free(bmi);
      win32.SelectObject(hMemoryDc, oldObject);
      win32.DeleteObject(hBitmap);
      win32.DeleteDC(hMemoryDc);
      win32.ReleaseDC(0, hScreenDc);
    }
  }

  Future<Uint8List?> _captureLocalScreenFallbackPngBytes(io.Directory stableDir) async {
    final outputPath = '${stableDir.path}\\frame_fallback.png';
    final script = r'''
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$all=[System.Windows.Forms.Screen]::AllScreens
$idx=SCREEN_INDEX
if ($idx -lt 0) { $idx = 0 }
if ($idx -ge $all.Count) { $idx = 0 }
$b=$all[$idx].Bounds
$bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left,$b.Top,0,0,$bmp.Size)
$bmp.Save('OUTPUT_PATH',[System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "$($bmp.Width),$($bmp.Height),$($b.Left),$($b.Top),$($b.Width),$($b.Height)"
$g.Dispose();$bmp.Dispose()
'''
        .replaceAll('OUTPUT_PATH', outputPath.replaceAll("'", "''"))
        .replaceAll('SCREEN_INDEX', _selectedLocalScreenIndex.toString());

    try {
      final result = await _runPowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        timeout: const Duration(seconds: 10),
      );
      if (result.exitCode != 0) {
        var err = '${result.stderr}'.trim();
        if (err.isEmpty) err = '${result.stdout}'.trim();
        if (mounted && err.isNotEmpty) {
          setState(() => _captureError = 'Fallback capture failed: ${err.substring(0, err.length.clamp(0, 120))}');
        }
        return null;
      }
      final file = io.File(outputPath);
      if (!file.existsSync()) {
        if (mounted) setState(() => _captureError = 'Fallback capture file not found');
        return null;
      }
      final out = '${result.stdout}'.trim();
      final line = out.split(RegExp(r'[\r\n]+')).firstWhere((l) => l.contains(','), orElse: () => '');
      if (line.isNotEmpty) {
        final parts = line.split(',');
        if (parts.length >= 2) {
          final w = int.tryParse(parts[0].trim()) ?? 0;
          final h = int.tryParse(parts[1].trim()) ?? 0;
          if (w > 0 && h > 0) {
            _localFrameWidth = w;
            _localFrameHeight = h;
          }
        }
        if (parts.length >= 6) {
          _localCaptureLeft = int.tryParse(parts[2].trim()) ?? _localCaptureLeft;
          _localCaptureTop = int.tryParse(parts[3].trim()) ?? _localCaptureTop;
          _localCaptureWidth = int.tryParse(parts[4].trim()) ?? _localCaptureWidth;
          _localCaptureHeight = int.tryParse(parts[5].trim()) ?? _localCaptureHeight;
        }
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) setState(() => _captureError = 'Fallback capture produced empty PNG');
        return null;
      }
      if (mounted) setState(() => _captureError = '');
      return bytes;
    } catch (e) {
      if (mounted) setState(() => _captureError = 'Fallback capture exception: $e');
      return null;
    } finally {
      try { io.File(outputPath).deleteSync(); } catch (_) {}
    }
  }

  Future<void> _toggleRecording() async {
    if (!_isConnected) return;
    final next = !_isRecording;
    setState(() => _isRecording = next);
    if (next) {
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!_isRecording || _remoteScreenFrame == null || _remoteScreenFrame!.isEmpty) return;
        try {
          final dir = io.Directory(_recordingsPath);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          final path = '${dir.path}\\frame_${_timestampForFile()}_${_recordedFrames.length + 1}.jpg';
          await io.File(path).writeAsBytes(_remoteScreenFrame!, flush: true);
          if (!mounted) return;
          setState(() {
            _recordedFrames.add({'path': path, 'time': DateTime.now().toIso8601String()});
          });
        } catch (_) {
          // Ignore intermittent write failures.
        }
      });
    } else {
      _recordingTimer?.cancel();
      final videoPath = await _exportRecordingToVideoIfPossible();
      if (!mounted) return;
      if (videoPath != null) {
        _showMessage(
          context,
          'Recording saved: $videoPath',
          _getColors(context),
        );
        return;
      }
    }
    _showMessage(
      context,
      next
          ? 'Recording started (saved to $_recordingsPath)'
          : 'Recording stopped. ${_recordedFrames.length} frames saved.',
      _getColors(context),
    );
  }

  void _toggleAudio() {
    if (!_isConnected) return;
    setState(() => _audioEnabled = !_audioEnabled);
    _sendSessionPayload(
      messageType: 'audio_toggle',
      payload: {'enabled': _audioEnabled},
    );
    unawaited(_syncRemoteAudioPipeline());
    _showMessage(context, _audioEnabled ? tr('audio_enabled') : tr('audio_disabled'), _getColors(context));
  }

  void _lockDevice() {
    if (!_isConnected || _isRebooting) return;
    setState(() => _isDeviceLocked = !_isDeviceLocked);
    _sendSessionPayload(
      messageType: 'lock_mode',
      payload: {'enabled': _isDeviceLocked},
    );
    _showMessage(
      context,
      _isDeviceLocked ? tr('device_locked') : 'Device unlocked',
      _getColors(context),
    );
  }

  void _rebootDevice() {
    if (!_isConnected || _isRebooting) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('confirm_reboot')),
        content: Text(tr('reboot_warning')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('btn_cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _isRebooting = true;
                _isConnected = false;
                _connectionStatus = 'Rebooting remote machine...';
              });
              _sendSystemAction('reboot');
              _showMessage(context, tr('device_rebooting'), _getColors(context));
              _startReconnectLoop();
            },
            child: Text(tr('btn_reboot')),
          ),
        ],
      ),
    );
  }

  void _toggleBlackout() {
    if (!_isConnected) return;
    setState(() => _isBlackoutMode = !_isBlackoutMode);
    _sendSessionPayload(
      messageType: 'privacy_mode',
      payload: {'enabled': _isBlackoutMode},
    );
    
    // Also send system action to machine B to hide/show display
    if (_isBlackoutMode) {
      // Hide display - black out the system screen
      _applySystemAction({'action': 'privacy_mode_on'});
    } else {
      // Show display - restore the system screen
      _applySystemAction({'action': 'privacy_mode_off'});
    }
    
    _showMessage(context, _isBlackoutMode ? tr('privacy_mode_enabled') : tr('privacy_mode_disabled'), _getColors(context));
  }

  void _sendSystemAction(String action) {
    _sendSessionPayload(
      messageType: 'system_action',
      payload: {'action': action},
    );
    _showMessage(context, 'Requested: $action', _getColors(context));
  }

  Future<void> _applySystemAction(Map<String, dynamic> payload) async {
    if (!io.Platform.isWindows) return;
    final action = (payload['action'] ?? '').toString();
    if (action.isEmpty) return;
    try {
      switch (action) {
        case 'task_manager':
          await io.Process.start('taskmgr', []);
          break;
        case 'file_explorer':
          await io.Process.start('explorer', []);
          break;
        case 'terminal':
          await io.Process.start('cmd', ['/c', 'start', 'cmd']);
          break;
        case 'control_panel':
          await io.Process.start('cmd', ['/c', 'start', 'control']);
          await io.Process.start('cmd', ['/c', 'start', 'ms-settings:']);
          break;
        case 'run_dialog':
          await io.Process.start('rundll32.exe', ['shell32.dll,#61']);
          break;
        case 'lock_screen':
          await io.Process.run('rundll32.exe', ['user32.dll,LockWorkStation']);
          break;
        case 'logout':
          await io.Process.start('shutdown', ['/l']);
          break;
        case 'reboot':
          await io.Process.start('shutdown', ['/r', '/t', '3']);
          break;
        case 'privacy_mode_on':
          // Turn off display - black out the system screen on machine B
          await io.Process.run('powershell', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            r'''
[DllImport("user32.dll")]
public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
$null = Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);' -Name NativeMethods -PassThru
[NativeMethods]::PostMessage([IntPtr](-1), 0x0112, [IntPtr](0xF170), [IntPtr](2))
''',
          ]);
          break;
        case 'privacy_mode_off':
          // Turn on display - restore the system screen on machine B
          await io.Process.run('powershell', [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            r'''Move-Mouse'''
          ]);
          break;
      }
    } catch (_) {
      // Keep session alive even if local policy blocks command execution.
    }
  }

  Future<String?> _exportRecordingToVideoIfPossible() async {
    if (_recordedFrames.length < 2) {
      return null;
    }

    try {
      final recordingsDir = io.Directory(_recordingsPath);
      if (!recordingsDir.existsSync()) {
        recordingsDir.createSync(recursive: true);
      }
      final listPath = '${recordingsDir.path}\\frames_${_timestampForFile()}.txt';
      final outPath = '${recordingsDir.path}\\session_${_timestampForFile()}.mp4';

      final buffer = StringBuffer();
      for (final frame in _recordedFrames) {
        final p = (frame['path'] ?? '').replaceAll('\\', '/').replaceAll("'", "''");
        if (p.isEmpty) continue;
        buffer.writeln("file '$p'");
        buffer.writeln('duration ${1 / _recordingFps}');
      }

      try {
        await io.File(listPath).writeAsString(buffer.toString());
        final result = await io.Process.run(
          'ffmpeg',
          [
            '-y',
            '-f',
            'concat',
            '-safe',
            '0',
            '-i',
            listPath,
            '-vf',
            'fps=$_recordingFps',
            '-pix_fmt',
            'yuv420p',
            outPath,
          ],
        );

        if (result.exitCode == 0 && io.File(outPath).existsSync()) {
          return outPath;
        }
      } catch (_) {
        // ffmpeg might not be installed.
      } finally {
        try {
          io.File(listPath).deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      // Ignore errors
    }
    return null;
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap, Map<String, Color> colors, {bool isActive = false, bool isDanger = false, bool enabled = true}) {
    final bgColor = !enabled
        ? colors['cardBg']!
        : (isDanger ? Colors.red[600] : (isActive ? colors['accent']! : colors['cardBg']!));
    final borderColor = !enabled
        ? colors['border']!
        : (isDanger ? Colors.red[700]! : colors['border']!);
    final fgColor = !enabled
        ? colors['textSecondary']!
        : (isDanger ? Colors.white : (isActive ? Colors.white : colors['text']!));

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fgColor, size: 16),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: fgColor, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, Color> _getColors(BuildContext context) {
    final isDark = widget.isDarkMode;
    return {
      'bg': isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
      'cardBg': isDark ? const Color(0xFF2A2A2A) : Colors.white,
      'text': isDark ? Colors.white : Colors.black,
      'textSecondary': isDark ? const Color(0xFF999999) : const Color(0xFF666666),
      'accent': isDark ? const Color(0xFF4A90E2) : const Color(0xFF2E5BF8),
      'border': isDark ? const Color(0xFF404040) : const Color(0xFFE0E0E0),
    };
  }
}
// ===== Cursor Shape Painters =====
/// Renders standard arrow cursor (pointer)
class _ArrowCursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.fill;
    
    // Arrow pointing up-left
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(0, 16);
    path.lineTo(6, 10);
    path.lineTo(12, 18);
    path.lineTo(14, 17);
    path.lineTo(8, 8);
    path.lineTo(16, 8);
    path.close();
    
    canvas.drawPath(path, fillPaint);
  }
  
  @override
  bool shouldRepaint(_ArrowCursorPainter oldDelegate) => false;
}

/// Renders text cursor (I-beam)
class _TextCursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final center = size.width / 2;
    
    // Top horizontal bar
    canvas.drawLine(Offset(center - 4, 2), Offset(center + 4, 2), paint);
    
    // Center vertical line
    canvas.drawLine(Offset(center, 4), Offset(center, 16), paint);
    
    // Bottom horizontal bar
    canvas.drawLine(Offset(center - 4, 18), Offset(center + 4, 18), paint);
  }
  
  @override
  bool shouldRepaint(_TextCursorPainter oldDelegate) => false;
}

/// Renders horizontal resize cursor
class _ResizeXCursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final center = size.height / 2;
    
    // Left arrow
    canvas.drawLine(Offset(2, center), Offset(8, center), paint);
    canvas.drawLine(Offset(2, center), Offset(6, center - 3), paint);
    canvas.drawLine(Offset(2, center), Offset(6, center + 3), paint);
    
    // Right arrow
    canvas.drawLine(Offset(12, center), Offset(18, center), paint);
    canvas.drawLine(Offset(18, center), Offset(14, center - 3), paint);
    canvas.drawLine(Offset(18, center), Offset(14, center + 3), paint);
  }
  
  @override
  bool shouldRepaint(_ResizeXCursorPainter oldDelegate) => false;
}

/// Renders vertical resize cursor
class _ResizeYCursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final center = size.width / 2;
    
    // Top arrow
    canvas.drawLine(Offset(center, 2), Offset(center, 8), paint);
    canvas.drawLine(Offset(center, 2), Offset(center - 3, 6), paint);
    canvas.drawLine(Offset(center, 2), Offset(center + 3, 6), paint);
    
    // Bottom arrow
    canvas.drawLine(Offset(center, 12), Offset(center, 18), paint);
    canvas.drawLine(Offset(center, 18), Offset(center - 3, 14), paint);
    canvas.drawLine(Offset(center, 18), Offset(center + 3, 14), paint);
  }
  
  @override
  bool shouldRepaint(_ResizeYCursorPainter oldDelegate) => false;
}
// ===== END: Cursor Shape Painters =====