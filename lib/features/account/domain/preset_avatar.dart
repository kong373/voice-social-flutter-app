/// A public preset identifier and its display label.
///
/// This describes a choice, not a default selection or uploaded-media authority.
final class PresetAvatar {
  const PresetAvatar({required this.id, required this.label});

  final String id;
  final String label;
}

/// Stable catalog shared with the backend registration policy.
abstract final class PresetAvatars {
  static const List<PresetAvatar> values = <PresetAvatar>[
    PresetAvatar(id: 'avatar-preset-moon', label: '月兔'),
    PresetAvatar(id: 'avatar-preset-sun', label: '暖阳'),
    PresetAvatar(id: 'avatar-preset-cloud', label: '云朵'),
    PresetAvatar(id: 'avatar-preset-star', label: '星狐'),
    PresetAvatar(id: 'avatar-preset-sea', label: '小鲸'),
    PresetAvatar(id: 'avatar-preset-leaf', label: '叶熊'),
  ];

  /// Exact lookup: no trimming, case conversion or first-item fallback.
  static PresetAvatar? byId(String id) {
    for (final avatar in values) {
      if (avatar.id == id) {
        return avatar;
      }
    }
    return null;
  }
}
