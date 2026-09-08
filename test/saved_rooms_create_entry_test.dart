import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/presentation/saved_rooms_page.dart';
import 'package:voice_social_app/features/room/presentation/create_room_page.dart';

void main() {
  for (final bool initiallyEmpty in <bool>[true, false]) {
    testWidgets(
      'owned rooms create route and return reload (empty=$initiallyEmpty)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _Collections(initiallyEmpty: initiallyEmpty);
        // Repository fixtures are only a widget-test boundary. Navigation must
        // use the real CreateRoomPage and inherit the caller's dependencies.
        final dependencies = AppDependencies.forTestEnvironment(
          environment: AppEnvironment.mock(),
          discoveryRepository: repository,
        );
        addTearDown(dependencies.dispose);
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const SavedRoomsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('收藏测试房'), findsOneWidget);
        expect(find.text('取消收藏'), findsOneWidget);
        expect(find.text('创建房间'), findsNothing);

        await tester.tap(find.text('我的房间'));
        await tester.pumpAndSettle();
        expect(
          find.text(initiallyEmpty ? '当前账号暂无可管理房间' : '原本人房'),
          findsOneWidget,
        );
        final create = find.widgetWithText(FilledButton, '创建房间');
        expect(create.hitTestable(), findsOneWidget);
        // Exercise a queued second activation of the visible button. A second
        // physical tap already hits the new route's barrier, not this callback.
        final activate = tester.widget<FilledButton>(create).onPressed!;
        await tester.tap(create);
        activate();
        await tester.pumpAndSettle();
        expect(find.byType(CreateRoomPage), findsOneWidget);
        expect(
          AppDependencyScope.of(tester.element(find.byType(CreateRoomPage))),
          same(dependencies),
        );
        expect(repository.reads, 1);

        // A newer authoritative collection is rendered on returning even when
        // the route supplies no success result (normal system/back navigation).
        repository.changed = true;
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(CreateRoomPage), findsNothing);
        expect(repository.reads, 2);
        expect(find.text('更新后的本人房'), findsOneWidget);
        expect(find.text('管理'), findsOneWidget);
        expect(find.text('进入房间'), findsOneWidget);
        expect(create.hitTestable(), findsOneWidget);

        await tester.tap(find.text('收藏房间'));
        await tester.pumpAndSettle();
        expect(find.text('收藏测试房'), findsOneWidget);
        expect(find.text('取消收藏'), findsOneWidget);
        expect(find.text('创建房间'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _Collections extends MockDiscoveryRepository {
  _Collections({required this.initiallyEmpty});

  final bool initiallyEmpty;
  int reads = 0;
  bool changed = false;

  @override
  Future<RoomCollectionSnapshot> fetchRoomCollections({
    int page = 1,
    int pageSize = 30,
  }) async {
    reads++;
    return RoomCollectionSnapshot(
      favorites: <DiscoveryRoom>[_room('favorite', '收藏测试房')],
      ownedRooms: <DiscoveryRoom>[
        if (changed)
          _room('owned', '更新后的本人房')
        else if (!initiallyEmpty)
          _room('owned', '原本人房'),
      ],
    );
  }
}

DiscoveryRoom _room(String id, String title) => DiscoveryRoom(
  id: id,
  code: id,
  title: title,
  topic: '测试房间',
  onlineCount: 0,
  occupiedSeats: 0,
  isSpeaking: false,
  isFavorite: true,
);
