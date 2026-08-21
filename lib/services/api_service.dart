import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'storage_service.dart';

/// HTTP client wrapping Dio.
///
/// - Automatically injects the JWT access token into every request.
/// - On 401, attempts a token refresh and retries the original request once.
/// - Maps backend errors to human-readable messages.
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ),
    );
  }

  // ── Interceptors ──────────────────────────────────────────────────────────

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await StorageService.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Attempt token refresh on 401
    if (err.response?.statusCode == 401) {
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        // Retry original request with new token
        final options = err.requestOptions;
        final newToken = await StorageService.getAccessToken();
        options.headers['Authorization'] = 'Bearer $newToken';
        try {
          final retryResp = await _dio.fetch(options);
          handler.resolve(retryResp);
          return;
        } catch (_) {
          // Refresh retry failed — fall through to error
        }
      }
    }
    handler.next(err);
  }

  Future<bool> _tryRefreshToken() async {
    final refreshToken = await StorageService.getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final resp = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {}), // no auth header to avoid recursion
      );
      await StorageService.saveTokens(
        accessToken: resp.data['access_token'] as String,
        refreshToken: resp.data['refresh_token'] as String,
      );
      return true;
    } catch (_) {
      await StorageService.clearTokens();
      return false;
    }
  }

  // ── HTTP verbs ─────────────────────────────────────────────────────────────

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  Future<Response<T>> post<T>(String path, {Object? data}) {
    return _dio.post<T>(path, data: data);
  }

  Future<Response<T>> patch<T>(String path, {Object? data}) {
    return _dio.patch<T>(path, data: data);
  }

  Future<Response<T>> delete<T>(String path) {
    return _dio.delete<T>(path);
  }

  // ── Error mapping ──────────────────────────────────────────────────────────

  static String friendlyError(Object err) {
    if (err is DioException) {
      final status = err.response?.statusCode;
      final detail = err.response?.data is Map
          ? (err.response!.data as Map)['detail'] ?? ''
          : '';
      if (status == 401) return 'Session expired. Please log in again.';
      if (status == 403) return 'Access denied.';
      if (status == 404) return detail.toString().isNotEmpty ? detail.toString() : 'Not found.';
      if (status == 409) return detail.toString().isNotEmpty ? detail.toString() : 'Conflict error.';
      if (status == 422) return 'Invalid input. Please check your details.';
      if (status != null && status >= 500) return 'Server error. Please try again later.';
      if (err.type == DioExceptionType.connectionTimeout ||
          err.type == DioExceptionType.receiveTimeout) {
        return 'Connection timed out. Check your network.';
      }
      if (err.type == DioExceptionType.unknown) {
        return 'Network unavailable. Is the server running?';
      }
    }
    return 'An unexpected error occurred.';
  }
}
