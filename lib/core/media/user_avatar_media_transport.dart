part of '../network/api_client.dart';

/// Compact USER_AVATAR descriptors have no MIME/length. Read the authoritative
/// content response without inventing a MediaReference, purpose or public URL.
extension UserAvatarMediaTransport on ApiClient {
  Future<Uint8List> readUserAvatarContent({
    required String assetId,
    required int version,
    required MediaIdentityScope identity,
  }) async {
    requireMediaId(assetId);
    if (version < 0) throw mediaProtocol();
    if (!const {'http', 'https'}.contains(_baseUri.scheme) ||
        _baseUri.host.isEmpty ||
        _baseUri.userInfo.isNotEmpty ||
        _baseUri.hasQuery ||
        _baseUri.hasFragment) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '头像读取地址尚未配置',
      );
    }
    return _readUserAvatar(assetId, identity, recover: true);
  }

  Future<Uint8List> _readUserAvatar(
    String assetId,
    MediaIdentityScope identity, {
    required bool recover,
  }) async {
    identity.check();
    final token = _authorizationProvider();
    if (token == null || token.isEmpty) throw MediaIdentityScope.invalid;
    final recoveryGeneration = _unauthorizedRecoveryGeneration;
    final buffer = BytesBuilder(copy: true);
    HttpClientRequest? request;
    void Function()? unregister;
    var abandoned = false;
    try {
      final opening = _httpClient
          .openUrl(
            'GET',
            _baseUri.resolve('/app-api/media/v1/assets/$assetId/content'),
          )
          .then((value) {
            if (abandoned || !identity.isCurrent) value.abort();
            return value;
          });
      final active = await identity.wait(opening.timeout(timeout));
      request = active;
      unregister = identity.onCancel(active.abort);
      active.followRedirects = false;
      active.maxRedirects = 0;
      // No arbitrary provider headers, cookie or registration capability.
      final headers = _requestHeadersProvider?.call();
      identity.check();
      final clientId = headers?['Client-Id'];
      if (clientId != null) active.headers.set('Client-Id', clientId);
      active.headers
        ..removeAll(HttpHeaders.cookieHeader)
        ..removeAll(HttpHeaders.contentEncodingHeader)
        ..set(HttpHeaders.authorizationHeader, token)
        ..set(HttpHeaders.acceptHeader, 'image/jpeg, image/png, image/webp')
        ..set(HttpHeaders.acceptEncodingHeader, 'identity')
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('Client-Type', clientType)
        ..set('Client-Inner-Version', clientInnerVersion)
        ..set('X-Request-Id', ApiClient._newRequestId());
      identity.check();
      final response = await identity.wait(active.close().timeout(timeout));
      if (response.statusCode == 401 && recover) {
        active.abort();
        final refreshed =
            _unauthorizedRecoveryGeneration > recoveryGeneration ||
            (_unauthorizedRecovery != null &&
                await identity.wait(_recoverUnauthorized().timeout(timeout)));
        identity.check();
        if (refreshed)
          return await _readUserAvatar(assetId, identity, recover: false);
      }
      if (response.statusCode != 200) {
        throw ApiException(
          kind: response.statusCode == 401
              ? ApiFailureKind.unauthorized
              : response.statusCode == 403
              ? ApiFailureKind.forbidden
              : ApiFailureKind.protocol,
          httpStatus: response.statusCode,
          message: '头像当前不可读取',
        );
      }
      final cache =
          response.headers
              .value(HttpHeaders.cacheControlHeader)
              ?.toLowerCase()
              .split(',')
              .map((s) => s.trim())
              .toSet() ??
          {};
      final type = response.headers.value(HttpHeaders.contentTypeHeader);
      final length = response.contentLength;
      if (!cache.containsAll({'private', 'no-store'}) ||
          cache.contains('public') ||
          response.headers.value(HttpHeaders.contentEncodingHeader) != null ||
          !const {'image/jpeg', 'image/png', 'image/webp'}.contains(type) ||
          length == 0 ||
          length < -1 ||
          length > 10000000)
        throw mediaProtocol();
      final total = await _mediaChunks(
        response,
        identity,
        10000000,
        (chunk) async => buffer.add(chunk),
        exactBytes: length >= 0 ? length : null,
      );
      identity.check();
      if (total == 0) throw mediaProtocol();
      return buffer.takeBytes();
    } on TimeoutException {
      identity.check();
      throw const ApiException(kind: ApiFailureKind.timeout, message: '头像读取超时');
    } on SocketException {
      identity.check();
      throw const ApiException(kind: ApiFailureKind.network, message: '头像读取中断');
    } on HttpException {
      identity.check();
      throw const ApiException(kind: ApiFailureKind.network, message: '头像读取中断');
    } finally {
      abandoned = true;
      unregister?.call();
      request?.abort();
      buffer.clear();
    }
  }
}
