import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';

/// Metadata-only event admitted from an AVChatRoom custom element.
///
/// The provider payload is parsed and discarded at the Tencent adapter
/// boundary. Consumers receive only the bounded hint and the transient group
/// scope; they must refresh the current room through an authoritative HTTP
/// repository before changing any UI or permission state.
class ImRoomRefreshEvent {
  const ImRoomRefreshEvent({
    required this.groupId,
    required this.hint,
    this.sessionId,
  });

  final String groupId;
  final ImRefreshHint hint;

  /// Optional transient session fence from an event-aware bridge. It is not
  /// read from the custom payload; a missing value falls back to the active
  /// generation/lease fence in the room coordinator.
  final String? sessionId;
}

/// Optional capability exposed by an IM session adapter that can join a
/// Tencent AVChatRoom. Provider implementations should return `false` from
/// [supportsAvChatRoom] when the SDK is absent or not enabled, allowing room
/// UI to remain on its HTTP snapshot path.
abstract interface class ImRoomGroupCapability {
  bool get supportsAvChatRoom;

  Stream<ImRoomRefreshEvent> get roomEvents;

  /// Returns `true` when the provider accepted (or already had) the group.
  /// A provider-unavailable implementation must return `false` without making
  /// a network/vendor call.
  Future<bool> joinGroup({required String groupId, required String groupType});

  /// Returns `true` when the provider accepted (or already completed) the
  /// leave. Implementations must bound this call.
  Future<bool> quitGroup({required String groupId});
}
