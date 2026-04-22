import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

String _resolveApiBaseUrl() {
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

  final configured =
      (Platform.environment['BIM_API_URL'] ??
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
  late final FlutterSecureStorage _storage;
  late final http.Client _httpClient;

  String? _accessToken;
  String? _refreshToken;
  bool _isRefreshing = false;
  final List<Completer<String>> _refreshCompleters = [];

  factory ApiClient() => _instance;

  ApiClient._internal() {
    _storage = const FlutterSecureStorage();
    _httpClient = http.Client();
  }

  /// Initialize the client - loads stored tokens
  Future<void> init() async {
    try {
      _accessToken = await _storage.read(key: _accessTokenKey);
      _refreshToken = await _storage.read(key: _refreshTokenKey);
    } catch (e) {
      // Ignore storage errors on init
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

    try {
      await Future.wait([
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _refreshTokenKey, value: refreshToken),
      ]);
    } catch (e) {
      throw ApiException('Failed to store tokens: $e');
    }
  }

  /// Clear tokens on logout
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;

    try {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
      ]);
    } catch (e) {
      throw ApiException('Failed to clear tokens: $e');
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
        await _storage.write(key: _accessTokenKey, value: newAccessToken);

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
