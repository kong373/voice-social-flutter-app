import 'package:voice_social_app/core/network/api_exception.dart';

/// Audio authority only. Member-list `muted` is public-text moderation and
/// must never be passed here as microphone authority.
class RoomAudioMuteState {
  const RoomAudioMuteState({
    required this.selfMuted,
    required this.forcedMuted,
    required this.legacyMuted,
    this.version,
  });

  final bool selfMuted;
  final bool forcedMuted;
  final bool legacyMuted;
  final int? version;
  bool get effectiveMuted => selfMuted || forcedMuted || legacyMuted;

  static RoomAudioMuteState parse(
    Map<String, Object?> data, {
    bool occupied = true,
    bool requireVersion = true,
  }) {
    const invalid = ApiException(
      kind: ApiFailureKind.protocol,
      message: '麦克风静音原因或版本无效',
    );
    final self = data['selfMuted'],
        forced = data['forcedMuted'],
        legacy = data['legacyMuted'];
    final version = data['version'];
    if (self is! bool ||
        forced is! bool ||
        legacy is! bool ||
        (version == null ? requireVersion : version is! int || version < 0))
      throw invalid;
    final result = RoomAudioMuteState(
      selfMuted: self,
      forcedMuted: forced,
      legacyMuted: legacy,
      version: version as int?,
    );
    if (data['muted'] is! bool ||
        (occupied && data['muted'] != result.effectiveMuted))
      throw invalid;
    return result;
  }

  /// Old snapshots can still be displayed, but missing reasons cannot grant
  /// publishing. Partial new contracts are invalid rather than guessed.
  static RoomAudioMuteState? optionalSnapshot(
    Map<String, Object?> data, {
    required bool occupied,
  }) {
    if (!['selfMuted', 'forcedMuted', 'legacyMuted'].any(data.containsKey))
      return null;
    // Enter/authority snapshots do not expose a seat version; receipts do.
    return parse(data, occupied: occupied, requireVersion: false);
  }
}
