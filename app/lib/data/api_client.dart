import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'models.dart';
import 'token_store.dart';

/// An error returned by the API (`{"error": {"code", "message"}}`) or the network.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status});

  final String code;
  final String message;
  final int? status;

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;

  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['error'] is Map) {
        final e = data['error'] as Map;
        return ApiException(e['code'] as String? ?? 'error', e['message'] as String? ?? 'Something went wrong',
            status: error.response?.statusCode);
      }
      if (error.type == DioExceptionType.connectionError || error.type == DioExceptionType.connectionTimeout) {
        return const ApiException('network', 'Could not reach Cholo. Check your connection.');
      }
      return ApiException('http_${error.response?.statusCode ?? 0}', 'Something went wrong',
          status: error.response?.statusCode);
    }
    return ApiException('unknown', error.toString());
  }
}

/// Low-level HTTP client: attaches the access token, refreshes it once on a 401
/// and converts failures into [ApiException].
class ApiClient {
  ApiClient({required String baseUrl, required this.tokens, Dio? dio, this.onSessionExpired})
      : dio = dio ?? Dio() {
    this.dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 20)
      ..contentType = Headers.jsonContentType;
    this.dio.interceptors.add(QueuedInterceptorsWrapper(
          onRequest: (options, handler) async {
            if (options.extra['auth'] != false) {
              final t = await tokens.read();
              if (t != null) options.headers['Authorization'] = 'Bearer ${t.access}';
            }
            handler.next(options);
          },
          onError: (err, handler) async {
            final opts = err.requestOptions;
            if (err.response?.statusCode != 401 || opts.extra['auth'] == false || opts.extra['retried'] == true) {
              return handler.next(err);
            }
            final refreshed = await _refresh();
            if (!refreshed) {
              onSessionExpired?.call();
              return handler.next(err);
            }
            try {
              opts.extra['retried'] = true;
              final t = await tokens.read();
              opts.headers['Authorization'] = 'Bearer ${t!.access}';
              handler.resolve(await this.dio.fetch<dynamic>(opts));
            } on DioException catch (e) {
              handler.next(e);
            }
          },
        ));
  }

  final Dio dio;
  final TokenStore tokens;
  final void Function()? onSessionExpired;

  /// Refresh calls bypass the queued interceptor, which is blocked while it waits on them.
  late final Dio _refreshDio = Dio(dio.options.copyWith())..httpClientAdapter = dio.httpClientAdapter;

  /// Refreshes the access token if it expires within [margin]; used before
  /// opening WebSockets, which can't go through the 401 retry above.
  Future<void> ensureFreshToken({Duration margin = const Duration(seconds: 60)}) async {
    final t = await tokens.read();
    if (t == null) return;
    final exp = accessTokenExpiry(t.access);
    if (exp == null || exp.isBefore(DateTime.now().add(margin))) await _refresh();
  }

  Future<bool> _refresh() async {
    final t = await tokens.read();
    if (t == null) return false;
    try {
      final res = await _refreshDio.post<Json>('/v1/auth/refresh',
          data: {'refresh_token': t.refresh}, options: Options(extra: {'auth': false}));
      await tokens.write(Tokens(access: res.data!['access_token'] as String, refresh: res.data!['refresh_token'] as String));
      return true;
    } catch (_) {
      await tokens.clear();
      return false;
    }
  }

  Future<Json> get(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get<Json>(path, queryParameters: query));

  Future<Json> post(String path, [Object? body, bool auth = true]) =>
      _wrap(() => dio.post<Json>(path, data: body ?? const {}, options: Options(extra: {'auth': auth})));

  Future<Json> patch(String path, Object body) => _wrap(() => dio.patch<Json>(path, data: body));

  Future<Json> delete(String path) => _wrap(() => dio.delete<Json>(path));

  Future<Json> _wrap(Future<Response<Json>> Function() call) async {
    try {
      final res = await call();
      return res.data ?? const {};
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

/// Reads the `exp` claim of a JWT without verifying it; null if unreadable.
DateTime? accessTokenExpiry(String jwt) {
  try {
    final payload = jwt.split('.')[1];
    final json = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload)))) as Map;
    return DateTime.fromMillisecondsSinceEpoch((json['exp'] as num).toInt() * 1000);
  } catch (_) {
    return null;
  }
}
