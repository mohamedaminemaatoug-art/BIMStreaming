import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'app_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

String _resolveApiBaseUrl() {
  final configFileApiUrl = AppConfig.instance.apiUrl ?? '';
  if (configFileApiUrl.isNotEmpty) {
    var v = configFileApiUrl;
    if (!v.endsWith('/api/v1')) v = v.endsWith('/') ? '${v}api/v1' : '$v/api/v1';
    return v;
  }

  String normalize(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return value;
    }

    // Recover from malformed localhost URL forms like http://localhost8080.
    value = value.replaceFirstMapped(
      RegExp(r'^(https?://localhost)(\d+)(/.*)?$', caseSensitive: false),
      (match) =>
          '${match.group(1)}:${match.group(2)}${match.group(3) ?? ''}',
    );

    if (!value.endsWith('/api/v1')) {
      if (value.endsWith('/')) {
        value = '${value}api/v1';
      } else {
        value = '$value/api/v1';
      }
    }
    return value;
  }

  final configured = (
    const String.fromEnvironment('BIM_API_URL')
        .trim()
        .isNotEmpty
        ? const String.fromEnvironment('BIM_API_URL')
        : const String.fromEnvironment('BIM_API_BASE_URL')
  ).trim().isNotEmpty
      ? (const String.fromEnvironment('BIM_API_URL').trim().isNotEmpty
          ? const String.fromEnvironment('BIM_API_URL')
          : const String.fromEnvironment('BIM_API_BASE_URL'))
      : (Platform.environment['BIM_API_URL'] ??
              Platform.environment['BIM_API_BASE_URL'] ??
              '')
          .trim();
  if (configured.isEmpty) {
    return 'http://localhost:8080/api/v1';
  }
  return normalize(configured);
}

final String _baseUrl = _resolveApiBaseUrl();
const String _accessTokenKey = 'access_token';
const String _refreshTokenKey = 'refresh_token';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  ApiException(this.message, {this.statusCode, this.originalError});

  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(String message) : super(message, statusCode: 401);
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late final FlutterSecureStorage _secureStorage;
  late final SharedPreferences _prefs;
  late final http.Client _httpClient;

  String? _accessToken;
  String? _refreshToken;
  bool _isRefreshing = false;
  bool _secureStorageAvailable = true;
  final List<Completer<String>> _refreshCompleters = [];

  factory ApiClient() => _instance;

  ApiClient._internal() {
    _secureStorage = const FlutterSecureStorage();
    _httpClient = http.Client();
  }

  /// Initialize the client - loads stored tokens with fallback to SharedPreferences
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️  SharedPreferences init failed: $e');
      }
    }

    // Try secure storage first
    try {
      _accessToken = await _secureStorage.read(key: _accessTokenKey);
      _refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      if (kDebugMode && (_accessToken != null || _refreshToken != null)) {
        print('✅ Tokens loaded from secure storage');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️  Secure storage read failed: $e - Falling back to SharedPreferences');
      }
      _secureStorageAvailable = false;
      // Fallback to SharedPreferences
      try {
        _accessToken = _prefs.getString(_accessTokenKey);
        _refreshToken = _prefs.getString(_refreshTokenKey);
        if (kDebugMode && (_accessToken != null || _refreshToken != null)) {
          print('✅ Tokens loaded from SharedPreferences (fallback)');
        }
      } catch (e2) {
        if (kDebugMode) {
          print('❌ Failed to load tokens from both storages: $e2');
        }
      }
    }
  }

  /// Get current access token
  String? get accessToken => _accessToken;

  /// Get current refresh token
  String? get refreshToken => _refreshToken;

  /// Expose the base URL for multipart and external request scenarios.
  String get baseUrl => _baseUrl;

  /// Check if user is authenticated
  bool get isAuthenticated => _accessToken != null;

  /// Store tokens after login
  Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;

    // Try to store in secure storage
    if (_secureStorageAvailable) {
      try {
        await Future.wait([
          _secureStorage.write(key: _accessTokenKey, value: accessToken),
          _secureStorage.write(key: _refreshTokenKey, value: refreshToken),
        ]);
        if (kDebugMode) {
          print('✅ Tokens stored in secure storage');
        }
        return;
      } catch (e) {
        if (kDebugMode) {
          print('⚠️  Secure storage write failed: $e - Falling back to SharedPreferences');
        }
        _secureStorageAvailable = false;
      }
    }

    // Fallback to SharedPreferences
    try {
      await Future.wait([
        _prefs.setString(_accessTokenKey, accessToken),
        _prefs.setString(_refreshTokenKey, refreshToken),
      ]);
      if (kDebugMode) {
        print('✅ Tokens stored in SharedPreferences (fallback)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to store tokens: $e');
      }
      throw ApiException('Failed to store tokens: $e');
    }
  }

  /// Clear tokens on logout
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;

    List<String> failures = [];

    // Try to clear from secure storage
    if (_secureStorageAvailable) {
      try {
        await Future.wait([
          _secureStorage.delete(key: _accessTokenKey),
          _secureStorage.delete(key: _refreshTokenKey),
        ]);
        if (kDebugMode) {
          print('✅ Tokens cleared from secure storage');
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️  Secure storage clear failed: $e');
        }
        failures.add(e.toString());
      }
    }

    // Also clear from SharedPreferences
    try {
      await Future.wait([
        _prefs.remove(_accessTokenKey),
        _prefs.remove(_refreshTokenKey),
      ]);
      if (kDebugMode) {
        print('✅ Tokens cleared from SharedPreferences');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️  SharedPreferences clear failed: $e');
      }
      failures.add(e.toString());
    }

    if (failures.isNotEmpty) {
      throw ApiException('Failed to clear tokens: ${failures.join(', ')}');
    }
  }

  /// Refresh the access token using refresh token
  Future<String> _refreshAccessToken() async {
    if (_isRefreshing) {
      // Wait for the ongoing refresh
      final completer = Completer<String>();
      _refreshCompleters.add(completer);
      return completer.future;
    }

    if (_refreshToken == null) {
      throw UnauthorizedException('No refresh token available');
    }

    _isRefreshing = true;
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': _refreshToken}),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw ApiException('Request timeout'),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = data['access_token'] as String?;

        if (newAccessToken == null) {
          throw ApiException('Invalid refresh response');
        }

        _accessToken = newAccessToken;
        
        // Try to store in secure storage first
        if (_secureStorageAvailable) {
          try {
            await _secureStorage.write(key: _accessTokenKey, value: newAccessToken);
            if (kDebugMode) {
              print('✅ Refreshed access token stored in secure storage');
            }
          } catch (e) {
            if (kDebugMode) {
              print('⚠️  Secure storage write failed: $e - Falling back to SharedPreferences');
            }
            _secureStorageAvailable = false;
            // Fallback to SharedPreferences
            try {
              await _prefs.setString(_accessTokenKey, newAccessToken);
              if (kDebugMode) {
                print('✅ Refreshed access token stored in SharedPreferences (fallback)');
              }
            } catch (e2) {
              if (kDebugMode) {
                print('❌ Failed to store refreshed token: $e2');
              }
            }
          }
        } else {
          // Already failed before, use SharedPreferences directly
          try {
            await _prefs.setString(_accessTokenKey, newAccessToken);
          } catch (e) {
            if (kDebugMode) {
              print('⚠️  SharedPreferences write failed during refresh: $e');
            }
          }
        }

        // Notify all waiters
        for (final completer in _refreshCompleters) {
          completer.complete(newAccessToken);
        }
        _refreshCompleters.clear();

        return newAccessToken;
      } else if (response.statusCode == 401) {
        await clearTokens();
        throw UnauthorizedException('Refresh token expired');
      } else {
        throw ApiException(
          'Token refresh failed',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      // Notify all waiters with error
      for (final completer in _refreshCompleters) {
        completer.completeError(e);
      }
      _refreshCompleters.clear();
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }

  Future<String> refreshAccessToken() => _refreshAccessToken();

  /// Build headers with auth
  Map<String, String> _getHeaders({Map<String, String>? extra}) {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }

    if (extra != null) {
      headers.addAll(extra);
    }

    return headers;
  }

  /// Internal method to handle response and auto-refresh on 401
  Future<http.Response> _handleRequest(
    Future<http.Response> Function() request,
  ) async {
    var response = await request();

    if (response.statusCode == 401 && isAuthenticated) {
      try {
        await _refreshAccessToken();
        response = await request();
      } catch (e) {
        rethrow;
      }
    }

    return response;
  }

  /// GET request
  Future<Map<String, dynamic>> get(String endpoint) async {
    final response = await _handleRequest(
      () => _httpClient
          .get(Uri.parse('$_baseUrl$endpoint'), headers: _getHeaders())
          .timeout(const Duration(seconds: 30)),
    );

    return _handleResponse(response);
  }

  /// POST request
  Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _handleRequest(
      () => _httpClient
          .post(
            Uri.parse('$_baseUrl$endpoint'),
            headers: _getHeaders(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30)),
    );

    return _handleResponse(response);
  }

  /// POST request without automatic refresh retry.
  Future<Map<String, dynamic>> postWithoutRetry(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _httpClient
        .post(
          Uri.parse('$_baseUrl$endpoint'),
          headers: _getHeaders(),
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(const Duration(seconds: 30));
    return _handleResponse(response);
  }

  /// PATCH request
  Future<Map<String, dynamic>> patch(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _handleRequest(
      () => _httpClient
          .patch(
            Uri.parse('$_baseUrl$endpoint'),
            headers: _getHeaders(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30)),
    );

    return _handleResponse(response);
  }

  /// DELETE request
  Future<Map<String, dynamic>> delete(String endpoint) async {
    final response = await _handleRequest(
      () => _httpClient
          .delete(Uri.parse('$_baseUrl$endpoint'), headers: _getHeaders())
          .timeout(const Duration(seconds: 30)),
    );

    return _handleResponse(response);
  }

  /// Multipart POST request with Authorization header support.
  Future<Map<String, dynamic>> postMultipart(
    String endpoint, {
    required String fieldName,
    required File file,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl$endpoint'),
    );
    final headers = <String, String>{};
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    request.headers.addAll(headers);
    request.files.add(await http.MultipartFile.fromPath(fieldName, file.path));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _handleResponse(response);
  }

  /// Handle HTTP response and throw errors
  Map<String, dynamic> _handleResponse(http.Response response) {
    try {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) {
          return {'success': true};
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      // Parse error response
      Map<String, dynamic> errorData = {};
      if (response.body.isNotEmpty) {
        try {
          errorData = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (e) {
          // Not JSON, will use generic message
        }
      }

      final errorMessage =
          errorData['error'] ??
          errorData['message'] ??
          'HTTP ${response.statusCode}';

      if (response.statusCode == 401) {
        throw UnauthorizedException(errorMessage.toString());
      } else if (response.statusCode == 400) {
        throw ApiException(errorMessage.toString(), statusCode: 400);
      } else if (response.statusCode == 403) {
        throw ApiException(errorMessage.toString(), statusCode: 403);
      } else if (response.statusCode == 404) {
        throw ApiException(errorMessage.toString(), statusCode: 404);
      } else if (response.statusCode >= 500) {
        throw ApiException(
          errorMessage.toString(),
          statusCode: response.statusCode,
        );
      } else {
        throw ApiException(
          errorMessage.toString(),
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to parse response: $e', originalError: e);
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
