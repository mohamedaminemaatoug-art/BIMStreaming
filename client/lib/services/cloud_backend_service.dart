import 'package:bim_streaming/models/user_model.dart';

class CloudBackendConfig {
  static const String apiBaseUrl = String.fromEnvironment('BIM_API_BASE_URL');
  static const String signalUrl = String.fromEnvironment('BIM_SIGNAL_URL');

  static bool get hasApi => apiBaseUrl.trim().isNotEmpty;

  static bool get hasSignal => signalUrl.trim().isNotEmpty;

  // Cloud mode is enabled only if at least one endpoint is provided at build time.
  static bool get isConfigured => hasApi || hasSignal;
}

class CloudLoginResult {
  final bool success;
  final String message;
  final User? user;
  final String? token;

  const CloudLoginResult({
    required this.success,
    required this.message,
    this.user,
    this.token,
  });
}

class CloudCreateSessionResult {
  final bool success;
  final String message;
  final String? sessionId;
  final String? sessionCode;

  const CloudCreateSessionResult({
    required this.success,
    required this.message,
    this.sessionId,
    this.sessionCode,
  });
}

class CloudSignalChannel {
  final String sessionId;

  CloudSignalChannel(this.sessionId);

  void dispose() {}
}

class CloudBackendService {
  bool _authenticated = false;

  bool get isAuthenticated => _authenticated;

  Future<CloudLoginResult> login(String userId, String password) async {
    _authenticated = false;
    return const CloudLoginResult(
      success: false,
      message: 'Cloud backend unavailable. Running in local mode.',
    );
  }

  Future<CloudCreateSessionResult> createSession({
    required String targetAccountId,
    required String sessionPassword,
  }) async {
    return const CloudCreateSessionResult(
      success: false,
      message: 'Cloud session service unavailable. Running in local mode.',
    );
  }

  CloudSignalChannel? openSignalChannel(String sessionId) {
    if (!CloudBackendConfig.hasSignal) {
      return null;
    }
    return CloudSignalChannel(sessionId);
  }

  void logout() {
    _authenticated = false;
  }
}
