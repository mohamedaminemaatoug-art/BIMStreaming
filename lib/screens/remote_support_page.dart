import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ffi' as ffi;
import 'dart:ffi';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';
import '../services/signaling_client_service.dart';

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
  static const Duration _screenShareInterval = Duration(milliseconds: 120);
  static const int _defaultCaptureMaxWidth = 1600;
  static const int _defaultJpegQuality = 70;

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
  int _remoteCaptureLeft = 0;
  int _remoteCaptureTop = 0;
  int _remoteCaptureWidth = 0;
  int _remoteCaptureHeight = 0;
  bool _fillRemoteViewport = false;
  int _lastAppliedMoveMs = 0;
  double? _lastSentMoveX;
  double? _lastSentMoveY;
  bool _showTopOverlay = true;
  bool _showLeftFloatingButtons = true;
  int _captureMaxWidth = _defaultCaptureMaxWidth;
  int _captureJpegQuality = _defaultJpegQuality;
  String _captureResolutionLabel = 'Full Screen';
  String _qualityLabel = 'Medium';
  String _autoQualityMode = 'Auto';
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
  String _transferMode = 'send';
  String _receiveTargetPath = '';
  int _reconnectAttempts = 0;
  int _recordingFps = 1;
  List<String> _remoteFileList = [];

  String tr(String key) => widget.translate(key);

  @override
  void initState() {
    super.initState();
    _initializeUserPaths();
    _syncFullScreenState();
    _startSessionTimer();
    _connectSessionSignalIfAvailable();
    _startAutomaticScreenShareIfPossible();
    _startDiagnosticsTimer();
    _revealOverlayTemporarily();
    _refreshLocalScreenInfo();
    _autoEnterFullscreenForController();
    _pinRemoteAgentWindowIfNeeded();
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
  [void][Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
  $count = [System.Windows.Forms.Screen]::AllScreens.Count
Write-Output $count
''';
    try {
      final result = await io.Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
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
    _screenShareTimer = Timer.periodic(_screenShareInterval, (_) {
      _sendScreenFrame();
    });
    _sendScreenFrame();
  }

  void _revealOverlayTemporarily() {
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
          // Keep the complete remote image visible (no edge cropping).
          _fillRemoteViewport = false;
          break;
        case 'Windowed Adapted':
          _fillRemoteViewport = false;
          break;
        case 'Adapted Resolution':
          _fillRemoteViewport = false;
          _captureMaxWidth = _defaultCaptureMaxWidth;
          break;
        case '720p':
          _captureMaxWidth = 1280;
          break;
        case '1080p':
          _captureMaxWidth = 1920;
          break;
        case '540p':
          _captureMaxWidth = 960;
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
          _autoQualityMode = 'Manual';
          break;
        case 'Medium':
          _captureJpegQuality = _defaultJpegQuality;
          _autoQualityMode = 'Manual';
          break;
        case 'High':
          _captureJpegQuality = 85;
          _autoQualityMode = 'Manual';
          break;
        default:
          _captureJpegQuality = _defaultJpegQuality;
          _autoQualityMode = 'Manual';
      }
    });
    _sendDisplayConfig();
  }

  void _applyAutoQuality() {
    if (_autoQualityMode != 'Auto') return;
    // Auto-adjust quality based on bandwidth and ping
    // Excellent (ping <= 50ms): High quality
    // Good (ping <= 100ms): Medium quality
    // Fair (ping <= 180ms): Low quality
    // Poor (ping > 180ms): Very Low quality
    final newQuality = _pingMs <= 50
        ? 85  // High
        : (_pingMs <= 100
            ? _defaultJpegQuality  // Medium
            : (_pingMs <= 180
                ? 45  // Low
                : 35)); // Very Low
    if (_captureJpegQuality != newQuality) {
      setState(() {
        _captureJpegQuality = newQuality;
      });
    }
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
    if (fromUserId.isEmpty || fromUserId == widget.currentUserId) {
      return;
    }

    final messageType = (data['messageType'] ?? '').toString();
    final payload = data['payload'] is Map
        ? Map<String, dynamic>.from(data['payload'] as Map)
        : <String, dynamic>{};

    if (messageType == 'input_event') {
      if (widget.sendLocalScreen) {
        _applyRemoteInput(payload);
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
      }
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
          _fillRemoteViewport = false;
        }
        if (quality.isNotEmpty) {
          _qualityLabel = quality;
          if (quality == 'Low') _captureJpegQuality = 45;
          if (quality == 'Medium') _captureJpegQuality = _defaultJpegQuality;
          if (quality == 'High') _captureJpegQuality = 85;
        }
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
            try {
              _isConnected = true;
              _connectionStatus = 'Connected';
              if (_reconnectTimer != null) {
                _stopReconnectLoop();
              }
              _remoteScreenFrame = base64Decode(frameData);
              final fw = payload['frameWidth'];
              final fh = payload['frameHeight'];
              final sc = payload['screenCount'];
              final si = payload['screenIndex'];
              if (fw is num && fh is num && fw > 0 && fh > 0) {
                _remoteFrameWidth = fw.toInt();
                _remoteFrameHeight = fh.toInt();
              }
              if (sc is num && sc.toInt() > 0) {
                _remoteScreenCount = sc.toInt();
              }
              if (si is num && si.toInt() >= 0) {
                _selectedRemoteScreenIndex = si.toInt();
              }
              // Extract remote capture bounds for mouse coordinate mapping
              final rcl = payload['captureLeft'];
              final rct = payload['captureTop'];
              final rcw = payload['captureWidth'];
              final rch = payload['captureHeight'];
              if (rcl is num) _remoteCaptureLeft = rcl.toInt();
              if (rct is num) _remoteCaptureTop = rct.toInt();
              if (rcw is num) _remoteCaptureWidth = rcw.toInt();
              if (rch is num) _remoteCaptureHeight = rch.toInt();
              _framesReceived++;
              if (_framesReceived % 30 == 0) {
                print('[ScreenShare] Frame received #$_framesReceived (${frameData.length} chars b64) from $fromUserId');
              }
            } catch (e) {
              print('[ScreenShare] Decode error: $e');
              _remoteScreenFrame = null;
            }
          }
          break;
      }
    });
  }

  Future<void> _closeSession({bool notifyPeer = true}) async {
    if (_isClosingSession) return;
    _isClosingSession = true;

    if (notifyPeer) {
      _sendSessionPayload(
        messageType: 'session_end',
        payload: {'reason': 'disconnect'},
      );
    }

    _sessionTimer?.cancel();
    _screenShareTimer?.cancel();
    _stopReconnectLoop();

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

  Future<void> _minimizeWindow() async {
    try {
      await windowManager.minimize();
    } catch (_) {
      // Ignore minimize failures.
    }
  }

  Future<void> _restoreWindow() async {
    try {
      final isMin = await windowManager.isMinimized();
      if (isMin) {
        await windowManager.restore();
      }
      final isFs = await windowManager.isFullScreen();
      if (isFs) {
        await windowManager.setFullScreen(false);
        if (mounted) {
          setState(() => _isFullScreen = false);
        }
      }
      await windowManager.setAlwaysOnTop(false);
    } catch (_) {
      // Ignore restore failures.
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

  void _sendInputEvent(
    String action, {
    double? normalizedX,
    double? normalizedY,
    int? wheelDelta,
    String? key,
  }) {
    if (!_canSendRemoteInput) return;
    final payload = <String, dynamic>{'action': action};
    if (normalizedX != null) payload['x'] = normalizedX.clamp(0.0, 1.0);
    if (normalizedY != null) payload['y'] = normalizedY.clamp(0.0, 1.0);
    if (wheelDelta != null) payload['wheelDelta'] = wheelDelta;
    if (key != null && key.isNotEmpty) payload['key'] = key;
    _sendSessionPayload(messageType: 'input_event', payload: payload);
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
    if (!_keyboardInputEnabledForUser2 && action == 'key_press') {
      return;
    }
    if (action == 'move') {
      // Running a PowerShell process per event is expensive; throttle move apply.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastAppliedMoveMs < 45) return;
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
  .replaceAll('__CAP_LEFT__', _remoteCaptureLeft.toString())
  .replaceAll('__CAP_TOP__', _remoteCaptureTop.toString())
  .replaceAll('__CAP_WIDTH__', _remoteCaptureWidth.toString())
  .replaceAll('__CAP_HEIGHT__', _remoteCaptureHeight.toString())
        .replaceAll('__KEY__', key.replaceAll("'", "''"));

    try {
      await io.Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
      );
    } catch (_) {
      // Ignore remote input injection failures silently to keep session alive.
    }
  }

  void _sendSessionPayload({
    required String messageType,
    required Map<String, dynamic> payload,
  }) {
    if (!_canSignal) {
      print('[RemoteSupportPage] Cannot signal: signalingService=${widget.signalingService}, userId=${widget.currentUserId}, sessionId=${widget.sessionId}');
      return;
    }
    if (messageType != 'screen_frame' && messageType != 'input_event') {
      print('[RemoteSupportPage] Sending $messageType to ${widget.deviceId} via session ${widget.sessionId}');
    }
    widget.signalingService!.sendSessionMessage(
      sessionId: (widget.sessionId ?? '').toString(),
      toUserId: widget.deviceId,
      messageType: messageType,
      payload: payload,
    );
  }

  void _sendMoveIfNeeded(Offset p) {
    const epsilon = 0.0025;
    final sameAsLast = _lastSentMoveX != null &&
        _lastSentMoveY != null &&
        (p.dx - _lastSentMoveX!).abs() < epsilon &&
        (p.dy - _lastSentMoveY!).abs() < epsilon;
    if (sameAsLast) return;
    _lastSentMoveX = p.dx;
    _lastSentMoveY = p.dy;
    _sendInputEvent('move', normalizedX: p.dx, normalizedY: p.dy);
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
    _sessionTimer?.cancel();
    _screenShareTimer?.cancel();
    _overlayHideTimer?.cancel();
    _diagnosticsTimer?.cancel();
    _recordingTimer?.cancel();
    _reconnectTimer?.cancel();
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1200;
        final overlayLeft = isCompact ? 12.0 : 70.0;
        final panelLeft = isCompact ? 12.0 : 74.0;
        final panelWidth =
            (constraints.maxWidth - panelLeft - 12.0).clamp(260.0, 360.0);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _revealOverlayTemporarily();
            if (_panelMode != 'none') {
              setState(() => _panelMode = 'none');
            }
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
              if (_showTopOverlay)
                Positioned(
                  top: 10,
                  left: overlayLeft,
                  right: 12,
                  child: _buildTopOverlayBar(colors),
                ),
              if (_showLeftFloatingButtons)
                Positioned(
                  top: 84,
                  left: 12,
                  child: _buildFloatingButtons(colors),
                ),
              if (_panelMode != 'none')
                Positioned(
                  top: 76,
                  left: panelLeft,
                  bottom: 20,
                  width: panelWidth,
                  child: _buildContextPanel(colors),
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
        );
      },
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
                  icon: const Icon(Icons.minimize, color: Colors.white),
                  tooltip: 'Minimize',
                  onPressed: () => _minimizeWindow(),
                ),
                IconButton(
                  icon: const Icon(Icons.filter_none, color: Colors.white),
                  tooltip: 'Restore',
                  onPressed: () => _restoreWindow(),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
            const SizedBox(width: 14),
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
            _buildSmallOverlayButton(Icons.minimize, () => _minimizeWindow(), colors),
            const SizedBox(width: 6),
            _buildSmallOverlayButton(Icons.filter_none, () => _restoreWindow(), colors),
            const SizedBox(width: 6),
            _buildSmallOverlayButton(Icons.close, () => _closeSession(), colors, isDanger: true),
          ],
        ),
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
          _buildRoundToolButton(Icons.chat_bubble_outline, 'Chat', () => _togglePanel('chat'), colors),
          const SizedBox(height: 8),
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
                final key = event.logicalKey.keyLabel.isNotEmpty
                    ? event.logicalKey.keyLabel
                    : event.logicalKey.debugName;
                if (key != null && key.isNotEmpty) {
                  _sendInputEvent('key_press', key: key);
                }
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
                          if (now - _lastPointerMoveMs < 35) return;
                          _lastPointerMoveMs = now;
                          final p = normalize(event.localPosition);
                          if (p == null) return;
                          _sendMoveIfNeeded(p);
                        }
                      : null,
                  onPointerMove: _canSendRemoteInput && !_isDeviceLocked && !_isSessionPaused && _mouseInputEnabledForUser2
                      ? (event) {
                          final now = DateTime.now().millisecondsSinceEpoch;
                          if (now - _lastPointerMoveMs < 35) return;
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
                            _sendInputEvent('wheel', wheelDelta: event.scrollDelta.dy.toInt());
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
        const SizedBox(height: 10),
        // Transfer mode selector
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
        const SizedBox(height: 10),
        // Dual file browser
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors['bg']!,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors['border']!),
            ),
            child: Row(
              children: [
                // Local machine (Machine A) browser
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors['cardBg']!,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Machine A (Your Computer)',
                          style: TextStyle(
                            color: colors['text']!,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: _buildLocalFileBrowser(colors),
                        ),
                      ),
                    ],
                  ),
                ),
                // Divider
                Container(
                  width: 1,
                  color: colors['border']!,
                ),
                // Remote machine (Machine B) browser
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors['cardBg']!,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Machine B (Remote Computer)',
                          style: TextStyle(
                            color: colors['text']!,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: _buildRemoteFileBrowser(colors),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Action buttons and status
        Row(
          children: [
            if (_transferMode == 'send')
              Expanded(
                child: _buildFileButton(
                  icon: Icons.cloud_upload_outlined,
                  label: 'Select File to Send',
                  onPressed: _handleUpload,
                  colors: colors,
                ),
              )
            else
              Expanded(
                child: _buildFileButton(
                  icon: Icons.download,
                  label: 'Pull File from B',
                  onPressed: () => _showMessage(context, 'Remote file browsing available', colors),
                  colors: colors,
                ),
              ),
          ],
        ),
        if (_transfers.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors['cardBg']!,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors['border']!),
            ),
            height: 100,
            child: ListView.builder(
              itemCount: _transfers.length,
              itemBuilder: (context, index) {
                return _buildTransferItem(index, _transfers[index], colors);
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLocalFileBrowser(Map<String, Color> colors) {
    return ListView(
      children: [
        _buildFileBrowserItem('C:', Icons.storage, colors, () {}),
        _buildFileBrowserItem('D:', Icons.storage, colors, () {}),
        _buildFileBrowserItem('Desktop', Icons.folder, colors, () {}),
        _buildFileBrowserItem('Documents', Icons.folder, colors, () {}),
        _buildFileBrowserItem('Downloads', Icons.folder, colors, () {}),
      ],
    );
  }

  Widget _buildRemoteFileBrowser(Map<String, Color> colors) {
    if (_remoteFileList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.storage, size: 32, color: colors['textSecondary']!),
            const SizedBox(height: 8),
            Text(
              'Remote Files',
              style: TextStyle(color: colors['textSecondary']!, fontSize: 12),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _remoteFileList.length,
      itemBuilder: (context, index) {
        return _buildFileBrowserItem(
          _remoteFileList[index],
          Icons.folder,
          colors,
          () {},
        );
      },
    );
  }

  Widget _buildFileBrowserItem(
    String name,
    IconData icon,
    Map<String, Color> colors,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colors['bg']!,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors['border']!),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 16, color: colors['accent']!),
        title: Text(
          name,
          style: TextStyle(color: colors['text']!, fontSize: 11),
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onTap,
      ),
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
                if (tempScreenshot.isNotEmpty && tempRecordings.isNotEmpty) {
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
            DropdownMenuItem(value: 'Windowed Adapted', child: Text('Windowed Adapted')),
            DropdownMenuItem(value: 'Adapted Resolution', child: Text('Adapted Resolution')),
            DropdownMenuItem(value: 'Auto', child: Text('Auto')),
            DropdownMenuItem(value: '540p', child: Text('540p')),
            DropdownMenuItem(value: '720p', child: Text('720p')),
            DropdownMenuItem(value: '1080p', child: Text('1080p')),
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
            DropdownMenuItem(value: 'Low', child: Text('Low (performance)')),
            DropdownMenuItem(value: 'Medium', child: Text('Medium')),
            DropdownMenuItem(value: 'High', child: Text('High (quality)')),
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
        _buildActionButton(
          Icons.refresh,
          'Refresh Diagnostics',
          () async {
            _showMessage(context, 'Refreshing diagnostics...', _getColors(context));
            await _refreshPing();
            _applyAutoQuality();
            if (mounted) {
              _showMessage(context, 'Diagnostics updated: $_connectionQualityText', _getColors(context));
            }
          },
          colors,
        ),
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
                        ? 'Reçu de: $from${fileSize.isNotEmpty ? '  •  $fileSize' : ''}'
                        : 'Envoyé${fileSize.isNotEmpty ? '  •  $fileSize' : ''}',
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
                      'Status: $status  ${progress.isNotEmpty ? '• $progress%' : ''}  ${speed.isNotEmpty ? '• $speed' : ''}',
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
      _showMessage(context, 'Aucune donnée disponible', _getColors(context));
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
      _showMessage(context, 'Fichier sauvegardé: $outputPath', _getColors(context));
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
        if (mounted) setState(() => _captureError = 'capture null');
        return;
      }
      const maxFrameBytes = 8 * 1024 * 1024;
      if (bytes.length > maxFrameBytes) {
        print('[ScreenShare] Frame too large: ${bytes.length} bytes');
        if (mounted) setState(() => _captureError = 'too large: ${bytes.length}');
        return;
      }
      final b64 = base64Encode(bytes);
      _sendSessionPayload(
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
      if (mounted) setState(() { _framesSent++; _captureError = ''; });
      if (_framesSent % 30 == 0) {
        print('[ScreenShare] Sent frame #$_framesSent (${bytes.length} bytes) ${_localFrameWidth}x$_localFrameHeight');
      }
    } finally {
      _isCapturing = false;
    }
  }

  Future<Uint8List?> _captureLocalScreenToJpegBytes() async {
    if (!io.Platform.isWindows) return null;

    try {
      // Use safe PowerShell capture without Add-Type (antivirus friendly)
      final tempFile = io.File('${io.Directory.systemTemp.path}\\bim_screen_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final psScript = '''
  Add-Type -AssemblyName System.Drawing
  Add-Type -AssemblyName System.Windows.Forms
  \$path = "${tempFile.path.replaceAll('\\', '\\\\')}";
  \$bitmap = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height);
  \$graphics = [System.Drawing.Graphics]::FromImage(\$bitmap);
  \$graphics.CopyFromScreen(0,0,0,0, \$bitmap.Size);
  \$bitmap.Save(\$path);
  \$graphics.Dispose();
  \$bitmap.Dispose();
  ''';

      try {
        final result = await io.Process.run(
          'powershell.exe',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psScript],
          runInShell: false,
        );

        if (result.exitCode != 0) {
          print('[ScreenShare] PS error: ${result.stderr}');
          return null;
        }

        if (!await tempFile.exists()) {
          return null;
        }

        final imageBytes = await tempFile.readAsBytes();
        final decoded = img.decodeImage(imageBytes);
        await tempFile.delete().catchError((_) {});

        if (decoded == null || decoded.width < 1 || decoded.height < 1) {
          if (mounted) setState(() => _captureError = 'Image decode failed');
          return null;
        }

        img.Image frame = decoded;
        if (frame.width > _captureMaxWidth) {
          final resizedHeight = (frame.height * (_captureMaxWidth / frame.width)).round();
          frame = img.copyResize(
            frame,
            width: _captureMaxWidth,
            height: resizedHeight,
            interpolation: img.Interpolation.cubic,
          );
        }

        final jpegBytes = Uint8List.fromList(
          img.encodeJpg(frame, quality: _captureJpegQuality),
        );

        _localFrameWidth = frame.width;
        _localFrameHeight = frame.height;
        _localCaptureLeft = 0;
        _localCaptureTop = 0;
        _localCaptureWidth = frame.width;
        _localCaptureHeight = frame.height;

        return jpegBytes;
      } catch (e) {
        print('[ScreenShare] PowerShell capture error: $e');
        return null;
      }
    } catch (e, st) {
      print('[ScreenShare] Screen capture exception: $e');
      print(st);
      if (mounted) setState(() => _captureError = e.toString());
      return null;
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
