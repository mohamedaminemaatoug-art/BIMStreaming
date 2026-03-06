import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';

class RemoteSupportPage extends StatefulWidget {
  final String deviceName;
  final String deviceId;
  final bool isDarkMode;
  final String Function(String) translate;

  const RemoteSupportPage({
    super.key,
    required this.deviceName,
    required this.deviceId,
    required this.isDarkMode,
    required this.translate,
  });

  @override
  State<RemoteSupportPage> createState() => _RemoteSupportPageState();
}

class _RemoteSupportPageState extends State<RemoteSupportPage> {
  bool _isConnected = true;
  String _connectionStatus = 'Connected';
  bool _isEncrypted = true;
  String _sessionTime = '00:00:00';
  String _encryptionType = 'AES-256 Encrypted';
  bool _isFullScreen = false;
  bool _isRecording = false;
  bool _audioEnabled = true;
  bool _isBlackoutMode = false;
  String? _activeTab;
  final TextEditingController _composerController = TextEditingController();
  final List<String> _chatMessages = [];
  final List<String> _commandResults = [];
  Timer? _sessionTimer;
  int _sessionSeconds = 0;

  String tr(String key) => widget.translate(key);

  @override
  void initState() {
    super.initState();
    _syncFullScreenState();
    _startSessionTimer();
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
    _composerController.dispose();
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
          onPressed: () => Navigator.pop(context),
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
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: Text(tr('btn_disconnect'), style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          const SizedBox(width: 16),
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
                        _buildActionButton(Icons.screenshot_monitor, tr('btn_screenshot'), _takeScreenshot, colors),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                          _isRecording ? tr('btn_stop_record') : tr('btn_record'),
                          _toggleRecording,
                          colors,
                          isActive: _isRecording,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _audioEnabled ? Icons.mic : Icons.mic_off,
                          tr('btn_audio'),
                          _toggleAudio,
                          colors,
                          isActive: _audioEnabled,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(Icons.lock, tr('btn_lock'), _lockDevice, colors),
                        const SizedBox(width: 8),
                        _buildActionButton(Icons.restart_alt, tr('btn_reboot'), _rebootDevice, colors),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _isBlackoutMode ? Icons.visibility_off : Icons.visibility,
                          tr('btn_privacy'),
                          _toggleBlackout,
                          colors,
                          isActive: _isBlackoutMode,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                          _isFullScreen ? tr('exit_full_screen') : tr('full_screen'),
                          _toggleFullScreen,
                          colors,
                        ),
                        const Spacer(),
                        _buildActionButton(Icons.close, tr('btn_disconnect'), () => Navigator.pop(context), colors, isDanger: true),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: colors['cardBg']!,
                  margin: const EdgeInsets.only(top: 56),
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
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (!_isFullScreen)
          // Partie droite - Panneau de contrôle
          Container(
            width: 300,
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
        _buildFileButton(
          icon: Icons.cloud_upload_outlined,
          label: tr('btn_upload_file'),
          onPressed: _handleUpload,
          colors: colors,
        ),
        const SizedBox(height: 12),
        _buildFileButton(
          icon: Icons.cloud_download_outlined,
          label: tr('btn_download_file'),
          onPressed: _handleDownload,
          colors: colors,
        ),
      ],
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
    final isCommand = line.startsWith('>');
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
    
    setState(() {
      if (_activeTab == 'chat') {
        _chatMessages.add(value);
      } else if (_activeTab == 'command') {
        _commandResults.add('> $value');
        _commandResults.add(tr('command_executed_success'));
      }
    });
    _composerController.clear();
  }

  Future<void> _handleUpload() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (!mounted) return;
    if (result == null || result.files.isEmpty) {
      _showMessage(context, tr('upload_canceled'), _getColors(context));
      return;
    }
    final fileName = result.files.single.name;
    _showMessage(context, '${tr('selected_for_upload')}: $fileName', _getColors(context));
  }

  Future<void> _handleDownload() async {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: tr('save_downloaded_file'),
      fileName: 'downloaded_file.txt',
    );
    if (!mounted) return;
    if (outputPath == null || outputPath.isEmpty) {
      _showMessage(context, tr('download_canceled'), _getColors(context));
      return;
    }
    _showMessage(context, '${tr('download_target_selected')}: $outputPath', _getColors(context));
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

  void _takeScreenshot() {
    _showMessage(context, tr('screenshot_taken'), _getColors(context));
  }

  void _toggleRecording() {
    setState(() => _isRecording = !_isRecording);
    _showMessage(context, _isRecording ? tr('recording_started') : tr('recording_stopped'), _getColors(context));
  }

  void _toggleAudio() {
    setState(() => _audioEnabled = !_audioEnabled);
    _showMessage(context, _audioEnabled ? tr('audio_enabled') : tr('audio_disabled'), _getColors(context));
  }

  void _lockDevice() {
    _showMessage(context, tr('device_locked'), _getColors(context));
  }

  void _rebootDevice() {
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
              _showMessage(context, tr('device_rebooting'), _getColors(context));
            },
            child: Text(tr('btn_reboot')),
          ),
        ],
      ),
    );
  }

  void _toggleBlackout() {
    setState(() => _isBlackoutMode = !_isBlackoutMode);
    _showMessage(context, _isBlackoutMode ? tr('privacy_mode_enabled') : tr('privacy_mode_disabled'), _getColors(context));
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap, Map<String, Color> colors, {bool isActive = false, bool isDanger = false}) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDanger ? Colors.red[600] : (isActive ? colors['accent']! : colors['cardBg']!),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isDanger ? Colors.red[700]! : colors['border']!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isDanger ? Colors.white : colors['text']!, size: 16),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: isDanger ? Colors.white : colors['text']!, fontSize: 12, fontWeight: FontWeight.w500)),
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
