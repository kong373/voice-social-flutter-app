import '../../../core/network/api_client.dart';
import 'registration_avatar_models.dart';

abstract interface class RegistrationAvatarTransport {
  Future<Object?> exchange({
    required RegistrationAvatarAction action,
    required RegistrationAvatarContext context,
    required String requestId,
    required String capability,
    String? assetId,
    int? expectedVersion,
    int? bytes,
    Stream<List<int>>? content,
  });
}

class ApiRegistrationAvatarTransport implements RegistrationAvatarTransport {
  const ApiRegistrationAvatarTransport(this.api);
  final ApiClient api;
  @override
  Future<Object?> exchange({
    required RegistrationAvatarAction action,
    required RegistrationAvatarContext context,
    required String requestId,
    required String capability,
    String? assetId,
    int? expectedVersion,
    int? bytes,
    Stream<List<int>>? content,
  }) async {
    final result = await api.registrationAvatarExchange(
      action: action,
      scope: RegistrationAvatarRequestScope(
        clientId: context.clientId,
        deviceId: context.deviceId,
        requestId: requestId,
        capability: capability,
        check: context.check,
        wait: context.wait,
        onCancel: context.onCancel,
      ),
      phone: action == RegistrationAvatarAction.allocate ? context.phone : null,
      smsCode: action == RegistrationAvatarAction.allocate
          ? context.smsCode
          : null,
      challengeId: action == RegistrationAvatarAction.allocate
          ? context.challengeId
          : null,
      assetId: assetId,
      expectedVersion: expectedVersion,
      bytes: bytes,
      content: content,
    );
    context.check();
    return result.data;
  }
}
