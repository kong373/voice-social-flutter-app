import '../network/api_client.dart';
import 'media_identity.dart';

/// Logged-in profile-avatar media operations.  The dedicated adapter keeps
/// AVATAR uploads away from the generic media routes and their semantics.
abstract interface class ProfileAvatarMediaTransport {
  Future<ApiResponse> allocateUpload({
    required MediaIdentityScope identity,
    required String requestId,
  });

  Future<ApiResponse> statusUpload({
    required MediaIdentityScope identity,
    required String assetId,
  });

  Future<ApiResponse> putUploadContent({
    required MediaIdentityScope identity,
    required String assetId,
    required int expectedVersion,
    required int bytes,
    required Stream<List<int>> Function() content,
  });

  Future<ApiResponse> completeUpload({
    required MediaIdentityScope identity,
    required String assetId,
    required int expectedVersion,
  });
}

/// Default adapter backed by the existing authenticated HTTP client.
final class ApiProfileAvatarMediaTransport
    implements ProfileAvatarMediaTransport {
  const ApiProfileAvatarMediaTransport(this.api);

  final ApiClient api;

  @override
  Future<ApiResponse> allocateUpload({
    required MediaIdentityScope identity,
    required String requestId,
  }) => api.profileAvatarUploadJson(
    action: ProfileAvatarUploadAction.allocate,
    identity: identity,
    requestId: requestId,
  );

  @override
  Future<ApiResponse> statusUpload({
    required MediaIdentityScope identity,
    required String assetId,
  }) => api.profileAvatarUploadJson(
    action: ProfileAvatarUploadAction.status,
    identity: identity,
    assetId: assetId,
  );

  @override
  Future<ApiResponse> putUploadContent({
    required MediaIdentityScope identity,
    required String assetId,
    required int expectedVersion,
    required int bytes,
    required Stream<List<int>> Function() content,
  }) => api.putProfileAvatarUploadContent(
    identity: identity,
    assetId: assetId,
    expectedVersion: expectedVersion,
    bytes: bytes,
    content: content,
  );

  @override
  Future<ApiResponse> completeUpload({
    required MediaIdentityScope identity,
    required String assetId,
    required int expectedVersion,
  }) => api.profileAvatarUploadJson(
    action: ProfileAvatarUploadAction.complete,
    identity: identity,
    assetId: assetId,
    expectedVersion: expectedVersion,
  );
}
