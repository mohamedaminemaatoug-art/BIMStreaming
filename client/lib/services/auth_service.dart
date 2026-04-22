import 'package:bim_streaming/models/user_model.dart' hide AuthSession;

import 'api_client.dart';
import 'ws_client.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();

  final ApiClient _apiClient = ApiClient();
  AuthSession? _currentSession;

  factory AuthService() => _instance;

  AuthService._internal();

  Future<void> init() async {
    await _apiClient.init();
  }

  Future<AuthResult> restoreSession() async {
    try {
      await _apiClient.init();
      if (!_apiClient.isAuthenticated) {
        return const AuthResult(success: false, message: 'Not authenticated');
      }
      final me = await _apiClient.get('/users/me');
      final userData = Map<String, dynamic>.from(
        (me['user'] as Map?) ?? const {},
      );
      final user = _parseUser(userData);

      _currentSession = AuthSession(
        user: user,
        token: _apiClient.accessToken ?? '',
        refreshToken: _apiClient.refreshToken ?? '',
        loginTime: DateTime.now(),
      );
      return AuthResult(success: true, message: 'Session restored', user: user);
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'Session restore failed',
      );
    }
  }

  Future<AuthResult> login(String userIdOrEmail, String password) async {
    try {
      final response = await _apiClient.post(
        '/auth/login',
        body: {'identifier': userIdOrEmail, 'password': password},
      );

      final requires2FA = response['requires_2fa'] as bool? ?? false;
      if (requires2FA) {
        final tempToken = (response['temp_token'] ?? '').toString();
        return AuthResult(
          success: true,
          message: '2FA required',
          requiresTwoFactor: true,
          tempToken: tempToken,
        );
      }

      return _consumeAuthTokensResponse(response);
    } on ApiException catch (e) {
      return AuthResult(
        success: false,
        message: e.message,
        errorCode: e.statusCode?.toString(),
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Login failed: $e',
        errorCode: 'LOGIN_FAILED',
      );
    }
  }

  Future<AuthResult> register({
    required String username,
    required String fullName,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.post(
        '/auth/register',
        body: {
          'username': username,
          'full_name': fullName,
          'email': email,
          'password': password,
          'confirm_password': password,
        },
      );
      if (response.containsKey('access_token') &&
          response.containsKey('refresh_token') &&
          response.containsKey('user')) {
        return _consumeAuthTokensResponse(response);
      }
      return AuthResult(
        success: true,
        message: (response['message'] ?? 'Registration successful').toString(),
        pendingUserId: (response['user_id'] ?? '').toString(),
      );
    } on ApiException catch (e) {
      return AuthResult(
        success: false,
        message: e.message,
        errorCode: e.statusCode?.toString(),
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Registration failed: $e',
        errorCode: 'REGISTER_FAILED',
      );
    }
  }

  Future<AuthResult> verifyEmail({
    required String userId,
    required String code,
  }) async {
    try {
      final response = await _apiClient.post(
        '/auth/verify-email',
        body: {'user_id': userId, 'code': code},
      );
      return _consumeAuthTokensResponse(response);
    } on ApiException catch (e) {
      return AuthResult(
        success: false,
        message: e.message,
        errorCode: e.statusCode?.toString(),
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Verification failed: $e',
        errorCode: 'VERIFY_FAILED',
      );
    }
  }

  Future<AuthResult> completeTwoFactor({
    required String tempToken,
    required String code,
  }) async {
    try {
      final response = await _apiClient.post(
        '/auth/2fa/challenge',
        body: {'temp_token': tempToken, 'code': code},
      );
      return _consumeAuthTokensResponse(response);
    } on ApiException catch (e) {
      return AuthResult(
        success: false,
        message: e.message,
        errorCode: e.statusCode?.toString(),
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: '2FA verification failed: $e',
        errorCode: 'TWO_FACTOR_FAILED',
      );
    }
  }

  Future<AuthResult> _consumeAuthTokensResponse(
    Map<String, dynamic> response,
  ) async {
    final accessToken = response['access_token'] as String?;
    final refreshToken = response['refresh_token'] as String?;
    final userData = response['user'] as Map<String, dynamic>?;

    if (accessToken == null || refreshToken == null || userData == null) {
      return const AuthResult(
        success: false,
        message: 'Invalid authentication response from server.',
        errorCode: 'INVALID_AUTH_RESPONSE',
      );
    }

    await _apiClient.setTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    try {
      await WsClient().connect(accessToken);
    } catch (_) {
      // WebSocket is best-effort; auth still succeeds.
    }
    final user = _parseUser(userData);

    _currentSession = AuthSession(
      user: user,
      token: accessToken,
      refreshToken: refreshToken,
      loginTime: DateTime.now(),
    );

    return AuthResult(
      success: true,
      message: 'Authentication successful',
      user: user,
    );
  }

  User _parseUser(Map<String, dynamic> userData) {
    String readNullableString(dynamic value) {
      if (value == null) {
        return '';
      }
      if (value is Map) {
        final isValid = value['Valid'];
        if (isValid == false) {
          return '';
        }
        final nested = value['String'];
        if (nested != null) {
          return nested.toString().trim();
        }
      }
      return value.toString().trim();
    }

    final avatarUrl = readNullableString(userData['avatar_url']);
    final displayName = readNullableString(userData['display_name']);
    final username = readNullableString(userData['username']);
    final email = readNullableString(userData['email']);
    final resolvedName = displayName.isNotEmpty
        ? displayName
        : (username.isNotEmpty ? username : email);

    return User(
      id: (userData['id'] ?? '').toString(),
      name: resolvedName,
      password: '',
      role: UserRole.client,
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
    );
  }

  Future<void> logout() async {
    final refreshToken = _apiClient.refreshToken;
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _apiClient.postWithoutRetry(
          '/auth/logout',
          body: {'refresh_token': refreshToken},
        );
      }
    } catch (_) {
      // Best effort logout.
    } finally {
      try {
        await WsClient().disconnect();
      } catch (_) {}
      _currentSession = null;
      await _apiClient.clearTokens();
    }
  }

  Future<void> refreshToken() async {
    final newToken = await _apiClient.refreshAccessToken();
    final session = _currentSession;
    if (session != null) {
      _currentSession = session.copyWith(token: newToken);
    }
  }

  AuthSession? getCurrentSession() => _currentSession;

  bool get isAuthenticated => _apiClient.isAuthenticated;

  User? get currentUser => _currentSession?.user;
}

class AuthResult {
  final bool success;
  final String message;
  final User? user;
  final String? errorCode;
  final bool requiresTwoFactor;
  final String? tempToken;
  final String? pendingUserId;

  const AuthResult({
    required this.success,
    required this.message,
    this.user,
    this.errorCode,
    this.requiresTwoFactor = false,
    this.tempToken,
    this.pendingUserId,
  });
}

class AuthSession {
  final User user;
  final String token;
  final String refreshToken;
  final DateTime loginTime;
  final DateTime expiryTime;

  AuthSession({
    required this.user,
    required this.token,
    required this.refreshToken,
    required this.loginTime,
    Duration sessionDuration = const Duration(minutes: 15),
  }) : expiryTime = loginTime.add(sessionDuration);

  bool get isExpired => DateTime.now().isAfter(expiryTime);

  bool get isValid => !isExpired;

  AuthSession copyWith({
    User? user,
    String? token,
    String? refreshToken,
    DateTime? loginTime,
    DateTime? expiryTime,
  }) {
    final updatedLoginTime = loginTime ?? this.loginTime;
    final updatedExpiry = expiryTime ?? this.expiryTime;
    return AuthSession(
      user: user ?? this.user,
      token: token ?? this.token,
      refreshToken: refreshToken ?? this.refreshToken,
      loginTime: updatedLoginTime,
      sessionDuration: updatedExpiry.difference(updatedLoginTime),
    );
  }
}
