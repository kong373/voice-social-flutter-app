import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';

void main() {
  testWidgets('live guardian requires an anchor before making a request', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _RequestRecorder recorder = _RequestRecorder();

    await _withRecorder(recorder, () async {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'https://community.test/',
          clientType: 'Android',
          clientInnerVersion: '6',
          oauthClientId: 'public-test-client',
          realtimeEndpoint: '',
        ),
      );
      await dependencies.sessionManager.save(
        AuthSession(
          accessToken: 'guardian-test-token',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          userId: 10001,
          mobile: 'test-user',
          roles: 'USER',
        ),
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: const GuardianFanPage(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      for (int index = 0; index < 5; index += 1) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    });

    expect(find.byKey(const Key('guardian-anchor-required')), findsOneWidget);
    expect(recorder.paths, isEmpty);
  });

  testWidgets('global search starts without business recent-search fixtures', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: AppDependencies.mock(),
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const GlobalSearchPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('live guardian renders the server anchor name', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _RequestRecorder recorder = _RequestRecorder();

    await _withRecorder(recorder, () async {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: const AppEnvironment(
          backendMode: BackendMode.live,
          apiBaseUrl: 'https://community.test/',
          clientType: 'Android',
          clientInnerVersion: '6',
          oauthClientId: 'public-test-client',
          realtimeEndpoint: '',
        ),
      );
      await dependencies.sessionManager.save(
        AuthSession(
          accessToken: 'guardian-test-token',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          userId: 10001,
          mobile: 'test-user',
          roles: 'USER',
        ),
      );
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: const GuardianFanPage(initialAnchorUserId: 88),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      for (int index = 0; index < 5; index += 1) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    });

    expect(find.text('主播甲'), findsOneWidget);
    expect(find.text('晚星'), findsNothing);
    expect(recorder.paths, hasLength(4));
  });
}

Future<T> _withRecorder<T>(
  _RequestRecorder recorder,
  Future<T> Function() action,
) {
  return HttpOverrides.runZoned(
    action,
    createHttpClient: (_) => _RecordingHttpClient(recorder),
  );
}

class _RequestRecorder {
  final List<String> paths = <String>[];
}

class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(this.recorder);

  final _RequestRecorder recorder;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    recorder.paths.add(url.path);
    return _RecordingHttpClientRequest(_guardianResponse(url.path));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingHttpClientRequest implements HttpClientRequest {
  _RecordingHttpClientRequest(this.data);

  final Object? data;

  @override
  final HttpHeaders headers = _RecordingHttpHeaders();

  @override
  Future<HttpClientResponse> close() async =>
      _RecordingHttpClientResponse(data);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingHttpClientResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _RecordingHttpClientResponse(Object? data)
    : super(
        Stream<List<int>>.value(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': data,
            }),
          ),
        ),
      );

  @override
  int get statusCode => 200;

  @override
  final HttpHeaders headers = _RecordingHttpHeaders();

  @override
  bool get isRedirect => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Object? _guardianResponse(String path) => switch (path) {
  '/app-api/room/radio/v1/queryGuardianLevels' => <String, Object?>{
    'list': <Object?>[
      <String, Object?>{
        'id': '2',
        'name': '银色守护',
        'price': 88,
        'durationDays': 30,
      },
    ],
    'total': 1,
    'providerInvocation': false,
  },
  '/app-api/room/radio/v1/queryOenGuardianInfo' => <String, Object?>{
    'anchorUserId': 88,
    'anchorName': '主播甲',
    'nickName': '主播甲',
    'roomId': 'room-88',
    'active': true,
    'guardianLevelId': '2',
    'levelId': '2',
    'levelName': '银色守护',
    'price': 88,
    'durationDays': 30,
    'startedAt': '2026-08-01T00:00:00Z',
    'expiresAt': '2026-08-31T00:00:00Z',
    'providerInvocation': false,
  },
  '/app-api/room/radio/v1/queryFansTeamRelation' => <String, Object?>{
    'anchorUserId': 88,
    'roomId': 'room-88',
    'fansTeamId': 'fans-88',
    'fansTeamName': '甲的粉团',
    'teamName': '甲的粉团',
    'teamExists': true,
    'fansLevel': 3,
    'level': 3,
    'intimacy': 66,
    'joined': true,
    'isJoin': true,
    'providerInvocation': false,
  },
  '/app-api/room/radio/v1/queryFansTeamTaskPage' => <String, Object?>{
    'list': <Object?>[_guardianTaskRow],
    'records': <Object?>[_guardianTaskRow],
    'total': 1,
    'anchorUserId': 88,
    'roomId': 'room-88',
    'fansTeamId': 'fans-88',
    'fansTeamName': '甲的粉团',
    'teamExists': true,
    'joined': true,
    'isJoin': true,
    'providerInvocation': false,
  },
  _ => <String, Object?>{},
};

const Map<String, Object?> _guardianTaskRow = <String, Object?>{
  'taskId': 201,
  'id': 201,
  'taskCode': 'FANS_STAY',
  'taskName': '陪伴主播',
  'title': '陪伴主播',
  'description': '陪伴主播',
  'taskDesc': '陪伴主播',
  'currentValue': 2,
  'progress': 2,
  'targetValue': 5,
  'target': 5,
  'rewardDesc': '1积分',
  'reward': '1积分',
  'isReceive': true,
  'claimed': true,
  'status': 2,
  'businessDate': '2026-08-23',
};
