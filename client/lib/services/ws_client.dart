import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'app_config.dart';

class WsException implements Exception {
  final String message;
  final dynamic originalError;

  WsException(this.message, {this.originalError});

  @override
  String toString() => message;
}

class WsClient {
  static final WsClient _instance = WsClient._internal();

  late final StreamController<Map<String, dynamic>> _eventController;
  WebSocketChannel? _channel;

  String? _token;
  int _reconnectAttempts = 0;
  int _maxReconnectAttempts = 10;
  int _reconnectDelayMs = 1000;
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  Timer? _reconnectTimer;
  StreamSubscription<dynamic>? _subscription;

  factory WsClient() => _instance;

  WsClient._internal() {
    _eventController = StreamController<Map<String, dynamic>>.broadcast();
  }

  String _normalizeHostPortUrl(String raw) {
    return raw.trim().replaceFirstMapped(
      RegExp(r'^(https?://localhost)(\d+)(/.*)?$', caseSensitive: false),
      (match) =>
          '${match.group(1)}:${match.group(2)}${match.group(3) ?? ''}',
    );
  }

  String _resolveWsUrl() {
    final configFileSignalUrl = AppConfig.instance.signalUrl ?? '';
    if (configFileSignalUrl.isNotEmpty) {
      return '$configFileSignalUrl?token=${Uri.encodeComponent(_token ?? '')}';
    }
    final configuredSignalUrl =
      const String.fromEnvironment('BIM_SIGNAL_URL').trim().isNotEmpty
        ? const String.fromEnvironment('BIM_SIGNAL_URL').trim()
        : (Platform.environment['BIM_SIGNAL_URL'] ?? '').trim();
    if (configuredSignalUrl.isNotEmpty) {
      final signal = _normalizeHostPortUrl(configuredSignalUrl);
      return '$signal?token=${Uri.encodeComponent(_token ?? '')}';
    }

    final configuredApiUrl =
      const String.fromEnvironment('BIM_API_URL').trim().isNotEmpty
        ? const String.fromEnvironment('BIM_API_URL').trim()
        : const String.fromEnvironment('BIM_API_BASE_URL').trim().isNotEmpty
          ? const String.fromEnvironment('BIM_API_BASE_URL').trim()
          : (Platform.environment['BIM_API_URL'] ??
              Platform.environment['BIM_API_BASE_URL'] ??
              '')
            .trim();
    if (configuredApiUrl.isNotEmpty) {
      final normalizedApi = _normalizeHostPortUrl(configuredApiUrl);
      final base = normalizedApi.replaceFirst(RegExp(r'/api/v1/?$'), '');
      final wsBase = base.startsWith('https://')
          ? base.replaceFirst('https://', 'wss://')
          : base.replaceFirst('http://', 'ws://');
      return '$wsBase/api/v1/ws?token=${Uri.encodeComponent(_token ?? '')}';
    }

    return 'ws://localhost:8080/api/v1/ws?token=${Uri.encodeComponent(_token ?? '')}';
  }

  /// Get the stream of incoming events
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  /// Check if connected
  bool get isConnected => _channel != null;

  /// Connect to WebSocket server
  Future<void> connect(String token) async {
    if (_isConnecting || isConnected) {
      return;
    }

    _token = token;
    _isConnecting = true;
    _shouldReconnect = true;
    _reconnectAttempts = 0;

    await _performConnect();
  }

  /// Perform the actual connection
  Future<void> _performConnect() async {
    try {
      final wsUrl = _resolveWsUrl();

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Listen to WebSocket stream
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _reconnectAttempts = 0;
      _isConnecting = false;
    } catch (e) {
      _isConnecting = false;
      _onError(WsException('Connection failed: $e', originalError: e));
    }
  }

  /// Handle incoming message
  void _onMessage(dynamic message) {
    try {
      if (message is String) {
        final data = jsonDecode(message) as Map<String, dynamic>;
        _eventController.add(data);
      }
    } catch (e) {
      _eventController.addError(WsException('Failed to parse message: $e'));
    }
  }

  /// Handle connection error
  void _onError(dynamic error) {
    _channel = null;
    _subscription?.cancel();
    _subscription = null;

    if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delayMs = _reconnectDelayMs * (_reconnectAttempts ~/ 2);

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(milliseconds: delayMs), _performConnect);
    } else if (_shouldReconnect) {
      _eventController.addError(
        WsException('Max reconnection attempts reached: $error'),
      );
    }
  }

  /// Handle connection closed
  void _onDone() {
    _channel = null;
    _subscription?.cancel();
    _subscription = null;

    if (_shouldReconnect && _reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      final delayMs = _reconnectDelayMs * (_reconnectAttempts ~/ 2);

      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(Duration(milliseconds: delayMs), _performConnect);
    }
  }

  /// Send a message to the server
  void send(Map<String, dynamic> data) {
    if (!isConnected) {
      _eventController.addError(WsException('Not connected'));
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (e) {
      _eventController.addError(WsException('Failed to send message: $e'));
    }
  }

  /// Disconnect cleanly
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _isConnecting = false;
  }

  /// Dispose the client
  Future<void> dispose() async {
    await disconnect();
    await _eventController.close();
  }
}
