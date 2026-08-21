import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';

abstract interface class DiscoveryRepository {
  Future<List<DiscoveryRoom>> fetchHomeRooms({int page = 1, int pageSize = 20});

  Future<DiscoverySearchResult> search({
    required String keyword,
    required SearchEntityType type,
    int page = 1,
    int pageSize = 20,
  });

  Future<RoomCollectionSnapshot> fetchRoomCollections({
    int page = 1,
    int pageSize = 30,
  });

  Future<bool> setFavorite({required String roomId, required bool favorite});
}
