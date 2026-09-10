import 'package:voice_social_app/core/network/api_exception.dart';
import 'preset_avatar.dart';

const registrationChoiceInvalid = ApiException(
  kind: ApiFailureKind.validation,
  message: '请完整选择昵称、头像和性别',
);

final _avatarId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// A requested avatar, never an authorization to read or bind an upload.
final class RegistrationAvatarChoice {
  const RegistrationAvatarChoice._(
    this.kind,
    this.reference,
    this.expectedVersion,
  );
  factory RegistrationAvatarChoice.preset(String id) {
    if (PresetAvatars.byId(id) == null) throw registrationChoiceInvalid;
    return RegistrationAvatarChoice._('PRESET', id, null);
  }
  factory RegistrationAvatarChoice.uploaded(String id, int version) {
    if (id.length != 36 || !_avatarId.hasMatch(id) || version < 0)
      throw registrationChoiceInvalid;
    return RegistrationAvatarChoice._('UPLOADED', id, version);
  }
  final String kind;
  final String reference;
  final int? expectedVersion;
  Map<String, Object?> toJson() => {
    'kind': kind,
    'reference': reference,
    if (expectedVersion != null) 'expectedVersion': expectedVersion,
  };
}

/// Short-lived registration submission binding. Not an App session/token.
/// The upload capability is only sent as an HTTP header, never in the body.
final class RegistrationProof {
  const RegistrationProof({
    required this.challengeId,
    required this.requestId,
    required this.requireCurrent,
    this.avatarCapability,
  });
  final String challengeId;
  final String requestId;
  final String? avatarCapability;
  final void Function() requireCurrent;

  void validate(RegistrationAvatarChoice choice) {
    requireCurrent();
    if (challengeId.length != 36 ||
        !_avatarId.hasMatch(challengeId) ||
        requestId.length > 128 ||
        requestId.contains('\n') ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(requestId)) {
      throw registrationChoiceInvalid;
    }
    if (choice.kind == 'UPLOADED') {
      final capability = avatarCapability;
      if (capability == null ||
          capability.length != 43 ||
          !RegExp(
            r'^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$',
          ).hasMatch(capability)) {
        throw registrationChoiceInvalid;
      }
    } else if (avatarCapability != null) {
      throw registrationChoiceInvalid;
    }
  }
}

void validateRegistrationProfile(
  String nickname,
  int sex,
  RegistrationAvatarChoice? avatar,
) {
  if (nickname.trim().isEmpty ||
      nickname.trim().length > 24 ||
      sex < 0 ||
      sex > 2 ||
      avatar == null)
    throw registrationChoiceInvalid;
  final units = nickname.codeUnits;
  for (var index = 0; index < units.length; index++) {
    final value = units[index];
    if (value < 32 || (value >= 127 && value <= 159))
      throw registrationChoiceInvalid;
    if (value >= 0xd800 && value <= 0xdbff) {
      if (++index >= units.length ||
          units[index] < 0xdc00 ||
          units[index] > 0xdfff) {
        throw registrationChoiceInvalid;
      }
    } else if (value >= 0xdc00 && value <= 0xdfff) {
      throw registrationChoiceInvalid;
    }
  }
}
