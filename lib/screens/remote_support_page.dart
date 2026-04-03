import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import '../services/signaling_client_service.dart';
import '../services/remote_audio_service.dart';

class RemoteSupportPage extends StatefulWidget {
  final String deviceName;
  final String deviceId;
  final bool sendLocalScreen;
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
  static const int _defaultCaptureIntervalMs = 150;

  bool _isConnected = true;
  String _connectionStatus = 'Connected';
  bool _isEncrypted = true;
  String _sessionTime = '00:00:00';
  String _encryptionType = 'AES-256 Encrypted';
  bool _isFullScreen = false;
  bool _isRecording = false;
  bool _audioEnabled = true;
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
  bool _isClosingSession = false;
  int _remoteFrameWidth = 16;
  int _remoteFrameHeight = 9;
  int _localFrameWidth = 0;
  int _localFrameHeight = 0;
  int _localCaptureLeft = 0;
  int _localCaptureTop = 0;
  int _localCaptureWidth = 0;
  int _localCaptureHeight = 0;
  bool _fillRemoteViewport = false;
  int _lastAppliedMoveMs = 0;
  int _lastCaptureStatusSentMs = 0;
  double? _lastSentMoveX;
  double? _lastSentMoveY;
  Offset? _pendingMove;
  Timer? _pendingMoveTimer;
  double _wheelAccumulator = 0.0;
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
  int _captureMaxWidth = _defaultCaptureMaxWidth;
  int _captureJpegQuality = _defaultJpegQuality;
  String _captureResolutionLabel = 'Full Screen';
  String _qualityLabel = 'Medium';
  String _autoQualityMode = 'Manual';
  int _captureFrameIntervalMs = _defaultCaptureIntervalMs;
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
    _syncFullScreenState();
    _startSessionTimer();
    _connectSessionSignalIfAvailable();
    _startAutomaticScreenShareIfPossible();
    _startDiagnosticsTimer();
    _startKeyboardLayoutSync();
    _startKeyStateSync();
    _revealOverlayTemporarily();
    _refreshLocalScreenInfo();
    _autoEnterFullscreenForController();
    _pinRemoteAgentWindowIfNeeded();
    unawaited(_initAudioUdpSocket());
    unawaited(_syncRemoteAudioPipeline());
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
      if (!isFs) {
        await windowManager.setFullScreen(true);
      }
      if (!mounted) return;
      setState(() => _isFullScreen = true);
      _revealOverlayTemporarily();
    });
  }

  Future<void> _pinRemoteAgentWindowIfNeeded() async {
    if (!widget.sendLocalScreen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setFullScreen(true);
      if (!mounted) return;
      setState(() => _isFullScreen = true);
    });
  }

  Future<void> _refreshLocalScreenInfo() async {
    if (!io.Platform.isWindows) return;
    final script = r'''
Add-Type -AssemblyName System.Windows.Forms
$count = [System.Windows.Forms.Screen]::AllScreens.Count
Write-Output $count
''';
    try {
      final result = await _runPowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        timeout: const Duration(seconds: 4),
      );
      if (result.exitCode != 0) return;
      final count = int.tryParse('${result.stdout}'.trim()) ?? 1;
      if (!mounted) return;
      setState(() {
        _localScreenCount = count < 1 ? 1 : count;
        if (_selectedLocalScreenIndex >= _localScreenCount) {
          _selectedLocalScreenIndex = 0;
        }
      });
    } catch (_) {
      // Keep defaults when screen enumeration fails.
    }
  }

  bool get _canSignal =>
      widget.signalingService != null &&
      (widget.currentUserId ?? '').isNotEmpty;

  void _connectSessionSignalIfAvailable() {
    if (!_canSignal) return;
    _signalSubscription = widget.signalingService!.events.listen(_handleSignalEvent);
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
      final q = _pingMs <= 50
          ? 'Excellent'
          : (_pingMs <= 100 ? 'Good' : (_pingMs <= 180 ? 'Fair' : 'Poor'));
      setState(() {
        _bandwidthText = '$kbps kb/s';
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
          _captureMaxWidth = _defaultCaptureMaxWidth;
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
          _captureFrameIntervalMs = 75;
          _autoQualityMode = 'Manual';
          break;
        case 'Medium':
          _captureJpegQuality = _defaultJpegQuality;
          _captureFrameIntervalMs = 55;
          _autoQualityMode = 'Manual';
          break;
        case 'High':
          _captureJpegQuality = 92;
          _captureFrameIntervalMs = 38;
          _captureMaxWidth = _defaultCaptureMaxWidth;
          _autoQualityMode = 'Manual';
          break;
        case 'Ultra':
          _captureJpegQuality = 96;
          _captureFrameIntervalMs = 28;
          _captureMaxWidth = 3200;
          _autoQualityMode = 'Manual';
          break;
        default:
          _captureJpegQuality = _defaultJpegQuality;
          _captureFrameIntervalMs = _defaultCaptureIntervalMs;
          _autoQualityMode = 'Manual';
      }
    });
    _restartScreenShareTimerIfNeeded();
    _sendDisplayConfig();
  }

  void _applyAutoQuality() {
    if (_autoQualityMode != 'Auto') return;
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
        ? 100
        : (_pingMs <= 80
            ? 150
            : (_pingMs <= 140
                ? 200
                : 250));
    setState(() {
      _captureJpegQuality = newQuality;
      _captureFrameIntervalMs = newIntervalMs;
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

  void _sendInputPolicy() {
    _sendSessionPayload(
      messageType: 'input_policy',
      payload: {
        'keyboardEnabled': _keyboardInputEnabledForUser2,
        'mouseEnabled': _mouseInputEnabledForUser2,
      },
    );
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

    if (messageType == 'screen_frame' && _audioEnabled && !_remoteAudioActive) {
      unawaited(_syncRemoteAudioPipeline());
    }

    if (messageType == 'input_event') {
      if (widget.sendLocalScreen) {
        _enqueueRemoteInput(() => _applyRemoteInput(payload));
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
      setState(() {
        _keyboardInputEnabledForUser2 = keyboard;
        _mouseInputEnabledForUser2 = mouse;
      });
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
          if (quality == 'Low') _captureFrameIntervalMs = 75;
          if (quality == 'Medium') _captureFrameIntervalMs = 55;
          if (quality == 'High') _captureFrameIntervalMs = 38;
          if (quality == 'Ultra') _captureFrameIntervalMs = 28;
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

    setState(() {
      switch (messageType) {
        case 'chat':
          final text = (payload['text'] ?? '').toString();
          if (text.isNotEmpty) {
            print('[Chat] Added from peer: $text');
            _isConnected = true;
            _connectionStatus = 'Connected';
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
            if (_reconnectTimer != null) {
              _stopReconnectLoop();
            }
            _pendingRemoteFrameData = frameData;
            final fw = payload['frameWidth'];
            final fh = payload['frameHeight'];
            final sc = payload['screenCount'];
            final si = payload['screenIndex'];
            if (fw is num && fh is num && fw > 0 && fh > 0) {
              _pendingRemoteFrameWidth = fw.toInt();
              _pendingRemoteFrameHeight = fh.toInt();
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
  }

  Future<void> _closeSession({bool notifyPeer = true}) async {
    if (_isClosingSession) return;
    _isClosingSession = true;

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

  void _enqueueRemoteInput(Future<void> Function() task) {
    _remoteInputQueue = _remoteInputQueue.then((_) => task()).catchError((_) {
      // Keep later input events flowing if one injection fails.
    });
  }

  void _sendWheelFromDelta(double deltaY) {
    if (!_canSendRemoteInput) return;
    _wheelAccumulator += deltaY;
    const threshold = 20.0;
    while (_wheelAccumulator.abs() >= threshold) {
      final direction = _wheelAccumulator > 0 ? 1 : -1;
      // Flutter dy > 0 means scroll down, while Win32 wheel < 0 is down.
      final wheel = direction > 0 ? -120 : 120;
      _sendInputEvent('wheel', wheelDelta: wheel);
      _wheelAccumulator -= threshold * direction;
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
    final payload = <String, dynamic>{'action': action};
    if (normalizedX != null) payload['x'] = normalizedX.clamp(0.0, 1.0);
    if (normalizedY != null) payload['y'] = normalizedY.clamp(0.0, 1.0);
    if (wheelDelta != null) payload['wheelDelta'] = wheelDelta;
    if (key != null && key.isNotEmpty) payload['key'] = key;
    if (extra != null && extra.isNotEmpty) payload.addAll(extra);
    _sendSessionPayload(messageType: 'input_event', payload: payload);
  }

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
      // Ignore compatibility duplicate on updated receivers.
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
    if (action == 'move') {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastAppliedMoveMs < 12) return;
      _lastAppliedMoveMs = now;
    }

    final x = (payload['x'] is num) ? (payload['x'] as num).toDouble() : null;
    final y = (payload['y'] is num) ? (payload['y'] as num).toDouble() : null;
    final wheelDelta = (payload['wheelDelta'] is num)
        ? (payload['wheelDelta'] as num).toInt()
        : 0;
    final key = (payload['key'] ?? '').toString();

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

  Future<void> _applyRemoteKeyboardEvent(Map<String, dynamic> payload) async {
    final phase = (payload['phase'] ?? 'down').toString();
    if (phase != 'down' && phase != 'up') return;
    final isModifier = _isModifierKey(payload);
    if (phase == 'up' && !isModifier) {
      // Non-modifier keys are injected as a full tap on key-down.
      return;
    }
    final vkCode = _resolveVirtualKey(payload);
    final keyStroke = _buildSendKeysStroke(payload);
    final character = _mapCharacterForLayout((payload['character'] ?? '').toString(), payload);
    final isNumpad = payload['isNumpad'] == true;
    final useCtrl = payload['ctrl'] == true;
    final useAlt = payload['alt'] == true;
    final useMeta = payload['meta'] == true;
    final useAltGraph = payload['altGraph'] == true;
    final shouldSendUnicode =
        phase == 'down' &&
        !isModifier &&
        !isNumpad &&
        _isPrintableCharacter(character) &&
        !(useCtrl || useMeta) &&
        (useAltGraph || !useAlt);
    final unicode = shouldSendUnicode ? character.runes.first : 0;

    final script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeInput {
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT {
    public uint type;
    public InputUnion U;
  }

  [StructLayout(LayoutKind.Explicit)]
  public struct InputUnion {
    [FieldOffset(0)]
    public KEYBDINPUT ki;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct KEYBDINPUT {
    public ushort wVk;
    public ushort wScan;
    public uint dwFlags;
    public uint time;
    public UIntPtr dwExtraInfo;
  }

  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint MapVirtualKey(uint uCode, uint uMapType);
}
"@

$phase = '__PHASE__'
$vk = __VK__
$unicode = __UNICODE__
$sendUnicode = __SEND_UNICODE__
$stroke = '__STROKE__'

function Send-Key([int]$k, [bool]$up) {
  $input = New-Object NativeInput+INPUT
  $input.type = 1
  $kb = New-Object NativeInput+KEYBDINPUT
  $kb.wVk = [UInt16]$k
  $kb.wScan = [UInt16][NativeInput]::MapVirtualKey([UInt32]$k, 0)
  $flags = 0x0008
  if ($up) { $flags = $flags -bor 0x0002 }
  if ($k -in 0x25,0x26,0x27,0x28,0x21,0x22,0x23,0x24,0x2D,0x2E,0xA2,0xA3,0xA4,0xA5,0x90,0x91,0x6F,0x6A,0x6B,0x6D,0x6E) { $flags = $flags -bor 0x0001 }
  $kb.dwFlags = $flags
  $kb.time = 0
  $kb.dwExtraInfo = [UIntPtr]::Zero
  $input.U.ki = $kb
  [void][NativeInput]::SendInput(1, @($input), [Runtime.InteropServices.Marshal]::SizeOf([type][NativeInput+INPUT]))
}

function Tap-Key([int]$k) {
  Send-Key $k $false
  Send-Key $k $true
}

function Send-Unicode([int]$codePoint) {
  $down = New-Object NativeInput+INPUT
  $down.type = 1
  $kbDown = New-Object NativeInput+KEYBDINPUT
  $kbDown.wVk = 0
  $kbDown.wScan = [UInt16]$codePoint
  $kbDown.dwFlags = 0x0004
  $kbDown.time = 0
  $kbDown.dwExtraInfo = [UIntPtr]::Zero
  $down.U.ki = $kbDown

  $up = New-Object NativeInput+INPUT
  $up.type = 1
  $kbUp = New-Object NativeInput+KEYBDINPUT
  $kbUp.wVk = 0
  $kbUp.wScan = [UInt16]$codePoint
  $kbUp.dwFlags = 0x0004 -bor 0x0002
  $kbUp.time = 0
  $kbUp.dwExtraInfo = [UIntPtr]::Zero
  $up.U.ki = $kbUp

  [void][NativeInput]::SendInput(2, @($down, $up), [Runtime.InteropServices.Marshal]::SizeOf([type][NativeInput+INPUT]))
}

if ($sendUnicode -eq 1 -and $phase -eq 'down' -and $unicode -gt 0) {
  Send-Unicode $unicode
  return
}

if ($vk -gt 0) {
  if ($phase -eq 'down') {
    $modifiers = @(0x10, 0xA0, 0xA1, 0x11, 0xA2, 0xA3, 0x12, 0xA4, 0xA5, 0x5B, 0x5C)
    if ($modifiers -contains $vk) {
      Send-Key $vk $false
    } else {
      Tap-Key $vk
    }
  } elseif ($phase -eq 'up') {
    Send-Key $vk $true
  }
  return
}

if ($phase -eq 'down' -and -not [string]::IsNullOrWhiteSpace($stroke)) {
  [System.Windows.Forms.SendKeys]::SendWait($stroke)
}
'''
        .replaceAll('__PHASE__', phase)
        .replaceAll('__VK__', vkCode.toString())
        .replaceAll('__UNICODE__', unicode.toString())
        .replaceAll('__SEND_UNICODE__', shouldSendUnicode ? '1' : '0')
        .replaceAll('__STROKE__', keyStroke.replaceAll("'", "''"));

    try {
      await _runPowerShell(
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
        timeout: const Duration(seconds: 2),
      );
    } catch (_) {
      // Keep session alive on key injection failures.
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
    // Keep literal characters as the source of truth for text fidelity across layouts.
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
    return widget.signalingService!.sendSessionMessage(
      sessionId: (widget.sessionId ?? '').toString(),
      toUserId: widget.deviceId,
      messageType: messageType,
      payload: payload,
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

  void _sendMoveIfNeeded(Offset p) {
    _pendingMove = p;
    if (_pendingMoveTimer?.isActive == true) return;

    _pendingMoveTimer = Timer(const Duration(milliseconds: 16), () {
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
    _lastSentMoveX = pending.dx;
    _lastSentMoveY = pending.dy;
    _sendInputEvent('move', normalizedX: pending.dx, normalizedY: pending.dy);
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
    if (isFullScreen) {
      _revealOverlayTemporarily();
    }
  }

  Future<void> _toggleFullScreen() async {
    final nextValue = !_isFullScreen;
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
    _keyboardLayoutTimer?.cancel();
    _keyStateSyncTimer?.cancel();
    _signalSubscription?.cancel();
    _composerController.dispose();
    _chatScrollController.dispose();
    _remoteControlFocusNode.dispose();
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
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Session paused. Remote screen is frozen.',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
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
              decoration: BoxDecoration(
                border: Border.all(color: Colors.redAccent, width: 4),
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: _buildRemoteCanvas(colors)),
                  if (!_hideAllHud)
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        color: Colors.redAccent,
                        child: Text(
                          'Connected with: ${widget.deviceId}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
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
        Positioned(
          left: 10,
          top: 8,
          child: Tooltip(
            message: _hideAllHud ? 'Show bars' : 'Hide bars',
            child: _buildSmallOverlayButton(
              _hideAllHud ? Icons.visibility : Icons.visibility_off,
              _toggleHudVisibility,
              colors,
            ),
          ),
        ),
        if (!_hideAllHud)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                    tooltip: _isFullScreen ? 'Restore' : 'Full screen',
                    onPressed: () => _toggleFullScreen(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: 'Close session',
                    onPressed: () => _closeSession(),
                  ),
                ],
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
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Text(
          _captureError.isEmpty ? 'Waiting for remote stream...' : 'Capture issue: $_captureError',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return Stack(
      children: [
        Container(
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
                _sendKeyboardEvent(event, phase: 'down');
                if (managed) {
                  _startManagedRepeat(event);
                }
              }
              if (event is KeyUpEvent) {
                _stopManagedRepeat(event.logicalKey.keyId);
                _pressedLogicalKeys.remove(event.logicalKey.keyId);
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

                  final frameAspect = _remoteFrameWidth / _remoteFrameHeight;
                  final viewAspect = w / h;
                  double drawW;
                  double drawH;
                  double offsetX = 0;
                  double offsetY = 0;

                  if (_fillRemoteViewport) {
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

                  final inX = (local.dx - offsetX);
                  final inY = (local.dy - offsetY);
                  if (!_fillRemoteViewport && (inX < 0 || inY < 0 || inX > drawW || inY > drawH)) {
                    return null;
                  }

                  final nx = (inX / drawW).clamp(0.0, 1.0);
                  final ny = (inY / drawH).clamp(0.0, 1.0);
                  return Offset(nx, ny);
                }

                return Listener(
                  onPointerDown: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                      ? (event) {
                          _revealOverlayTemporarily();
                          final p = normalize(event.localPosition);
                          if (p == null) return;
                          _flushPendingMove();
                          _rightButtonPressed = event.buttons == kSecondaryMouseButton;
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
                          if (now - _lastPointerMoveMs < 2) return;
                          _lastPointerMoveMs = now;
                          final p = normalize(event.localPosition);
                          if (p == null) return;
                          _sendMoveIfNeeded(p);
                        }
                      : null,
                  onPointerMove: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                      ? (event) {
                          final now = DateTime.now().millisecondsSinceEpoch;
                          if (now - _lastPointerMoveMs < 2) return;
                          _lastPointerMoveMs = now;
                          final p = normalize(event.localPosition);
                          if (p == null) return;
                          _sendMoveIfNeeded(p);
                        }
                      : null,
                  onPointerUp: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                      ? (event) {
                          final p = normalize(event.localPosition);
                          if (p == null) return;
                          _flushPendingMove();
                          _sendInputEvent(
                            _rightButtonPressed ? 'right_up' : 'left_up',
                            normalizedX: p.dx,
                            normalizedY: p.dy,
                          );
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
                  child: Image.memory(
                    _remoteScreenFrame!,
                    width: double.infinity,
                    height: double.infinity,
                    fit: _fillRemoteViewport ? BoxFit.cover : BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                );
              },
            ),
          ),
        ),
        // Pause overlay
        if (_isSessionPaused)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
              alignment: Alignment.center,
              child: Column(
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _togglePauseSession,
                        icon: const Icon(Icons.play_circle),
                        label: const Text('Resume'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor:Colors.white,
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
                () {
                  setState(() => _keyboardInputEnabledForUser2 = !_keyboardInputEnabledForUser2);
                  _sendInputPolicy();
                },
                colors,
                isActive: _keyboardInputEnabledForUser2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                _mouseInputEnabledForUser2 ? Icons.mouse : Icons.mouse_outlined,
                _mouseInputEnabledForUser2 ? 'Mouse ON' : 'Mouse OFF',
                () {
                  setState(() => _mouseInputEnabledForUser2 = !_mouseInputEnabledForUser2);
                  _sendInputPolicy();
                },
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
                        ? 'Re├ºu de: $from${fileSize.isNotEmpty ? '  ΓÇó  $fileSize' : ''}'
                        : 'Envoy├⌐${fileSize.isNotEmpty ? '  ΓÇó  $fileSize' : ''}',
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
                      'Status: $status  ${progress.isNotEmpty ? 'ΓÇó $progress%' : ''}  ${speed.isNotEmpty ? 'ΓÇó $speed' : ''}',
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
      _showMessage(context, 'Aucune donn├⌐e disponible', _getColors(context));
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
      _showMessage(context, 'Fichier sauvegard├⌐: $outputPath', _getColors(context));
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
    _isCapturing = true;
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
      final b64 = base64Encode(bytes);
      final sent = _sendSessionPayload(
        messageType: 'screen_frame',
        payload: {
          'frameData': b64,
          'frameWidth': _localFrameWidth,
          'frameHeight': _localFrameHeight,
          'screenCount': _localScreenCount,
          'screenIndex': _selectedLocalScreenIndex,
          'captureLeft': _localCaptureLeft,
          'captureTop': _localCaptureTop,
          'captureWidth': _localCaptureWidth,
          'captureHeight': _localCaptureHeight,
        },
      );
      if (!sent) {
        if (mounted) setState(() => _captureError = 'session send failed');
        _sendCaptureStatus('error', 'Session send failed');
        return;
      }
      if (mounted) setState(() { _framesSent++; _captureError = ''; });
      _sendCaptureStatus('ok', '');
      if (_framesSent % 30 == 0) {
        print('[ScreenShare] Sent frame #$_framesSent (${bytes.length} bytes) ${_localFrameWidth}x$_localFrameHeight');
      }
    } catch (e) {
      if (mounted) setState(() => _captureError = 'capture/send exception: $e');
      _sendCaptureStatus('error', 'Capture/send exception: $e');
    } finally {
      _isCapturing = false;
    }
  }

  Future<Uint8List?> _captureLocalScreenToJpegBytes() async {
    if (!io.Platform.isWindows) return null;

    // Use stable paths so antivirus exclusions can target one precise location.
    final stableDir = io.Directory('${io.Platform.environment['LOCALAPPDATA']}\\BIMStreaming\\screenshare');
    if (!stableDir.existsSync()) {
      stableDir.createSync(recursive: true);
    }
    final outputPath = '${stableDir.path}\\frame.jpg';
    final scriptPath = '${stableDir.path}\\capture.ps1';
    final escapedOutput = outputPath.replaceAll("'", "''");

    // Script ├⌐crit dans un fichier (.ps1) pour ├⌐viter tout probl├¿me d'encodage en ligne de commande
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
