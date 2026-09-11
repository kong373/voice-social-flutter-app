part of '../network/api_client.dart';

enum ProfileAvatarUploadAction { allocate, status, complete }

extension ProfileAvatarApiTransport on ApiClient {
  Future<ApiResponse> profileAvatarUploadJson({
    required ProfileAvatarUploadAction action,
    required MediaIdentityScope identity,
    String? assetId,
    int? expectedVersion,
    String? requestId,
  }) {
    String path = '/app-api/user/profile/avatar-uploads';
    String method;
    Map<String, Object?>? body;
    String? stableRequestId;

    switch (action) {
      case ProfileAvatarUploadAction.allocate:
        if (assetId != null ||
            expectedVersion != null ||
            requestId == null ||
            !isProfileAvatarRequestId(requestId)) {
          throw mediaProtocol();
        }
        method = 'POST';
        body = const <String, Object?>{'purpose': 'AVATAR'};
        stableRequestId = requestId;
      case ProfileAvatarUploadAction.status:
        if (assetId == null || expectedVersion != null || requestId != null) {
          throw mediaProtocol();
        }
        path += '/${requireMediaId(assetId)}';
        method = 'GET';
      case ProfileAvatarUploadAction.complete:
        if (assetId == null ||
            expectedVersion == null ||
            expectedVersion < 0 ||
            requestId != null) {
          throw mediaProtocol();
        }
        path += '/${requireMediaId(assetId)}/complete';
        method = 'POST';
        body = {'expectedVersion': expectedVersion};
    }

    return _mediaExchange(
      method: method,
      path: path,
      identity: identity,
      body: body,
      requestId: stableRequestId,
    );
  }

  Future<ApiResponse> putProfileAvatarUploadContent({
    required MediaIdentityScope identity,
    required String assetId,
    required int expectedVersion,
    required int bytes,
    required Stream<List<int>> Function() content,
  }) {
    if (expectedVersion < 0 || bytes <= 0 || bytes > 10000000) {
      throw mediaProtocol();
    }
    return _mediaExchange(
      method: 'PUT',
      path:
          '/app-api/user/profile/avatar-uploads/${requireMediaId(assetId)}/content?expectedVersion=$expectedVersion',
      identity: identity,
      requestId: null,
      upload: content(),
      uploadBytes: bytes,
      maximumBytes: 10000000,
    );
  }
}

bool isProfileAvatarRequestId(String value) =>
    RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(value);
