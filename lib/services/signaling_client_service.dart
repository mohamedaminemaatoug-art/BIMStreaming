import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class SignalEvent {
  final String type;
  final Map<String, dynamic> data;

  const SignalEvent({required this.type, required this.data});
}

class SignalingClientService {
  SignalingClientService({
    String wsBaseUrl = 'ws://127.0.0.1:8080/api/v1/ws',
  }) : _wsBaseUrl = wsBaseUrl;

  final String _wsBaseUrl;

  final StreamController<SignalEvent> _eventsController = StreamController<SignalEvent>.broadcast();
  WebSocketChannel? _channel;
  bool _connected = false;
  String? _currentUserId;

  Stream<SignalEvent> get events => _eventsController.stream;
  bool get isConnected => _connected;

  Future<bool> connect({required String userId}) async {
    disconnect();
    try {
      final uri = Uri.parse('$_wsBaseUrl?user_id=${Uri.encodeQueryComponent(userId)}');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _currentUserId = userId;
      _connected = true;
      _channel!.stream.listen(
        _onMessage,
        onError: (_) {
          _connected = false;
        },
        onDone: () {
          _connected = false;
        },
      );
      return true;
    } catch (_) {
      _connected = false;
      _channel = null;
      _currentUserId = null;
      return false;
    }
  }

  void _onMessage(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);
      if (decoded is! Map<String, dynamic>) return;
      final type = (decoded['type'] ?? '').toString();
      if (type.isEmpty) return;
        final data = Map<String, dynamic>.from(decoded);
      _eventsController.add(SignalEvent(type: type, data: data));
    } catch (_) {
      // Ignore parse errors.
    }
  }

  Future<Map<String, dynamic>> requestSession({
    required String fromUserId,
    required String fromName,
    required String toUserId,
  }) async {
    if (!_connected || _channel == null) {
      return {'success': false, 'message': 'signaling disconnected'};
    }

    final sessionId = 'S-${DateTime.now().millisecondsSinceEpoch}';
    _channel!.sink.add(jsonEncode({
      'type': 'connection_request',
      'session_id': sessionId,
      'from': fromUserId,
      'to': toUserId,
      'payload': {'from_name': fromName},
    }));
    return {'success': true, 'sessionId': sessionId};
  }

  Future<Map<String, dynamic>> respondSession({
    required String sessionId,
    required String fromUserId,
    required String toUserId,
    required bool accepted,
  }) async {
    if (!_connected || _channel == null) {
      return {'success': false, 'message': 'signaling disconnected'};
    }

    _channel!.sink.add(jsonEncode({
      'type': accepted ? 'connection_accept' : 'connection_reject',
      'session_id': sessionId,
      'from': fromUserId,
      'to': toUserId,
      'payload': {},
    }));
    return {'success': true};
  }

  bool sendSessionMessage({
    required String sessionId,
    required String toUserId,
    required String messageType,
    required Map<String, dynamic> payload,
  }) {
    if (!_connected || _channel == null || _currentUserId == null) {
      return false;
    }

    _channel!.sink.add(jsonEncode({
      'type': 'session_message',
      'data': {
        'sessionId': sessionId,
        'fromUserId': _currentUserId,
        'toUserId': toUserId,
        'messageType': messageType,
        'payload': payload,
      },
    }));
    return true;
  }

  void disconnect() {
    _connected = false;
    _currentUserId = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _eventsController.close();
  }
}
