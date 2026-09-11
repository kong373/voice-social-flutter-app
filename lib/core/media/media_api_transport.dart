part of '../network/api_client.dart';

enum MediaAssetAction { allocate, status, complete, revoke }

/// S13-only transport. Kept in this library to share the existing HTTP client,
/// token provider and refresh singleflight, without exposing tokens or changing
/// the general JSON API. No caller-supplied URL or redirect is accepted.
extension MediaApiTransport on ApiClient {
  Future<ApiResponse> mediaAssetJson({
    required MediaAssetAction action,
    required MediaIdentityScope identity,
    String? assetId,
    MediaPurpose? purpose,
    int? expectedVersion,
    String? requestId,
  }) {
    String path = '/app-api/media/v1/assets';
    String method;
    Map<String, Object?>? body;
    switch (action) {
      case MediaAssetAction.allocate:
        if (purpose == null ||
            purpose == MediaPurpose.avatar ||
            assetId != null ||
            expectedVersion != null ||
            requestId == null ||
            !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(requestId))
          throw mediaProtocol();
        method = 'POST';
        body = {'purpose': purpose.wire};
      case MediaAssetAction.status:
      case MediaAssetAction.revoke:
        if (purpose != null || expectedVersion != null) throw mediaProtocol();
        path += '/${requireMediaId(assetId)}';
        method = action == MediaAssetAction.status ? 'GET' : 'DELETE';
      case MediaAssetAction.complete:
        if (purpose != null || expectedVersion == null || expectedVersion < 0)
          throw mediaProtocol();
        path += '/${requireMediaId(assetId)}/complete';
        method = 'POST';
        body = {'expectedVersion': expectedVersion};
    }
    return _mediaExchange(
      method: method,
      path: path,
      identity: identity,
      body: body,
      requestId: requestId ?? ApiClient._newRequestId(),
    );
  }

  Future<ApiResponse> putMediaAssetContent({
    required String assetId,
    required int expectedVersion,
    required MediaPurpose purpose,
    required int bytes,
    required Stream<List<int>> content,
    required MediaIdentityScope identity,
  }) {
    if (purpose == MediaPurpose.avatar ||
        expectedVersion != 0 ||
        bytes <= 0 ||
        bytes > purpose.maximumBytes)
      throw mediaProtocol();
    return _mediaExchange(
      method: 'PUT',
      path:
          '/app-api/media/v1/assets/${requireMediaId(assetId)}/content?expectedVersion=$expectedVersion',
      identity: identity,
      requestId: ApiClient._newRequestId(),
      upload: content,
      uploadBytes: bytes,
      maximumBytes: purpose.maximumBytes,
    );
  }

  /// Delivers bounded chunks to a caller-owned temporary sink, never a 100MB
  /// String/JSON/BytesBuilder. The sink must discard partial data on any error.
  Future<void> readMediaAssetContent({
    required MediaReference media,
    required MediaIdentityScope identity,
    required Future<void> Function(List<int>) onChunk,
  }) async {
    await _mediaExchange(
      method: 'GET',
      path: '/app-api/media/v1/assets/${requireMediaId(media.assetId)}/content',
      identity: identity,
      requestId: ApiClient._newRequestId(),
      maximumBytes: media.purpose.maximumBytes,
      download: onChunk,
      expectedContent: media,
    );
    identity.check();
  }

  Future<ApiResponse> _mediaExchange({
    required String method,
    required String path,
    required MediaIdentityScope identity,
    required String? requestId,
    Map<String, Object?>? body,
    Stream<List<int>>? upload,
    int? uploadBytes,
    int maximumBytes = 100000000,
    Future<void> Function(List<int>)? download,
    MediaReference? expectedContent,
    bool recover = true,
  }) async {
    identity.check();
    if (!const {'http', 'https'}.contains(_baseUri.scheme) ||
        _baseUri.host.isEmpty ||
        _baseUri.userInfo.isNotEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '后端地址尚未配置',
      );
    }
    final token = _authorizationProvider();
    if (token == null || token.isEmpty) throw MediaIdentityScope.invalid;
    final recoveryGeneration = _unauthorizedRecoveryGeneration;
    HttpClientRequest? request;
    void Function()? unregister;
    bool abandoned = false;
    try {
      final opening = _httpClient.openUrl(method, _baseUri.resolve(path)).then((
        value,
      ) {
        if (abandoned || !identity.isCurrent) value.abort();
        return value;
      });
      final activeRequest = await identity.wait<HttpClientRequest>(
        opening.timeout(timeout),
      );
      request = activeRequest;
      unregister = identity.onCancel(activeRequest.abort);
      activeRequest.followRedirects = false;
      activeRequest.maxRedirects = 0;
      ApiClient._applyHeaders(activeRequest, _requestHeadersProvider?.call());
      activeRequest.headers
        ..removeAll(HttpHeaders.contentEncodingHeader)
        ..removeAll('X-Request-Id')
        ..set(HttpHeaders.authorizationHeader, token)
        ..set(
          HttpHeaders.acceptHeader,
          download == null ? 'application/json' : expectedContent!.mediaType,
        )
        ..set(
          HttpHeaders.contentTypeHeader,
          upload == null
              ? 'application/json; charset=utf-8'
              : 'application/octet-stream',
        )
        ..set('Client-Type', clientType)
        ..set('Client-Inner-Version', clientInnerVersion);
      if (requestId != null) {
        activeRequest.headers.set('X-Request-Id', requestId);
      }
      identity.check();
      if (upload != null) {
        activeRequest.contentLength = uploadBytes!;
        final total = await _mediaChunks(upload, identity, maximumBytes, (
          chunk,
        ) async {
          activeRequest.add(chunk);
          await identity.wait(activeRequest.flush().timeout(timeout));
        }, exactBytes: uploadBytes);
        identity.check();
        if (total != uploadBytes) throw mediaProtocol();
      } else if (body != null) {
        activeRequest.write(jsonEncode(body));
      }
      final response = await identity.wait(
        activeRequest.close().timeout(timeout),
      );
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '受控媒体请求拒绝跳转',
        );
      }
      final httpSuccess = response.statusCode == 200;
      if (httpSuccess && download != null) {
        final media = expectedContent!;
        final encoding = response.headers.value(
          HttpHeaders.contentEncodingHeader,
        );
        final type = response.headers.value(HttpHeaders.contentTypeHeader);
        if (encoding != null ||
            type != media.mediaType ||
            (response.contentLength >= 0 &&
                response.contentLength != media.bytes))
          throw mediaProtocol();
        await _mediaChunks(
          response,
          identity,
          maximumBytes,
          download,
          exactBytes: media.bytes,
        );
        identity.check();
        return const ApiResponse(code: 200, message: 'OK', data: null);
      }
      // Metadata and error bodies keep the existing JSON bound, independently
      // of the much larger binary limit.
      final buffer = BytesBuilder(copy: false);
      await _mediaChunks(response, identity, maximumResponseBytes, (
        chunk,
      ) async {
        buffer.add(chunk);
      });
      identity.check();
      final decoded = jsonDecode(utf8.decode(buffer.takeBytes()));
      if (decoded is! Map<String, Object?> ||
          decoded['code'] is! int ||
          decoded['message'] is! String ||
          !decoded.containsKey('data'))
        throw mediaProtocol();
      final code = decoded['code']! as int;
      if (httpSuccess && code == 200) {
        return ApiResponse(
          code: code,
          message: decoded['message']! as String,
          data: decoded['data'],
          responseHeaders: ApiClient._responseHeaders(response),
        );
      }
      final kind = ApiClient._failureKind(
        code: code,
        httpStatus: response.statusCode,
      );
      if (recover && kind == ApiFailureKind.unauthorized) {
        identity.check();
        final refreshed =
            _unauthorizedRecoveryGeneration > recoveryGeneration ||
            (_unauthorizedRecovery != null &&
                await identity.wait(_recoverUnauthorized().timeout(timeout)));
        identity.check();
        // A PUT may have acquired UPLOADING even when its response is lost or
        // auth expires during processing. Refresh never replays upload bytes;
        // callers recover explicitly with status/complete.
        if (refreshed && upload == null) {
          return await _mediaExchange(
            method: method,
            path: path,
            identity: identity,
            requestId: requestId,
            body: body,
            maximumBytes: maximumBytes,
            download: download,
            expectedContent: expectedContent,
            recover: false,
          );
        }
      }
      throw ApiException(
        kind: kind,
        code: code,
        httpStatus: response.statusCode,
        message: '媒体请求未完成，请按原资产查询状态',
      );
    } on TimeoutException {
      throw const ApiException(
        kind: ApiFailureKind.timeout,
        message: '媒体请求超时，请查询原资产状态',
      );
    } on SocketException {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: '媒体连接中断，请查询原资产状态',
      );
    } on HttpException {
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: '媒体传输中断，请查询原资产状态',
      );
    } on FormatException {
      throw mediaProtocol();
    } finally {
      abandoned = true;
      unregister?.call();
      request?.abort();
    }
  }

  Future<int> _mediaChunks(
    Stream<List<int>> stream,
    MediaIdentityScope identity,
    int maximum,
    Future<void> Function(List<int>) consume, {
    int? exactBytes,
  }) async {
    final iterator = StreamIterator<List<int>>(stream);
    final unregister = identity.onCancel(() {
      unawaited(iterator.cancel());
    });
    int total = 0;
    try {
      while (await identity.wait(iterator.moveNext().timeout(timeout))) {
        identity.check();
        final chunk = iterator.current;
        total += chunk.length;
        if (total > maximum || (exactBytes != null && total > exactBytes))
          throw mediaProtocol();
        await identity.wait(consume(chunk));
      }
      identity.check();
      if (exactBytes != null && total != exactBytes) throw mediaProtocol();
      return total;
    } finally {
      unregister();
      await iterator.cancel();
    }
  }
}
