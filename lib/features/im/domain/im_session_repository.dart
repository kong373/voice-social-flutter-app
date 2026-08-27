import 'package:voice_social_app/features/im/domain/im_session_credentials.dart';

/// Retrieves a short-lived provider credential for the already authenticated
/// first-party session.  Implementations must not accept a user id argument;
/// the backend derives the principal from the Authorization header.
abstract class ImSessionCredentialRepository {
  const ImSessionCredentialRepository();

  /// Canonical method used by the coordinator.
  ///
  /// The default delegates to [fetchCredentials] so test doubles and future
  /// implementations can use either descriptive method name without creating
  /// a second repository contract.
  Future<ImSessionCredentials> fetch() => fetchCredentials();

  /// Descriptive alias for callers that prefer an explicit method name.
  Future<ImSessionCredentials> fetchCredentials() {
    throw UnimplementedError('IM 凭证仓储未实现');
  }
}

class BlockedImSessionCredentialRepository
    extends ImSessionCredentialRepository {
  const BlockedImSessionCredentialRepository();

  @override
  Future<ImSessionCredentials> fetch() => Future<ImSessionCredentials>.error(
    const ImCredentialException(ImCredentialFailure.invalidProvider),
  );

  @override
  Future<ImSessionCredentials> fetchCredentials() => fetch();
}
