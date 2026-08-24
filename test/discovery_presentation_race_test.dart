import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/presentation/saved_rooms_page.dart';
import 'package:voice_social_app/features/discovery/presentation/search_results_page.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';

void main() {
  testWidgets('home ignores an older success after a newer refresh', (
    WidgetTester tester,
  ) async {
    final _DelayedDiscoveryRepository repository =
        _DelayedDiscoveryRepository();
    await _pump(tester, const Scaffold(body: HomePage()), repository);
    expect(repository.homeRequests, hasLength(1));

    final RefreshIndicator indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final Future<void> secondLoad = indicator.onRefresh();
    await tester.pump();
    expect(repository.homeRequests, hasLength(2));

    repository.homeRequests[1].complete(<DiscoveryRoom>[_newRoom]);
    await secondLoad;
    await tester.pumpAndSettle();
    repository.homeRequests[0].complete(<DiscoveryRoom>[_oldRoom]);
    await tester.pumpAndSettle();

    expect(find.text('新响应房间'), findsWidgets);
    expect(find.text('旧响应房间'), findsNothing);
  });

  testWidgets(
    'search ignores an older error after the selected type succeeds',
    (WidgetTester tester) async {
      final _DelayedDiscoveryRepository repository =
          _DelayedDiscoveryRepository();
      await _pump(tester, const SearchResultsPage(keyword: '夜聊'), repository);
      expect(repository.searchRequests, hasLength(1));

      await tester.tap(find.text('房间'));
      await tester.pump();
      expect(repository.searchRequests, hasLength(2));
      repository.searchRequests[1].complete(_roomSearchResult);
      await tester.pumpAndSettle();
      repository.searchRequests[0].completeError(
        const ApiException(
          kind: ApiFailureKind.server,
          httpStatus: 500,
          message: '旧请求失败',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('新响应房间'), findsWidgets);
      expect(find.text('旧请求失败'), findsNothing);
      expect(find.text('搜索失败'), findsNothing);
    },
  );

  testWidgets('saved rooms ignores an older success after a newer refresh', (
    WidgetTester tester,
  ) async {
    final _DelayedDiscoveryRepository repository =
        _DelayedDiscoveryRepository();
    await _pump(tester, const SavedRoomsPage(), repository);
    expect(repository.collectionRequests, hasLength(1));

    final IconButton refresh = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.refresh_rounded),
    );
    refresh.onPressed!();
    await tester.pump();
    expect(repository.collectionRequests, hasLength(2));

    repository.collectionRequests[1].complete(
      const RoomCollectionSnapshot(
        favorites: <DiscoveryRoom>[_newRoom],
        ownedRooms: <DiscoveryRoom>[],
      ),
    );
    await tester.pumpAndSettle();
    repository.collectionRequests[0].complete(
      const RoomCollectionSnapshot(
        favorites: <DiscoveryRoom>[_oldRoom],
        ownedRooms: <DiscoveryRoom>[],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新响应房间'), findsWidgets);
    expect(find.text('旧响应房间'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  _DelayedDiscoveryRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final AppDependencies dependencies = AppDependencies.forTestEnvironment(
    environment: AppEnvironment.mock(),
    discoveryRepository: repository,
  );
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(theme: AppTheme.dark(), home: page),
    ),
  );
  await tester.pump();
}

const DiscoveryRoom _oldRoom = DiscoveryRoom(
  id: 'old-room',
  code: 'old-room',
  title: '旧响应房间',
  topic: '旧请求',
  onlineCount: 1,
  occupiedSeats: 1,
  isSpeaking: false,
  isFavorite: true,
);

const DiscoveryRoom _newRoom = DiscoveryRoom(
  id: 'new-room',
  code: 'new-room',
  title: '新响应房间',
  topic: '新请求',
  onlineCount: 2,
  occupiedSeats: 1,
  isSpeaking: true,
  isFavorite: true,
);

const DiscoverySearchResult _roomSearchResult = DiscoverySearchResult(
  rooms: <DiscoveryRoom>[_newRoom],
  users: <DiscoveryUser>[],
  page: 1,
  pageSize: 20,
  hasMore: false,
);

class _DelayedDiscoveryRepository extends MockDiscoveryRepository {
  final List<Completer<List<DiscoveryRoom>>> homeRequests =
      <Completer<List<DiscoveryRoom>>>[];
  final List<Completer<DiscoverySearchResult>> searchRequests =
      <Completer<DiscoverySearchResult>>[];
  final List<Completer<RoomCollectionSnapshot>> collectionRequests =
      <Completer<RoomCollectionSnapshot>>[];

  @override
  Future<List<DiscoveryRoom>> fetchHomeRooms({
    int page = 1,
    int pageSize = 20,
  }) {
    final Completer<List<DiscoveryRoom>> request =
        Completer<List<DiscoveryRoom>>();
    homeRequests.add(request);
    return request.future;
  }

  @override
  Future<DiscoverySearchResult> search({
    required String keyword,
    required SearchEntityType type,
    int page = 1,
    int pageSize = 20,
  }) {
    final Completer<DiscoverySearchResult> request =
        Completer<DiscoverySearchResult>();
    searchRequests.add(request);
    return request.future;
  }

  @override
  Future<RoomCollectionSnapshot> fetchRoomCollections({
    int page = 1,
    int pageSize = 30,
  }) {
    final Completer<RoomCollectionSnapshot> request =
        Completer<RoomCollectionSnapshot>();
    collectionRequests.add(request);
    return request.future;
  }
}
