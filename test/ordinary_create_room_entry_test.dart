import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/room/presentation/create_room_page.dart';
import 'package:voice_social_app/features/room/presentation/room_configuration_form.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';

void main() {
  for (final bool closed in <bool>[false, true]) {
    testWidgets(
      'ordinary home opens owned room selection and refreshes on back '
      '(closed=$closed)',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(
          closed ? const Size(360, 800) : const Size(390, 844),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _HomeRooms();
        final dependencies = AppDependencies.forTestEnvironment(
          environment: AppEnvironment.mock(),
          discoveryRepository: repository,
        );
        addTearDown(dependencies.dispose);
        if (closed) {
          await tester.runAsync(
            () => dependencies.roomLifecycleRepository.closeRoom('952700'),
          );
        }
        // Keep the scope below Navigator to prove the new route carries the
        // ordinary home's dependencies instead of relying on a global scope.
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.social(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(closed ? 1.3 : 1)),
              child: child!,
            ),
            home: AppDependencyScope(
              dependencies: dependencies,
              child: Scaffold(
                body: VideoRuntimeHomePage(
                  dependencies: dependencies,
                  onOpenRoom: (_) => fail('Entry must open the creation form'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final entry = find.widgetWithText(TextButton, '创建房间');
        expect(entry.hitTestable(), findsOneWidget);
        expect(find.byTooltip('榜单').hitTestable(), findsOneWidget);
        expect(find.byTooltip('搜索').hitTestable(), findsOneWidget);
        expect(repository.reads, 1);

        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(CreateRoomPage), findsOneWidget);
        expect(
          AppDependencyScope.of(tester.element(find.byType(CreateRoomPage))),
          same(dependencies),
        );
        expect(find.byType(RoomConfigurationForm), findsNothing);
        expect(find.text('名下房间'), findsOneWidget);
        expect(find.text('创建新房间'), findsOneWidget);
        expect(find.text('周末松弛聊天局'), findsWidgets);
        expect(find.textContaining('房间号 952700'), findsOneWidget);
        expect(find.text(closed ? '已关闭' : '已开放'), findsOneWidget);
        expect(find.text('创建固定 8 麦房'), findsNothing);
        expect(repository.reads, 1);

        // System back has no success result, but must still refresh the home.
        repository.changed = true;
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(CreateRoomPage), findsNothing);
        expect(repository.reads, 2);
        expect(find.text('返回后刷新房间'), findsWidgets);
        expect(entry.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _HomeRooms extends MockDiscoveryRepository {
  int reads = 0;
  bool changed = false;

  @override
  Future<List<DiscoveryRoom>> fetchHomeRooms({
    int page = 1,
    int pageSize = 20,
  }) async {
    reads++;
    return <DiscoveryRoom>[
      DiscoveryRoom(
        id: 'home-room',
        code: '123456',
        title: changed ? '返回后刷新房间' : '首页测试房间',
        topic: '轻聊',
        onlineCount: 1,
        occupiedSeats: 1,
        isSpeaking: false,
        isFavorite: false,
      ),
    ];
  }
}
