import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';

void main() {
  test('discovery repository searches rooms and users by authoritative type', () async {
    final MockDiscoveryRepository repository = MockDiscoveryRepository();

    final DiscoverySearchResult roomResult = await repository.search(
      keyword: '880217',
      type: SearchEntityType.rooms,
    );
    expect(roomResult.rooms.single.code, '880217');
    expect(roomResult.users, isEmpty);

    final DiscoverySearchResult userResult = await repository.search(
      keyword: '南风',
      type: SearchEntityType.users,
    );
    expect(userResult.users.single.name, '南风');
    expect(userResult.rooms, isEmpty);
  });

  test('favorite mutation is reflected in room collections', () async {
    final MockDiscoveryRepository repository = MockDiscoveryRepository();
    RoomCollectionSnapshot snapshot = await repository.fetchRoomCollections();
    expect(
      snapshot.favorites.any((DiscoveryRoom room) => room.id == '660318'),
      isFalse,
    );

    await repository.setFavorite(roomId: '660318', favorite: true);
    snapshot = await repository.fetchRoomCollections();
    expect(
      snapshot.favorites.any((DiscoveryRoom room) => room.id == '660318'),
      isTrue,
    );

    await repository.setFavorite(roomId: '660318', favorite: false);
    snapshot = await repository.fetchRoomCollections();
    expect(
      snapshot.favorites.any((DiscoveryRoom room) => room.id == '660318'),
      isFalse,
    );
  });
}
