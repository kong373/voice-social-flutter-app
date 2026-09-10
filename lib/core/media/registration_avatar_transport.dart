part of '../network/api_client.dart';

enum RegistrationAvatarAction { allocate, status, upload, complete }

/// Independent pre-registration capability. No App token or principal enters
/// this scope. The host supplies its immutable challenge cancellation fence.
class RegistrationAvatarRequestScope {
  const RegistrationAvatarRequestScope({
    required this.clientId,
    required this.deviceId,
    required this.requestId,
    required this.capability,
    required this.check,
    required this.wait,
    required this.onCancel,
  });
  final String clientId, deviceId, requestId, capability;
  final void Function() check;
  final Future<T> Function<T>(Future<T>) wait;
  final void Function() Function(void Function()) onCancel;
}

const _registrationAvatarProtocol = ApiException(
  kind: ApiFailureKind.protocol,
  message: '注册头像请求或响应无效，请检查上传状态',
);

extension RegistrationAvatarApiTransport on ApiClient {
  Future<ApiResponse> registrationAvatarExchange({
    required RegistrationAvatarAction action,
    required RegistrationAvatarRequestScope scope,
    String? phone,
    String? smsCode,
    String? challengeId,
    String? assetId,
    int? expectedVersion,
    int? bytes,
    Stream<List<int>>? content,
  }) async {
    scope.check();
    bool uuid(String? value) =>
        value != null &&
        value.length == 36 &&
        RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(value);
    bool header(String value) =>
        value.isNotEmpty &&
        value.length <= 160 &&
        value.codeUnits.every((unit) => unit >= 0x21 && unit <= 0x7e);
    if (!header(scope.deviceId) ||
        !header(scope.clientId) ||
        scope.requestId.isEmpty ||
        scope.requestId.length > 80 ||
        RegExp(r'[^A-Za-z0-9._:-]').hasMatch(scope.requestId) ||
        scope.capability.length != 43 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(scope.capability))
      throw _registrationAvatarProtocol;
    final List<int> decodedCap;
    try {
      decodedCap = base64Url.decode('${scope.capability}=');
    } on FormatException {
      throw _registrationAvatarProtocol;
    }
    if (decodedCap.length != 32 ||
        base64Url.encode(decodedCap).replaceAll('=', '') != scope.capability) {
      throw _registrationAvatarProtocol;
    }
    if (!const {'http', 'https'}.contains(_baseUri.scheme) ||
        _baseUri.host.isEmpty ||
        _baseUri.userInfo.isNotEmpty ||
        _baseUri.hasQuery ||
        _baseUri.hasFragment) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '注册上传后端地址无效',
      );
    }
    String path = '/app-register-api/media/v1/avatar-uploads';
    String method;
    Map<String, Object?>? body;
    if (action == RegistrationAvatarAction.allocate) {
      if (phone == null ||
          phone.length != 11 ||
          !RegExp(r'^1[0-9]{10}$').hasMatch(phone) ||
          smsCode == null ||
          smsCode.length != 6 ||
          !RegExp(r'^[0-9]{6}$').hasMatch(smsCode) ||
          !uuid(challengeId) ||
          assetId != null ||
          expectedVersion != null ||
          bytes != null ||
          content != null)
        throw _registrationAvatarProtocol;
      method = 'POST';
      body = {
        'phone': phone,
        'smsCode': smsCode,
        'challengeId': challengeId,
        'deviceId': scope.deviceId,
      };
    } else {
      if (!uuid(assetId) ||
          phone != null ||
          smsCode != null ||
          challengeId != null)
        throw _registrationAvatarProtocol;
      path += '/$assetId';
      if (action == RegistrationAvatarAction.status) {
        if (expectedVersion != null || bytes != null || content != null)
          throw _registrationAvatarProtocol;
        method = 'GET';
      } else {
        if (expectedVersion == null ||
            expectedVersion < 0 ||
            expectedVersion > 9007199254740991)
          throw _registrationAvatarProtocol;
        if (action == RegistrationAvatarAction.complete) {
          if (bytes != null || content != null)
            throw _registrationAvatarProtocol;
          method = 'POST';
          path += '/complete';
          body = {'expectedVersion': expectedVersion};
        } else {
          if (bytes == null ||
              bytes <= 0 ||
              bytes > 10000000 ||
              content == null)
            throw _registrationAvatarProtocol;
          method = 'PUT';
          path += '/content?expectedVersion=$expectedVersion';
        }
      }
    }
    HttpClientRequest? request;
    void Function()? unregister;
    var abandoned = false;
    try {
      final opening = _httpClient.openUrl(method, _baseUri.resolve(path)).then((
        value,
      ) {
        try {
          scope.check();
          if (abandoned) value.abort();
        } catch (_) {
          value.abort();
        }
        return value;
      });
      final active = await scope.wait(opening.timeout(timeout));
      request = active;
      unregister = scope.onCancel(active.abort);
      active.followRedirects = false;
      active.maxRedirects = 0;
      // Deliberately never read either global headers or Authorization. A
      // stale App session must not leak into this anonymous capability flow.
      active.headers
        ..removeAll(HttpHeaders.authorizationHeader)
        ..removeAll(HttpHeaders.contentEncodingHeader)
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set(
          HttpHeaders.contentTypeHeader,
          content == null
              ? 'application/json; charset=utf-8'
              : 'application/octet-stream',
        )
        ..set('Client-Id', scope.clientId)
        ..set('X-Device-Id', scope.deviceId)
        ..set('X-Request-Id', scope.requestId)
        ..set('X-Registration-Avatar-Capability', scope.capability);
      scope.check();
      if (content != null) {
        active.contentLength = bytes!;
        final total = await _registrationAvatarChunks(content, scope, bytes, (
          chunk,
        ) async {
          active.add(chunk);
          await scope.wait(active.flush().timeout(timeout));
        }, timeout);
        if (total != bytes) throw _registrationAvatarProtocol;
      } else if (body != null) {
        active.write(jsonEncode(body));
      }
      scope.check();
      final response = await scope.wait(active.close().timeout(timeout));
      if (response.statusCode >= 300 && response.statusCode < 400)
        throw _registrationAvatarProtocol;
      final buffer = BytesBuilder(copy: false);
      await _registrationAvatarChunks(response, scope, maximumResponseBytes, (
        chunk,
      ) async {
        buffer.add(chunk);
      }, timeout);
      final value = jsonDecode(utf8.decode(buffer.takeBytes()));
      scope.check();
      if (value is! Map<String, Object?> ||
          value['code'] is! int ||
          value['message'] is! String ||
          !value.containsKey('data'))
        throw _registrationAvatarProtocol;
      final code = value['code']! as int;
      if (response.statusCode == 200 && code == 200) {
        return ApiResponse(code: code, message: 'OK', data: value['data']);
      }
      // Do not surface an untrusted server message that may echo a capability.
      throw ApiException(
        kind: ApiClient._failureKind(
          code: code,
          httpStatus: response.statusCode,
        ),
        code: code,
        httpStatus: response.statusCode,
        message: '注册头像操作未完成，请检查上传状态',
      );
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        kind: ApiFailureKind.timeout,
        message: '注册头像请求超时，请检查上传状态',
      );
    } on FormatException {
      throw _registrationAvatarProtocol;
    } on IOException {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: '注册头像网络中断，请检查上传状态',
      );
    } finally {
      abandoned = true;
      unregister?.call();
      request?.abort();
    }
  }
}

Future<int> _registrationAvatarChunks(
  Stream<List<int>> source,
  RegistrationAvatarRequestScope scope,
  int maximum,
  Future<void> Function(List<int>) sink,
  Duration timeout,
) async {
  final iterator = StreamIterator<List<int>>(source);
  final unregister = scope.onCancel(() {
    unawaited(iterator.cancel());
  });
  var total = 0;
  try {
    while (await scope.wait(iterator.moveNext().timeout(timeout))) {
      scope.check();
      final chunk = iterator.current;
      total += chunk.length;
      if (total > maximum) throw _registrationAvatarProtocol;
      await scope.wait(sink(chunk));
    }
    scope.check();
    return total;
  } finally {
    unregister();
    await iterator.cancel();
  }
}
