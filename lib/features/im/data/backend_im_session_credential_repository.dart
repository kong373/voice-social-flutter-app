import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';
import 'package:voice_social_app/features/im/domain/im_session_repository.dart';

/// First-party repository for the short-lived Tencent IM credential.
///
/// The route is authenticated and deliberately sends no body.  The server
/// derives the user id from the Authorization header, so this client cannot
/// ask for a credential for another account by supplying a uid.
class BackendImSessionCredentialRepository
    extends ImSessionCredentialRepository {
  BackendImSessionCredentialRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
    DateTime Function()? now,
  }) : _apiClient = apiClient,
       _routes = routes,
       _now = now ?? DateTime.now;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final DateTime Function() _now;

  static const Map<String, String> _requestHeaders = <String, String>{
    // The response is also required to carry this directive.  Sending it on
    // the request prevents an intermediary from treating this exchange as
    // cacheable when the gateway is misconfigured.
    'Cache-Control': 'no-store',
  };

  String get route => _routes.imCredential;

  @override
  Future<ImSessionCredentials> fetch() async {
    final ApiResponse
    response = await _apiClient.postWithoutUnauthorizedRecovery(
      _routes.imCredential,
      headers: _requestHeaders,
      authenticated: true,
      // Do not add a body here.  The backend resolves the principal from the
      // first-party Authorization header.
    );
    if (!_hasNoStore(response.responseHeaders)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: 'IM 凭证响应未声明 Cache-Control: no-store',
      );
    }
    return ImSessionCredentials.fromBackendData(response.data, now: _now());
  }

  @override
  Future<ImSessionCredentials> fetchCredentials() => fetch();

  static bool _hasNoStore(Map<String, String> headers) {
    final String? value = headers['cache-control'] ?? headers['Cache-Control'];
    if (value == null) {
      return false;
    }
    return value
        .split(',')
        .map((String part) => part.trim().toLowerCase())
        .any((String directive) => directive == 'no-store');
  }
}

/// Deterministic credential source for the in-memory fake adapter.  It is
/// intentionally separate from the live repository so mock mode cannot make a
/// network call.
class FakeImSessionCredentialRepository extends ImSessionCredentialRepository {
  FakeImSessionCredentialRepository({
    required String Function() userIdProvider,
    DateTime Function()? now,
    this.sdkAppId = 1,
    this.ttlSeconds = 3600,
    this.systemAccount = 'administrator',
  }) : _userIdProvider = userIdProvider,
       _now = now ?? DateTime.now;

  final String Function() _userIdProvider;
  final DateTime Function() _now;
  final int sdkAppId;
  final int ttlSeconds;
  final String systemAccount;

  @override
  Future<ImSessionCredentials> fetch() async {
    final String userId = _userIdProvider().trim();
    if (!ImSessionCredentials.isCanonicalUserId(userId)) {
      throw const ImCredentialException(ImCredentialFailure.userMismatch);
    }
    return ImSessionCredentials(
      provider: ImSessionCredentials.expectedProvider,
      sdkAppId: sdkAppId,
      userId: userId,
      userSig: 'fake-in-memory-user-sig',
      expiresAt: _now().toUtc().add(Duration(seconds: ttlSeconds)),
      ttlSeconds: ttlSeconds,
      imStatus: ImSessionCredentials.readyStatus,
      systemAccount: systemAccount,
    );
  }

  @override
  Future<ImSessionCredentials> fetchCredentials() => fetch();
}
