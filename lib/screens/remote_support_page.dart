import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
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
  static const int _maxCaptureWidth = 1600;
  static const int _jpegQuality = 70;

  bool _isConnected = true;
  String _connectionStatus = 'Connected';
  bool _isEncrypted = true;
  String _sessionTime = '00:00:00';
  String _encryptionType = 'AES-256 Encrypted';
  bool _isFullScreen = false;
  bool _isRecording = false;
  bool _audioEnabled = true;
  bool _isBlackoutMode = false;
  bool _isDeviceLocked = false;
  bool _isRebooting = false;
  bool _isScreenSharing = false;
  bool _isCapturing = false;
  int _framesSent = 0;
  int _framesReceived = 0;
  String _captureError = '';
  String _activeTab = 'chat';
  final TextEditingController _composerController = TextEditingController();
  final List<String> _chatMessages = [];
  final List<String> _commandResults = [];
  final List<Map<String, String>> _transfers = [];
  Uint8List? _remoteScreenFrame;
  Timer? _sessionTimer;
  Timer? _screenShareTimer;
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
  bool _isRemoteViewExpanded = false;
  int _lastAppliedMoveMs = 0;
  double? _lastSentMoveX;
  double? _lastSentMoveY;

  String tr(String key) => widget.translate(key);

  @override
  void initState() {
    super.initState();
    _syncFullScreenState();
    _startSessionTimer();
    _connectSessionSignalIfAvailable();
    _startAutomaticScreenShareIfPossible();
    if (!widget.sendLocalScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _remoteControlFocusNode.requestFocus();
        }
      });
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

  void _handleSignalEvent(SignalEvent event) {
    if (!mounted || event.type != 'session_message') return;

    final rawData = event.data['data'];
    if (rawData is! Map) return;

    final data = Map<String, dynamic>.from(rawData as Map);
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

    if (messageType != 'screen_frame' && messageType != 'input_event') {
      print('[RemoteSupportPage] Received $messageType from $fromUserId: $payload');
    }

    setState(() {
      switch (messageType) {
        case 'chat':
          final text = (payload['text'] ?? '').toString();
          if (text.isNotEmpty) {
            print('[Chat] Added from peer: $text');
            _chatMessages.add('${widget.deviceName}: $text');
          }
          break;
        case 'command':
          final cmd = (payload['command'] ?? '').toString();
          final result = (payload['result'] ?? '').toString();
          if (cmd.isNotEmpty) {
            _commandResults.add('[${widget.deviceName}] $cmd');
            _commandResults.add(
              result.isNotEmpty
                  ? result
                  : '[${widget.deviceName}] ${tr('command_executed_success')}',
            );
          }
          break;
        case 'upload':
          final fileName = (payload['fileName'] ?? '').toString();
          final fileData = (payload['fileData'] ?? '').toString();
          final rawSize = payload['fileSize'];
          final fileSize = rawSize is int ? rawSize : (rawSize is double ? rawSize.toInt() : 0);
          if (fileName.isNotEmpty) {
            _transfers.add({
              'type': 'received',
              'fileName': fileName,
              'from': fromUserId,
              'fileData': fileData,
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
              _remoteScreenFrame = base64Decode(frameData);
              final fw = payload['frameWidth'];
              final fh = payload['frameHeight'];
              if (fw is num && fh is num && fw > 0 && fh > 0) {
                _remoteFrameWidth = fw.toInt();
                _remoteFrameHeight = fh.toInt();
              }
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

  void _closeSession({bool notifyPeer = true}) {
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

    if (!mounted) return;

    Navigator.of(context).pop();
    widget.onExitToRemoteControl?.call();
  }

  bool get _canSendRemoteInput =>
      _canSignal && _isConnected && !widget.sendLocalScreen;

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
  .replaceAll('__CAP_LEFT__', _localCaptureLeft.toString())
  .replaceAll('__CAP_TOP__', _localCaptureTop.toString())
  .replaceAll('__CAP_WIDTH__', _localCaptureWidth.toString())
  .replaceAll('__CAP_HEIGHT__', _localCaptureHeight.toString())
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
  }

  Future<void> _toggleFullScreen() async {
    final nextValue = !_isFullScreen;
    await windowManager.setFullScreen(nextValue);
    if (!mounted) return;
    setState(() => _isFullScreen = nextValue);
    _showMessage(context, _isFullScreen ? tr('full_screen') : tr('exit_full_screen'), _getColors(context));
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _screenShareTimer?.cancel();
    _signalSubscription?.cancel();
    _composerController.dispose();
    _remoteControlFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _getColors(context);

    return Scaffold(
      appBar: _isFullScreen
          ? null
          : AppBar(
        backgroundColor: colors['bg']!,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors['text']!),
          onPressed: () => _closeSession(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('remote_support_title'),
              style: TextStyle(
                color: colors['text']!,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              tr('internal_secure_network'),
              style: TextStyle(
                color: colors['textSecondary']!,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Icon(Icons.circle, color: _isConnected ? Colors.green : Colors.grey, size: 8),
                      const SizedBox(width: 4),
                      Text(
                        _isConnected ? tr('status_connected') : tr('status_disconnected'),
                        style: TextStyle(color: colors['textSecondary']!, fontSize: 11),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${tr('session_label')}: $_sessionTime',
                        style: TextStyle(color: colors['textSecondary']!, fontSize: 11),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        _isEncrypted ? Icons.lock : Icons.lock_open,
                        color: _isEncrypted ? Colors.green : Colors.orange,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _encryptionType,
                        style: TextStyle(color: colors['textSecondary']!, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          // Partie gauche - Vue principale
          Expanded(
            flex: _isFullScreen ? 1 : 3,
            child: Stack(
              children: [
                // Top Actions Bar
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: colors['bg']!,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        _buildActionButton(
                          Icons.screenshot_monitor,
                          tr('btn_screenshot'),
                          () => _takeScreenshot(),
                          colors,
                          enabled: _isConnected,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                          _isRecording ? tr('btn_stop_record') : tr('btn_record'),
                          _toggleRecording,
                          colors,
                          isActive: _isRecording,
                          enabled: _isConnected,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _audioEnabled ? Icons.mic : Icons.mic_off,
                          tr('btn_audio'),
                          _toggleAudio,
                          colors,
                          isActive: _audioEnabled,
                          enabled: _isConnected,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _isDeviceLocked ? Icons.lock_open : Icons.lock,
                          tr('btn_lock'),
                          _lockDevice,
                          colors,
                          isActive: _isDeviceLocked,
                          enabled: _isConnected && !_isRebooting,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          Icons.restart_alt,
                          tr('btn_reboot'),
                          _rebootDevice,
                          colors,
                          isActive: _isRebooting,
                          enabled: _isConnected && !_isRebooting,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _isBlackoutMode ? Icons.visibility_off : Icons.visibility,
                          tr('btn_privacy'),
                          _toggleBlackout,
                          colors,
                          isActive: _isBlackoutMode,
                          enabled: _isConnected,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                          _isFullScreen ? tr('exit_full_screen') : tr('full_screen'),
                          _toggleFullScreen,
                          colors,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _fillRemoteViewport ? Icons.fit_screen_outlined : Icons.fit_screen,
                          _fillRemoteViewport ? 'Fit' : 'Fill',
                          () => setState(() => _fillRemoteViewport = !_fillRemoteViewport),
                          colors,
                          isActive: _fillRemoteViewport,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _isRemoteViewExpanded ? Icons.close_fullscreen : Icons.open_in_full,
                          _isRemoteViewExpanded ? 'Small view' : 'Full view',
                          () => setState(() => _isRemoteViewExpanded = !_isRemoteViewExpanded),
                          colors,
                          isActive: _isRemoteViewExpanded,
                        ),
                        const Spacer(),
                        _buildActionButton(Icons.close, tr('btn_disconnect'), () => _closeSession(), colors, isDanger: true),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: colors['cardBg']!,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    // Keep remote surface below top action bar to preserve accurate pointer mapping.
                    padding: const EdgeInsets.only(top: 58),
                    child: _isBlackoutMode
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.privacy_tip, size: 80, color: colors['accent']!),
                              const SizedBox(height: 24),
                              Text(
                                tr('privacy_mode_active'),
                                style: TextStyle(color: colors['text']!, fontSize: 18, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                tr('screen_is_hidden'),
                                style: TextStyle(color: colors['textSecondary']!, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                        : _remoteScreenFrame != null
                          ? Container(
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: RawKeyboardListener(
                                focusNode: _remoteControlFocusNode,
                                autofocus: !widget.sendLocalScreen,
                                onKey: (event) {
                                  if (!_canSendRemoteInput) return;
                                  if (event is RawKeyDownEvent) {
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
                                        // BoxFit.cover geometry: image fills viewport with center crop.
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
                                        // BoxFit.contain geometry: whole frame visible with letterboxing.
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
                                      onPointerHover: _canSendRemoteInput
                                          ? (event) {
                                              final now = DateTime.now().millisecondsSinceEpoch;
                                              if (now - _lastPointerMoveMs < 35) return;
                                              _lastPointerMoveMs = now;
                                              final p = normalize(event.localPosition);
                                              if (p == null) return;
                                              _sendMoveIfNeeded(p);
                                            }
                                          : null,
                                      onPointerDown: _canSendRemoteInput
                                          ? (event) {
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
                                          : null,
                                      onPointerMove: _canSendRemoteInput
                                          ? (event) {
                                              final now = DateTime.now().millisecondsSinceEpoch;
                                              if (now - _lastPointerMoveMs < 35) return;
                                              _lastPointerMoveMs = now;
                                              final p = normalize(event.localPosition);
                                              if (p == null) return;
                                              _sendMoveIfNeeded(p);
                                            }
                                          : null,
                                      onPointerUp: _canSendRemoteInput
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
                                      onPointerSignal: _canSendRemoteInput
                                          ? (event) {
                                              if (event is PointerScrollEvent) {
                                                _sendInputEvent(
                                                  'wheel',
                                                  wheelDelta: event.scrollDelta.dy.toInt(),
                                                );
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
                            )
                        : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.device_hub,
                                size: 80,
                                color: colors['accent']!,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                _isConnected ? tr('status_connected') : tr('status_disconnected'),
                                style: TextStyle(
                                  color: colors['text']!,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isFullScreen
                                    ? tr('full_screen_mode')
                                    : tr('remote_session_active'),
                                style: TextStyle(
                                  color: colors['textSecondary']!,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Diagnostic screen share
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '📤 Envoyées: $_framesSent  📥 Reçues: $_framesReceived',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    if (_captureError.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '⚠ $_captureError',
                                          style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    if (_isScreenSharing && _captureError.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text(
                                          '⏳ En attente du flux distant...',
                                          style: TextStyle(color: Colors.amber, fontSize: 11),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                  ),
                ),
              ],
            ),
          ),
          if (!_isFullScreen && !_isRemoteViewExpanded)
          // Partie droite - Panneau de contrôle
          Container(
            width: _remoteScreenFrame != null ? 240 : 300,
            color: colors['bg']!,
            child: Column(
              children: [
                // Onglets horizontaux
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      _buildTab('chat', tr('tab_chat'), Icons.chat_bubble_outline, colors),
                      const SizedBox(width: 4),
                      _buildTab('transfer', tr('tab_transfer'), Icons.folder_outlined, colors),
                      const SizedBox(width: 4),
                      _buildTab('command', tr('tab_command'), Icons.terminal, colors),
                    ],
                  ),
                ),
                // Contenu selon l'onglet actif
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildTabContent(colors),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String tabId, String label, IconData icon, Map<String, Color> colors) {
    final isActive = _activeTab == tabId;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = tabId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? colors['accent']! : colors['cardBg']!,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? Colors.white : colors['text']!,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive ? Colors.white : colors['text']!,
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(Map<String, Color> colors) {
    switch (_activeTab) {
      case 'chat':
        return _buildChatContent(colors);
      case 'command':
        return _buildCommandContent(colors);
      case 'transfer':
      default:
        return _buildTransferContent(colors);
    }
  }

  Widget _buildChatContent(Map<String, Color> colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors['bg']!,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors['border']!),
            ),
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
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

  Widget _buildCommandContent(Map<String, Color> colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors['bg']!,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors['border']!),
            ),
            padding: const EdgeInsets.all(12),
            child: ListView.builder(
              itemCount: _commandResults.length,
              itemBuilder: (context, index) {
                return _buildCommandLine(_commandResults[index], colors);
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
              Icon(
                Icons.terminal,
                size: 20,
                color: colors['textSecondary']!,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _composerController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  style: TextStyle(color: colors['text']!),
                  decoration: InputDecoration(
                    hintText: tr('command_hint'),
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
                return _buildTransferItem(_transfers[index], colors);
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildFileButton(
          icon: Icons.cloud_upload_outlined,
          label: tr('btn_upload_file'),
          onPressed: _handleUpload,
          colors: colors,
        ),
      ],
    );
  }

  Widget _buildTransferItem(
    Map<String, String> transfer,
    Map<String, Color> colors,
  ) {
    final type = transfer['type'] ?? 'sent';
    final fileName = transfer['fileName'] ?? '';
    final from = transfer['from'] ?? '';
    final fileSize = transfer['fileSize'] ?? '';
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
              ),
          ],
        ),
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colors['accent']!,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandLine(String line, Map<String, Color> colors) {
    final isCommand = line.contains('> ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        line,
        style: TextStyle(
          color: isCommand ? colors['accent']! : colors['text']!,
          fontSize: 13,
          fontFamily: 'Courier New',
          fontWeight: isCommand ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  void _sendMessage() {
    final value = _composerController.text.trim();
    if (value.isEmpty) return;
    
    print('[RemoteSupportPage] Sending $value via tab=$_activeTab');
    
    setState(() {
      if (_activeTab == 'chat') {
        _chatMessages.add('You: $value');
        _sendSessionPayload(
          messageType: 'chat',
          payload: {'text': value},
        );
      } else if (_activeTab == 'command') {
        _commandResults.add('> $value');
        _commandResults.add('[Local] ${tr('command_executed_success')}');
        _sendSessionPayload(
          messageType: 'command',
          payload: {'command': value},
        );
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
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: tr('save_downloaded_file'),
      fileName: transfer['fileName'] ?? 'fichier_recu',
    );
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

    final fileName = 'remote_screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: tr('save_screenshot_file'),
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
    );

    if (!mounted) return;

    if (outputPath == null || outputPath.isEmpty) {
      _showMessage(context, tr('screenshot_save_canceled'), _getColors(context));
      return;
    }

    try {
      await io.File(outputPath).writeAsBytes(_remoteScreenFrame!, flush: true);
      if (!mounted) return;
      final time = DateTime.now().toIso8601String();
      setState(() {
        _commandResults.add('> screenshot --capture');
        _commandResults.add('[$time] ${tr('screenshot_taken')}');
      });
      _sendSessionPayload(
        messageType: 'command',
        payload: {
          'command': '> screenshot --capture',
          'result': '[$time] Screenshot pris par ${widget.currentUserId ?? widget.deviceId}',
        },
      );
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

    // Use stable paths so antivirus exclusions can target one precise location.
    final stableDir = io.Directory('${io.Platform.environment['LOCALAPPDATA']}\\BIMStreaming\\screenshare');
    if (!stableDir.existsSync()) {
      stableDir.createSync(recursive: true);
    }
    final outputPath = '${stableDir.path}\\frame.jpg';
    final scriptPath = '${stableDir.path}\\capture.ps1';
    final escapedOutput = outputPath.replaceAll("'", "''");

    // Script écrit dans un fichier (.ps1) pour éviter tout problème d'encodage en ligne de commande
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
$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
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
        .replaceAll('MAX_WIDTH', _maxCaptureWidth.toString())
        .replaceAll('JPEG_QUALITY', '${_jpegQuality}L');

    await io.File(scriptPath).writeAsString(scriptContent);

    try {
      final result = await io.Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath],
      );
      if (result.exitCode != 0) {
        final err = '${result.stderr}'.trim();
        print('[ScreenShare] PS1 failed (exit=${result.exitCode}): $err');
        if (mounted) setState(() => _captureError = 'PS1 exit=${result.exitCode}: ${err.substring(0, err.length.clamp(0, 80))}');
        return null;
      }
      final file = io.File(outputPath);
      if (!file.existsSync()) {
        print('[ScreenShare] Output JPEG not found: $outputPath');
        if (mounted) setState(() => _captureError = 'file not found');
        return null;
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
      return bytes;
    } catch (e) {
      print('[ScreenShare] Exception: $e');
      if (mounted) setState(() => _captureError = e.toString());
      return null;
    } finally {
      try { io.File(outputPath).deleteSync(); } catch (_) {}
    }
  }

  Future<bool> _captureLocalScreenToPath(String outputPath) async {
    if (!io.Platform.isWindows) {
      return false;
    }

    final escapedPath = outputPath.replaceAll("'", "''");
    final script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bitmap.Size)
$bitmap.Save('__OUTPUT_PATH__', [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
'''.replaceAll('__OUTPUT_PATH__', escapedPath);

    try {
      final result = await io.Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
      );
      return result.exitCode == 0 && io.File(outputPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  void _toggleRecording() {
    if (!_isConnected) return;
    setState(() => _isRecording = !_isRecording);
    _showMessage(context, _isRecording ? tr('recording_started') : tr('recording_stopped'), _getColors(context));
  }

  void _toggleAudio() {
    if (!_isConnected) return;
    setState(() => _audioEnabled = !_audioEnabled);
    _showMessage(context, _audioEnabled ? tr('audio_enabled') : tr('audio_disabled'), _getColors(context));
  }

  void _lockDevice() {
    if (!_isConnected || _isRebooting) return;
    setState(() => _isDeviceLocked = !_isDeviceLocked);
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
              setState(() => _isRebooting = true);
              _showMessage(context, tr('device_rebooting'), _getColors(context));
              Future.delayed(const Duration(seconds: 3), () {
                if (!mounted) return;
                setState(() {
                  _isRebooting = false;
                  _isDeviceLocked = false;
                });
              });
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
    _showMessage(context, _isBlackoutMode ? tr('privacy_mode_enabled') : tr('privacy_mode_disabled'), _getColors(context));
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
