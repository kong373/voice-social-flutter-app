import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';
import 'package:voice_social_app/features/shell/video_runtime_pages.dart';

void main() {
  testWidgets(
    'identity change while covered waits for return and clears old rooms',
    (tester) async {
      final repository = _DelayedHomeRepository();
      await _pumpHome(tester, repository);
      repository.requests.single.complete(<DiscoveryRoom>[_oldRoom]);
      await tester.pumpAndSettle();
      final home = find.byType(VideoRuntimeHomePage);
      final dependencies = tester
          .widget<VideoRuntimeHomePage>(home)
          .dependencies;
      final navigator = Navigator.of(tester.element(home));
      navigator.push<void>(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await tester.pumpAndSettle();
      await dependencies.sessionManager.save(
        AuthSession(
          accessToken: 'test-only',
          tokenType: 'Bearer',
          expiresAt: DateTime(2099),
          userId: 42,
          mobile: '',
          roles: '',
        ),
      );
      await tester.pump();
      expect(repository.requests, hasLength(1));
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.requests, hasLength(2));
      expect(find.text('旧响应房间'), findsNothing);
      repository.requests.last.complete(<DiscoveryRoom>[_newRoom]);
      await tester.pumpAndSettle();
      expect(find.text('新响应房间'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('normal route return reloads authoritative room counts', (
    tester,
  ) async {
    final repository = _DelayedHomeRepository();
    await _pumpHome(tester, repository);
    repository.requests.single.complete(<DiscoveryRoom>[_countRoom(3, 2)]);
    await tester.pumpAndSettle();
    expect(find.text('2/8 麦'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('live-room-count-room')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    final navigator = Navigator.of(
      tester.element(find.byType(VideoRuntimeHomePage)),
    );
    navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('room')),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.requests, hasLength(1));
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.requests, hasLength(2));
    repository.requests.last.complete(<DiscoveryRoom>[_countRoom(1, 0)]);
    await tester.pumpAndSettle();
    expect(find.text('0/8 麦'), findsOneWidget);
    expect(find.text('2/8 麦'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('live-room-count-room')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(repository.requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final bool fails in <bool>[false, true]) {
    testWidgets(
      'identity switch rejects stale ${fails ? 'error' : 'success'}',
      (tester) async {
        final repository = _DelayedHomeRepository();
        await _pumpHome(tester, repository);
        final dependencies = tester
            .widget<VideoRuntimeHomePage>(find.byType(VideoRuntimeHomePage))
            .dependencies;
        await dependencies.sessionManager.save(
          AuthSession(
            accessToken: 'test-only',
            tokenType: 'Bearer',
            expiresAt: DateTime(2099),
            userId: 42,
            mobile: '',
            roles: '',
          ),
        );
        await tester.pump();
        expect(repository.requests, hasLength(2));
        repository.requests.last.complete(<DiscoveryRoom>[_newRoom]);
        await tester.pumpAndSettle();
        if (fails) {
          repository.requests.first.completeError(StateError('stale identity'));
        } else {
          repository.requests.first.complete(<DiscoveryRoom>[_oldRoom]);
        }
        await tester.pumpAndSettle();
        expect(find.text('新响应房间'), findsWidgets);
        expect(find.text('旧响应房间'), findsNothing);
        expect(find.text('房间推荐暂时无法加载'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'disposed home ignores pending ${fails ? 'error' : 'success'}',
      (tester) async {
        final repository = _DelayedHomeRepository();
        await _pumpHome(tester, repository);
        final dependencies = tester
            .widget<VideoRuntimeHomePage>(find.byType(VideoRuntimeHomePage))
            .dependencies;
        await tester.pumpWidget(const SizedBox.shrink());
        await dependencies.sessionManager.save(
          AuthSession(
            accessToken: 'test-only',
            tokenType: 'Bearer',
            expiresAt: DateTime(2099),
            userId: 42,
            mobile: '',
            roles: '',
          ),
        );
        if (fails) {
          repository.requests.single.completeError(StateError('disposed'));
        } else {
          repository.requests.single.complete(<DiscoveryRoom>[_oldRoom]);
        }
        await tester.pumpAndSettle();
        expect(repository.requests, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('dependency replacement rejects old repository response', (
    tester,
  ) async {
    final oldRepository = _DelayedHomeRepository();
    await _pumpHome(tester, oldRepository);
    final newRepository = _DelayedHomeRepository();
    await _pumpHome(tester, newRepository);
    expect(newRepository.requests, hasLength(1));
    newRepository.requests.single.complete(<DiscoveryRoom>[_newRoom]);
    oldRepository.requests.single.complete(<DiscoveryRoom>[_oldRoom]);
    await tester.pumpAndSettle();
    expect(find.text('新响应房间'), findsWidgets);
    expect(find.text('旧响应房间'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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

DiscoveryRoom _countRoom(int online, int seats) => DiscoveryRoom(
  id: 'count-room',
  code: 'count-room',
  title: '人数回归房间',
  topic: '轻聊',
  onlineCount: online,
  occupiedSeats: seats,
  isSpeaking: false,
  isFavorite: false,
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
