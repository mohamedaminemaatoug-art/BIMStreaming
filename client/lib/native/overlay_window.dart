import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HostSessionOverlay {
  static const MethodChannel _channel = MethodChannel('host_session_overlay');
  static VoidCallback? _disconnectRequested;
  static bool _handlerInstalled = false;

  static void bindDisconnectHandler(VoidCallback? handler) {
    _disconnectRequested = handler;
    if (!_handlerInstalled) {
      _channel.setMethodCallHandler(_handleMethodCall);
      _handlerInstalled = true;
    }
  }

  static Future<bool> startOverlay({required String label}) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'start',
        {'label': label},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> stopOverlay() async {
    try {
      final result = await _channel.invokeMethod<bool>('stop');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> startPrivacyOverlay() async {
    try {
      final result = await _channel.invokeMethod<bool>('startPrivacy');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> stopPrivacyOverlay() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopPrivacy');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'disconnectRequested') {
      _disconnectRequested?.call();
    }
  }
}

