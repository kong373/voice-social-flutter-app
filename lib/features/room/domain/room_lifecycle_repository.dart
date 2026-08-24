import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';

abstract interface class RoomLifecycleRepository {
  RoomLifecycleCapabilities get capabilities;

  Future<RoomConfiguration?> fetchOwnedRoom();

  Future<RoomConfiguration> fetchRoom(String roomId);

  Future<RoomLifecycleSaveResult> saveRoom(RoomConfiguration configuration);

  /// Closes an existing room using the version from its authoritative
  /// [RoomConfiguration] snapshot. Implementations backed by the live API
  /// reject a missing version instead of silently falling back to a read.
  Future<void> closeRoom(String roomId, {int? expectedVersion});

  Future<RoomLinkResolution> resolveRoomLink(String input);
}
