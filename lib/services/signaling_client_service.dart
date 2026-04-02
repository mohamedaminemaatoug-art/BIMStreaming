import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

class SignalEvent {
  final String type;
  final Map<String, dynamic> data;

  const SignalEvent({required this.type, required this.data});
}

class SignalingClientService {
  SignalingClientService({
    String? wsBaseUrl,
  }) :
        _wsBaseUrl = _resolveWsBaseUrl(wsBaseUrl),
        _clientInstanceId = _generateClientInstanceId();

  final String _wsBaseUrl;
  final String _clientInstanceId;

  static String _generateClientInstanceId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random.secure().nextInt(1 << 30);
    return '$now-$random';
  }

  static String _resolveWsBaseUrl(String? explicit) {
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }

    const fromDefine = String.fromEnvironment('BIM_SIGNAL_URL', defaultValue: '');
    if (fromDefine.trim().isNotEmpty) {
      return fromDefine.trim();
    }

    final fromEnv = io.Platform.environment['BIM_SIGNAL_URL'] ?? '';
    if (fromEnv.trim().isNotEmpty) {
      return fromEnv.trim();
    }

    return 'ws://127.0.0.1:8080/api/v1/ws';
  }

  final StreamController<SignalEvent> _eventsController = StreamController<SignalEvent>.broadcast();
  WebSocketChannel? _channel;
  bool _connected = false;
  String? _currentUserId;

  Stream<SignalEvent> get events => _eventsController.stream;
  bool get isConnected => _connected;
  String get clientInstanceId => _clientInstanceId;

  Future<bool> connect({required String userId}) async {
    disconnect();
    try {
      final normalizedUserId = userId.trim();
      if (normalizedUserId.isEmpty) {
        _connected = false;
        return false;
      }
      final uri = Uri.parse('$_wsBaseUrl?user_id=${Uri.encodeQueryComponent(normalizedUserId)}');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _currentUserId = normalizedUserId;
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

    final from = fromUserId.trim();
    final to = toUserId.trim();
    if (from.isEmpty || to.isEmpty) {
      return {'success': false, 'message': 'invalid users'};
    }

    final sessionId = 'S-${DateTime.now().millisecondsSinceEpoch}';
    _channel!.sink.add(jsonEncode({
      'type': 'connection_request',
      'session_id': sessionId,
      'from': from,
      'to': to,
      'payload': {
        'from_name': fromName,
        'fromInstanceId': _clientInstanceId,
      },
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

    final sid = sessionId.trim();
    final from = fromUserId.trim();
    final to = toUserId.trim();
    if (sid.isEmpty || from.isEmpty || to.isEmpty) {
      return {'success': false, 'message': 'invalid session/users'};
    }

    _channel!.sink.add(jsonEncode({
      'type': accepted ? 'connection_accept' : 'connection_reject',
      'session_id': sid,
      'from': from,
      'to': to,
      'payload': {
        'fromInstanceId': _clientInstanceId,
      },
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

    final sid = sessionId.trim();
    final to = toUserId.trim();
    if (sid.isEmpty || to.isEmpty) {
      return false;
    }

    _channel!.sink.add(jsonEncode({
      'type': 'session_message',
      'data': {
        'sessionId': sid,
        'fromUserId': _currentUserId,
        'fromInstanceId': _clientInstanceId,
        'toUserId': to,
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
