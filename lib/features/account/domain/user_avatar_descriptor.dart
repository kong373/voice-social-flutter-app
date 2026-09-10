/// The two supported forms of the backend's compact user-avatar projection.
enum UserAvatarKind { preset, uploaded }

/// An immutable, syntactically validated avatar descriptor.
///
/// An uploaded reference is a media asset public ID, never a URL.
/// Successful parsing does not establish asset ownership, readiness,
/// visibility, download permission or the existence of the referenced asset.
final class UserAvatarDescriptor {
  const UserAvatarDescriptor._({
    required this.kind,
    required this.reference,
    required this.version,
  });

  final UserAvatarKind kind;
  final String reference;

  /// Null for presets; a required nonnegative integer for uploaded avatars.
  final int? version;

  static const Set<String> _presetIds = <String>{
    'avatar-preset-moon',
    'avatar-preset-sun',
    'avatar-preset-cloud',
    'avatar-preset-star',
    'avatar-preset-sea',
    'avatar-preset-leaf',
  };

  static const Set<String> _presetFields = <String>{'kind', 'reference'};

  static const Set<String> _uploadedFields = <String>{
    'kind',
    'reference',
    'version',
  };

  static final RegExp _canonicalUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// Parses a non-null backend descriptor without coercion or fallback.
  ///
  /// Field sets are exact and differ by kind. No input value is trimmed,
  /// case-normalized, converted into a URL or retained in diagnostics.
  factory UserAvatarDescriptor.fromBackendData(Object? raw) {
    if (raw is! Map<Object?, Object?> ||
        raw.keys.any((key) => key is! String)) {
      throw const FormatException('Invalid user avatar descriptor');
    }

    final kind = raw['kind'];
    final reference = raw['reference'];

    if (kind is! String || reference is! String) {
      throw const FormatException('Invalid user avatar descriptor');
    }

    switch (kind) {
      case 'PRESET':
        if (!_hasExactFields(raw, _presetFields) ||
            !_presetIds.contains(reference)) {
          throw const FormatException('Invalid user avatar descriptor');
        }

        return UserAvatarDescriptor._(
          kind: UserAvatarKind.preset,
          reference: reference,
          version: null,
        );

      case 'UPLOADED':
        final version = raw['version'];

        if (!_hasExactFields(raw, _uploadedFields) ||
            reference.length != 36 ||
            !_canonicalUuid.hasMatch(reference) ||
            version is! int ||
            version < 0) {
          throw const FormatException('Invalid user avatar descriptor');
        }

        return UserAvatarDescriptor._(
          kind: UserAvatarKind.uploaded,
          reference: reference,
          version: version,
        );

      default:
        throw const FormatException('Invalid user avatar descriptor');
    }
  }

  /// Supports legacy null projections without inventing a default avatar.
  ///
  /// Every non-null value is subject to the same strict parser.
  static UserAvatarDescriptor? parseOptional(Object? raw) {
    return raw == null ? null : UserAvatarDescriptor.fromBackendData(raw);
  }

  static bool _hasExactFields(
    Map<Object?, Object?> data,
    Set<String> allowedFields,
  ) {
    return data.length == allowedFields.length &&
        data.keys.every(allowedFields.contains);
  }

  /// Diagnostics deliberately omit the asset reference and input payload.
  @override
  String toString() => 'UserAvatarDescriptor(kind: ${kind.name})';
}
