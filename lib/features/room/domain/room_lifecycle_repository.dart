import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';

abstract interface class RoomLifecycleRepository {
  RoomLifecycleCapabilities get capabilities;

  Future<RoomConfiguration?> fetchOwnedRoom();

  Future<RoomConfiguration> fetchRoom(String roomId);

  Future<RoomLifecycleSaveResult> saveRoom(RoomConfiguration configuration);

  Future<void> closeRoom(String roomId);

  Future<RoomLinkResolution> resolveRoomLink(String input);
}
