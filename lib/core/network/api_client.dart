import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:voice_social_app/core/network/api_exception.dart';

class ApiResponse {
  const ApiResponse({
    required this.code,
    required this.message,
    required this.data,
  });

  final int code;
  final String message;
  final Object? data;

  bool get isSuccess => code == 200;
}

typedef AuthorizationProvider = String? Function();
typedef RequestHeadersProvider = Map<String, String> Function();
typedef UnauthorizedRecovery = Future<bool> Function();

class ApiClient {
  ApiClient({
    required Uri baseUri,
    required this.clientType,
    required this.clientInnerVersion,
    required AuthorizationProvider authorizationProvider,
    RequestHeadersProvider? requestHeadersProvider,
    UnauthorizedRecovery? unauthorizedRecovery,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.maximumResponseBytes = 2 * 1024 * 1024,
  }) : _baseUri = baseUri,
       _authorizationProvider = authorizationProvider,
       _requestHeadersProvider = requestHeadersProvider,
       _unauthorizedRecovery = unauthorizedRecovery,
       _httpClient = httpClient ?? HttpClient();

  final Uri _baseUri;
  final String clientType;
  final String clientInnerVersion;
  final AuthorizationProvider _authorizationProvider;
  final RequestHeadersProvider? _requestHeadersProvider;
  final HttpClient _httpClient;
  final Duration timeout;
  final int maximumResponseBytes;
  UnauthorizedRecovery? _unauthorizedRecovery;

  void setUnauthorizedRecovery(UnauthorizedRecovery? recovery) {
    _unauthorizedRecovery = recovery;
  }

  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) => _request(
    method: 'GET',
    path: path,
    query: query,
    headers: headers,
    authenticated: authenticated,
  );

  Future<ApiResponse> put(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) => _request(
    method: 'PUT',
    path: path,
    query: query,
    headers: headers,
    body: body,
    authenticated: authenticated,
  );

  Future<ApiResponse> patch(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) => _request(
    method: 'PATCH',
    path: path,
    query: query,
    headers: headers,
    body: body,
    authenticated: authenticated,
  );

  Future<ApiResponse> post(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) => _request(
    method: 'POST',
    path: path,
    query: query,
    headers: headers,
    body: body,
    authenticated: authenticated,
  );

  Future<ApiResponse> delete(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) => _request(
    method: 'DELETE',
    path: path,
    query: query,
    headers: headers,
    body: body,
    authenticated: authenticated,
  );

  Future<ApiResponse> _request({
    required String method,
    required String path,
    required bool authenticated,
    Map<String, String>? query,
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool allowUnauthorizedRecovery = true,
  }) async {
    if (!_baseUri.hasScheme || _baseUri.host.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '后端地址尚未配置',
      );
    }

    final Uri uri = _baseUri
        .resolve(path)
        .replace(
          queryParameters: query == null || query.isEmpty ? null : query,
        );
    try {
      final HttpClientRequest request = await _httpClient
          .openUrl(method, uri)
          .timeout(timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
        ..set('Client-Type', clientType)
        ..set('Client-Inner-Version', clientInnerVersion)
        ..set('X-Request-Id', _newRequestId());

      _applyHeaders(request, _requestHeadersProvider?.call());
      _applyHeaders(request, headers);

      if (authenticated) {
        final String? authorization = _authorizationProvider();
        if (authorization == null || authorization.isEmpty) {
          throw const ApiException(
            kind: ApiFailureKind.unauthorized,
            code: 401,
            httpStatus: 401,
            message: '登录会话已失效',
          );
        }
        request.headers.set(HttpHeaders.authorizationHeader, authorization);
      }

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      final String responseBody = await _readResponseBody(response);
      if (responseBody.trim().isEmpty) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          code: response.statusCode,
          httpStatus: response.statusCode,
          message: '服务端返回空响应',
        );
      }

      final Object? decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, Object?>) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          code: response.statusCode,
          httpStatus: response.statusCode,
          message: '服务端响应结构无法识别',
        );
      }
      final int code = _asInt(decoded['code']) ?? response.statusCode;
      final String message = decoded['message']?.toString() ?? '请求失败';
      final ApiResponse apiResponse = ApiResponse(
        code: code,
        message: message,
        data: decoded['data'],
      );
      final bool httpSuccess =
          response.statusCode >= 200 && response.statusCode < 300;
      if (httpSuccess && apiResponse.isSuccess) {
        return apiResponse;
      }

      final ApiFailureKind kind = _failureKind(
        code: code,
        httpStatus: response.statusCode,
      );
      if (authenticated &&
          allowUnauthorizedRecovery &&
          kind == ApiFailureKind.unauthorized &&
          _unauthorizedRecovery != null) {
        final bool recovered = await _unauthorizedRecovery!.call();
        if (recovered) {
          return _request(
            method: method,
            path: path,
            authenticated: authenticated,
            query: query,
            headers: headers,
            body: body,
            allowUnauthorizedRecovery: false,
          );
        }
      }

      throw ApiException(
        kind: kind,
        code: code,
        httpStatus: response.statusCode,
        message: message,
      );
    } on TimeoutException catch (error) {
      throw ApiException(
        kind: ApiFailureKind.timeout,
        message: '请求超时，请检查网络后重试',
        cause: error,
      );
    } on SocketException catch (error) {
      throw ApiException(
        kind: ApiFailureKind.network,
        message: '网络连接失败，请稍后重试',
        cause: error,
      );
    } on ApiException {
      rethrow;
    } on FormatException catch (error) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '服务端返回了无法解析的数据',
        cause: error,
      );
    } on HttpException catch (error) {
      throw ApiException(
        kind: ApiFailureKind.network,
        message: '网络请求失败',
        cause: error,
      );
    }
  }

  Future<String> _readResponseBody(HttpClientResponse response) async {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    int total = 0;
    await for (final List<int> chunk in response.timeout(timeout)) {
      total += chunk.length;
      if (total > maximumResponseBytes) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          httpStatus: response.statusCode,
          message: '服务端响应超过允许大小',
        );
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }

  static void _applyHeaders(
    HttpClientRequest request,
    Map<String, String>? headers,
  ) {
    if (headers == null || headers.isEmpty) {
      return;
    }
    for (final MapEntry<String, String> entry in headers.entries) {
      final String name = entry.key.trim();
      final String value = entry.value.trim();
      if (name.isNotEmpty && value.isNotEmpty) {
        request.headers.set(name, value);
      }
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static ApiFailureKind _failureKind({
    required int code,
    required int httpStatus,
  }) {
    if (httpStatus == 401 || (code >= 40100 && code < 40200)) {
      return ApiFailureKind.unauthorized;
    }
    if (httpStatus == 403 || (code >= 40300 && code < 40400)) {
      return ApiFailureKind.forbidden;
    }
    if (httpStatus == 409 || (code >= 40900 && code < 41000)) {
      return ApiFailureKind.conflict;
    }
    if (httpStatus >= 500 || code >= 50000) {
      return ApiFailureKind.server;
    }
    if (httpStatus == 400 ||
        httpStatus == 404 ||
        httpStatus == 410 ||
        httpStatus == 422 ||
        (code >= 40000 && code < 50000)) {
      return ApiFailureKind.validation;
    }
    if (code >= 10000) {
      return ApiFailureKind.business;
    }
    return ApiFailureKind.business;
  }

  static String _newRequestId() {
    final Random random = Random.secure();
    final String randomPart = List<String>.generate(
      2,
      (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    ).join();
    return 'flutter-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
  }
}
