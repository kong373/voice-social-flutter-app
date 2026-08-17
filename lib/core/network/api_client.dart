import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class ApiClient {
  ApiClient({
    required Uri baseUri,
    required this.clientType,
    required this.clientInnerVersion,
    required AuthorizationProvider authorizationProvider,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 15),
  })  : _baseUri = baseUri,
        _authorizationProvider = authorizationProvider,
        _httpClient = httpClient ?? HttpClient();

  final Uri _baseUri;
  final String clientType;
  final String clientInnerVersion;
  final AuthorizationProvider _authorizationProvider;
  final HttpClient _httpClient;
  final Duration timeout;

  Future<ApiResponse> get(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) =>
      _request(
        method: 'GET',
        path: path,
        query: query,
        authenticated: authenticated,
      );

  Future<ApiResponse> put(
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) =>
      _request(
        method: 'PUT',
        path: path,
        query: query,
        body: body,
        authenticated: authenticated,
      );

  Future<ApiResponse> patch(
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) =>
      _request(
        method: 'PATCH',
        path: path,
        query: query,
        body: body,
        authenticated: authenticated,
      );

  Future<ApiResponse> post(
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) =>
      _request(
        method: 'POST',
        path: path,
        query: query,
        body: body,
        authenticated: authenticated,
      );

  Future<ApiResponse> _request({
    required String method,
    required String path,
    required bool authenticated,
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    if (!_baseUri.hasScheme || _baseUri.host.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '后端地址尚未配置',
      );
    }

    final Uri uri = _baseUri.resolve(path).replace(
          queryParameters: query == null || query.isEmpty ? null : query,
        );
    try {
      final HttpClientRequest request =
          await _httpClient.openUrl(method, uri).timeout(timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
        ..set('Client-Type', clientType)
        ..set('Client-Inner-Version', clientInnerVersion);

      if (authenticated) {
        final String? authorization = _authorizationProvider();
        if (authorization == null || authorization.isEmpty) {
          throw const ApiException(
            kind: ApiFailureKind.unauthorized,
            code: 401,
            message: '登录会话已失效',
          );
        }
        request.headers.set(HttpHeaders.authorizationHeader, authorization);
      }

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final HttpClientResponse response = await request.close().timeout(timeout);
      final String responseBody = await utf8.decoder.bind(response).join();
      if (responseBody.trim().isEmpty) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          code: response.statusCode,
          message: '服务端返回空响应',
        );
      }

      final Object? decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, Object?>) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          code: response.statusCode,
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
      if (!apiResponse.isSuccess) {
        throw ApiException(
          kind: _failureKind(code),
          code: code,
          message: message,
        );
      }
      return apiResponse;
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

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static ApiFailureKind _failureKind(int code) {
    if (code == 401) {
      return ApiFailureKind.unauthorized;
    }
    if (code == 403) {
      return ApiFailureKind.forbidden;
    }
    if (code == 404) {
      return ApiFailureKind.validation;
    }
    if (code >= 10000) {
      return ApiFailureKind.business;
    }
    if (code >= 500) {
      return ApiFailureKind.server;
    }
    return ApiFailureKind.business;
  }
}
