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
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';

void main() {
  testWidgets('home ignores an older success after refresh succeeds', (
    WidgetTester tester,
  ) async {
    final _DelayedHomeRepository repository = _DelayedHomeRepository();
    await _pumpHome(tester, repository);
    expect(repository.requests, hasLength(1));

    final RefreshIndicator indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final Future<void> refresh = indicator.onRefresh();
    await tester.pump();
    expect(repository.requests, hasLength(2));

    repository.requests[1].complete(<DiscoveryRoom>[_newRoom]);
    await refresh;
    await tester.pumpAndSettle();
    repository.requests[0].complete(<DiscoveryRoom>[_oldRoom]);
    await tester.pumpAndSettle();

    expect(find.text('新响应房间'), findsWidgets);
    expect(find.text('旧响应房间'), findsNothing);
  });

  testWidgets('home ignores an older error after refresh succeeds', (
    WidgetTester tester,
  ) async {
    final _DelayedHomeRepository repository = _DelayedHomeRepository();
    await _pumpHome(tester, repository);
    expect(repository.requests, hasLength(1));

    final RefreshIndicator indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final Future<void> refresh = indicator.onRefresh();
    await tester.pump();
    expect(repository.requests, hasLength(2));

    repository.requests[1].complete(<DiscoveryRoom>[_newRoom]);
    await refresh;
    await tester.pumpAndSettle();
    repository.requests[0].completeError(
      const ApiException(
        kind: ApiFailureKind.server,
        httpStatus: 500,
        message: '旧请求失败',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新响应房间'), findsWidgets);
    expect(find.text('旧请求失败'), findsNothing);
    expect(find.text('加载失败'), findsNothing);
  });

  testWidgets('换一批 invalidates a pending refresh generation', (
    WidgetTester tester,
  ) async {
    final _DelayedHomeRepository repository = _DelayedHomeRepository();
    await _pumpHome(tester, repository);
    repository.requests[0].complete(<DiscoveryRoom>[_firstRoom, _secondRoom]);
    await tester.pumpAndSettle();

    final RefreshIndicator indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final Future<void> refresh = indicator.onRefresh();
    await tester.pump();
    expect(repository.requests, hasLength(2));

    await tester.tap(find.byKey(const Key('home-rotate-rooms')).hitTestable());
    await tester.pump();
    expect(find.text('第二个房间'), findsWidgets);

    repository.requests[1].complete(<DiscoveryRoom>[_newRoom]);
    await refresh;
    await tester.pumpAndSettle();

    expect(find.text('第二个房间'), findsWidgets);
    expect(find.text('新响应房间'), findsNothing);
  });
}

Future<void> _pumpHome(
  WidgetTester tester,
  DiscoveryRepository repository,
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
      child: MaterialApp(
        theme: AppTheme.social(),
        home: Scaffold(
          body: VideoRuntimeHomePage(
            dependencies: dependencies,
            repository: repository,
            onOpenRoom: (_) {},
          ),
        ),
      ),
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

const DiscoveryRoom _firstRoom = DiscoveryRoom(
  id: 'first-room',
  code: 'first-room',
  title: '第一个房间',
  topic: '初始请求',
  onlineCount: 1,
  occupiedSeats: 1,
  isSpeaking: false,
  isFavorite: true,
);

const DiscoveryRoom _secondRoom = DiscoveryRoom(
  id: 'second-room',
  code: 'second-room',
  title: '第二个房间',
  topic: '初始请求',
  onlineCount: 2,
  occupiedSeats: 1,
  isSpeaking: true,
  isFavorite: true,
);

class _DelayedHomeRepository extends MockDiscoveryRepository {
  final List<Completer<List<DiscoveryRoom>>> requests =
      <Completer<List<DiscoveryRoom>>>[];

  @override
  Future<List<DiscoveryRoom>> fetchHomeRooms({
    int page = 1,
    int pageSize = 20,
  }) {
    final Completer<List<DiscoveryRoom>> request =
        Completer<List<DiscoveryRoom>>();
    requests.add(request);
    return request.future;
  }
}
