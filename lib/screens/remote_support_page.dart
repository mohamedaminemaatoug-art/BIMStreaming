import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';

class RemoteSupportPage extends StatefulWidget {
  final String deviceName;
  final String deviceId;

  const RemoteSupportPage({
    super.key,
    required this.deviceName,
    required this.deviceId,
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
  String? _activeTab;
  final TextEditingController _composerController = TextEditingController();
  final List<String> _chatMessages = [];
  final List<String> _commandResults = [];
  Timer? _sessionTimer;
  int _sessionSeconds = 0;

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
              'BIM Remote Support',
              style: TextStyle(
                color: colors['text']!,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Internal Secure Network',
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
                        _isConnected ? 'Connected' : 'Disconnected',
                        style: TextStyle(color: colors['textSecondary']!, fontSize: 11),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Session: $_sessionTime',
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
            child: const Text('Disconnect', style: TextStyle(color: Colors.white, fontSize: 12)),
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
                Container(
                  color: colors['cardBg']!,
                  child: Center(
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
                          _connectionStatus,
                          style: TextStyle(
                            color: colors['text']!,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isFullScreen
                              ? 'Full screen session mode'
                              : 'Remote session is active',
                          style: TextStyle(
                            color: colors['textSecondary']!,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    tooltip: _isFullScreen ? 'Exit Full Screen' : 'Full Screen',
                    onPressed: _toggleFullScreen,
                    icon: Icon(
                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: colors['text']!,
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
                      _buildTab('chat', 'Chat', Icons.chat_bubble_outline, colors),
                      const SizedBox(width: 4),
                      _buildTab('transfer', 'Transfer', Icons.folder_outlined, colors),
                      const SizedBox(width: 4),
                      _buildTab('command', 'Command', Icons.terminal, colors),
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
                    hintText: 'Message...',
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
                    hintText: 'Write your command...',
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
          label: 'Upload File',
          onPressed: _handleUpload,
          colors: colors,
        ),
        const SizedBox(height: 12),
        _buildFileButton(
          icon: Icons.cloud_download_outlined,
          label: 'Download File',
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
        // Simuler une réponse de commande
        _commandResults.add('Command executed successfully');
      }
    });
    _composerController.clear();
  }

  Future<void> _handleUpload() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (!mounted) return;
    if (result == null || result.files.isEmpty) {
      _showMessage(context, 'Upload canceled.', _getColors(context));
      return;
    }
    final fileName = result.files.single.name;
    _showMessage(context, 'Selected for upload: $fileName', _getColors(context));
  }

  Future<void> _handleDownload() async {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save downloaded file',
      fileName: 'downloaded_file.txt',
    );
    if (!mounted) return;
    if (outputPath == null || outputPath.isEmpty) {
      _showMessage(context, 'Download canceled.', _getColors(context));
      return;
    }
    _showMessage(context, 'Download target selected: $outputPath', _getColors(context));
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

  Map<String, Color> _getColors(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
