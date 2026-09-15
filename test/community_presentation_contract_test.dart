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
import 'support/media_http_fakes.dart';

void main() {
  _guildPageRaceTests();
  testWidgets(
    'live legacy ADMIN is a host with quit but no governance or transfer controls',
    (tester) async {
      final overrides = _ContractHttpOverrides();
      await HttpOverrides.runZoned(() async {
        final dependencies = AppDependencies.forTestEnvironment(
          environment: AppEnvironment(
            backendMode: BackendMode.live,
            apiBaseUrl: 'https://community.test/',
            clientType: 'Android',
            clientInnerVersion: '6',
            oauthClientId: 'public-test-client',
            realtimeEndpoint: '',
          ),
        );
        addTearDown(dependencies.dispose);
        await dependencies.sessionManager.save(
          AuthSession(
            accessToken: 'test-legacy-admin',
            tokenType: 'Bearer',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            userId: 10001,
            mobile: 'test',
            roles: 'USER',
          ),
        );
        Future<void> pumpPage(Widget page) async {
          await tester.pumpWidget(
            AppDependencyScope(
              dependencies: dependencies,
              child: MaterialApp(theme: AppTheme.social(), home: page),
            ),
          );
          for (var index = 0; index < 5; index++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump(const Duration(milliseconds: 30));
          }
        }

        await pumpPage(const GuildDetailPage(guildId: 'guild-active-admin'));
        expect(find.textContaining('你是主播'), findsOneWidget);
        expect(find.text('退出公会'), findsOneWidget);
        expect(find.text('名下房间'), findsNothing);
        expect(find.textContaining('解散'), findsNothing);
        expect(find.textContaining('转让'), findsNothing);
        await pumpPage(const GuildMembersPage(guildId: 'guild-active-admin'));
        expect(find.byType(PopupMenuButton<String>), findsNothing);
        expect(find.byType(SegmentedButton<int>), findsNothing);
        expect(find.text('管理员'), findsNothing);
        expect(
          overrides.requests.where(
            (uri) => uri.path.endsWith('getMembershipApplications'),
          ),
          isEmpty,
        );
        expect(
          overrides.requests.where(
            (uri) => uri.path.contains('guildManagement'),
          ),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      }, createHttpClient: overrides.createHttpClient);
    },
  );

  testWidgets('guild applications expose state and only pending actions', (
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
          home: const GuildMembersEntryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('申请 2'));
    await tester.pumpAndSettle();

    expect(find.text('待审核'), findsNWidgets(2));
    expect(find.text('已通过'), findsOneWidget);
    expect(find.text('已拒绝'), findsOneWidget);
    expect(find.text('已过期'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '拒绝'), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, '通过'), findsNWidgets(2));
  });

  testWidgets('live UI preserves unavailable guild authority', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _ContractHttpOverrides overrides = _ContractHttpOverrides();
    await HttpOverrides.runZoned(() async {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        mockNow: DateTime(2026, 9, 7),
        environment: AppEnvironment(
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
          accessToken: 'community-presentation-token',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          userId: 10001,
          mobile: 'test-user',
          roles: 'USER',
        ),
      );

      Future<void> pumpPage(Widget page) async {
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(theme: AppTheme.social(), home: page),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        for (int index = 0; index < 5; index += 1) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      await pumpPage(const GuildHomePage());
      expect(
        find.text('当前公会信息暂不可用'),
        findsOneWidget,
        reason:
            tester
                .widgetList<Text>(find.byType(Text))
                .map((Text value) => value.data)
                .join('|') +
            '\nrequests=${overrides.requests.map((Uri uri) => uri.path).join(',')}',
      );
      expect(find.textContaining('当前没有加入公会'), findsNothing);
      expect(find.text('公会编号未提供  ·  12 人'), findsOneWidget);

      await pumpPage(const GuildMembersEntryPage());
      expect(find.text('当前公会信息暂不可用'), findsOneWidget);
      expect(find.text('尚未加入公会'), findsNothing);
    }, createHttpClient: overrides.createHttpClient);
  });

  testWidgets('closed guild detail is explicit and read only', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final _ContractHttpOverrides overrides = _ContractHttpOverrides();
    await HttpOverrides.runZoned(() async {
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: AppEnvironment(
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
          accessToken: 'community-closed-guild-token',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          userId: 10001,
          mobile: 'test-user',
          roles: 'USER',
        ),
      );

      Future<void> pumpGuild(String guildId) async {
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: AppTheme.social(),
              home: GuildDetailPage(
                key: ValueKey<String>(guildId),
                guildId: guildId,
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
        for (int index = 0; index < 5; index += 1) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      await pumpGuild('guild-closed-visitor');
      expect(find.text('公会已关闭'), findsOneWidget);
      expect(find.text('申请加入'), findsNothing);

      await pumpGuild('guild-closed-admin');
      expect(find.text('公会已关闭'), findsOneWidget);
      expect(find.text('公会签到'), findsNothing);
      expect(find.text('公会主播'), findsNothing);
      expect(find.text('退出公会'), findsNothing);
      final Iterable<InkWell> roomCards = tester.widgetList<InkWell>(
        find.ancestor(of: find.text('已关闭公会房间'), matching: find.byType(InkWell)),
      );
      expect(roomCards, isNotEmpty);
      expect(roomCards.every((InkWell card) => card.onTap == null), isTrue);

      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            theme: AppTheme.social(),
            home: const GuildMembersPage(
              key: ValueKey<String>('guild-closed-members'),
              guildId: 'guild-closed-admin',
            ),
          ),
        ),
      );
      for (int index = 0; index < 3; index += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.text('公会已关闭'),
        findsOneWidget,
        reason:
            tester
                .widgetList<Text>(find.byType(Text))
                .map((Text value) => value.data)
                .join('|') +
            '\nrequests=${overrides.requests.map((Uri uri) => uri.path).join(',')}',
      );
      expect(find.byType(SegmentedButton<int>), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(
        overrides.requests.where(
          (Uri uri) => uri.path == '/app-api/guild/getMembershipApplications',
        ),
        isEmpty,
      );
    }, createHttpClient: overrides.createHttpClient);
  });
}

class _ContractHttpOverrides extends HttpOverrides {
  final List<Uri> requests = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ContractHttpClient(requests);
}

class _ContractHttpClient implements HttpClient {
  _ContractHttpClient(this.requests);

  final List<Uri> requests;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requests.add(url);
    return _ContractHttpClientRequest(url);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ContractHttpClientRequest implements HttpClientRequest {
  _ContractHttpClientRequest(this.url);

  final Uri url;

  @override
  final HttpHeaders headers = _ContractHttpHeaders();

  @override
  void write(Object? object) {}

  @override
  Future<HttpClientResponse> close() async =>
      _ContractHttpClientResponse(_communityResponseData(url));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ContractHttpHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ContractHttpClientResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _ContractHttpClientResponse(Object? data)
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
  final HttpHeaders headers = _ContractHttpHeaders();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Object? _communityResponseData(Uri url) => switch (url.path) {
  '/app-api/guild/getCurrentGuild' => <String, Object?>{
    'currentGuildAuthority': 'UNAVAILABLE',
    'authority': 'UNAVAILABLE',
    'available': false,
    'fabricated': false,
    'membershipStatus': 'UNAVAILABLE',
    'currentGuild': null,
    'currentGuildId': '',
  },
  '/app-api/guild/getGuildHomepageDetails' => _closedGuildDetail(
    url.queryParameters['guildId'] ?? '',
  ),
  '/app-api/guild/getGuildMembers' => <String, Object?>{
    'list': <Object?>[
      <String, Object?>{
        'userId': 21,
        'nickName': '历史成员',
        'headImgUrl': '',
        'signature': '',
        'role': 'MEMBER',
        'muted': false,
        'isSigned': false,
        'roomId': '',
        'joinedAt': '2026-08-01T00:00:00Z',
      },
    ],
    'records': <Object?>[
      <String, Object?>{
        'userId': 21,
        'nickName': '历史成员',
        'headImgUrl': '',
        'signature': '',
        'role': 'MEMBER',
        'muted': false,
        'isSigned': false,
        'roomId': '',
        'joinedAt': '2026-08-01T00:00:00Z',
      },
    ],
    'current': 1,
    'pageSize': 50,
    'total': 1,
    'pages': 1,
  },
  '/app-api/guild/getRecommendGuildPage' => <String, Object?>{
    'list': <Object?>[
      <String, Object?>{
        'guildId': 'guild-live-1',
        'code': '',
        'guildName': '星河公会',
        'name': '星河公会',
        'introduction': '真实公会简介',
        'ownerUserId': 7,
        'ownerName': '会长',
        'ownerAvatar': '',
        'artwork': '',
        'status': 'ACTIVE',
        'memberCount': 12,
        'onlineUsers': 0,
        'hasNewApplications': false,
        'viewerRole': 'NONE',
        'joined': false,
        'roomId': 'room-live-1',
        'roomCode': '880217',
        'roomName': '星河房间',
        'createdAt': '2026-08-01T00:00:00Z',
        'updatedAt': '2026-08-20T00:00:00Z',
      },
    ],
    'records': <Object?>[
      <String, Object?>{
        'guildId': 'guild-live-1',
        'code': '',
        'guildName': '星河公会',
        'name': '星河公会',
        'introduction': '真实公会简介',
        'ownerUserId': 7,
        'ownerName': '会长',
        'ownerAvatar': '',
        'artwork': '',
        'status': 'ACTIVE',
        'memberCount': 12,
        'onlineUsers': 0,
        'hasNewApplications': false,
        'viewerRole': 'NONE',
        'joined': false,
        'roomId': 'room-live-1',
        'roomCode': '880217',
        'roomName': '星河房间',
        'createdAt': '2026-08-01T00:00:00Z',
        'updatedAt': '2026-08-20T00:00:00Z',
      },
    ],
    'current': 1,
    'pageSize': 50,
    'total': 1,
    'pages': 1,
  },
  '/app-mini-api/mini/v1/cp/my-list' => <String, Object?>{
    'list': <Object?>[
      <String, Object?>{
        'cpRelationId': 'cp-live-1',
        'userId': 31,
        'nickName': '星河',
        'headImgUrl': '',
        'status': 'ACTIVE',
        'days': 2,
        'createdAt': '2026-08-22T00:00:00Z',
      },
    ],
    'records': <Object?>[
      <String, Object?>{
        'cpRelationId': 'cp-live-1',
        'userId': 31,
        'nickName': '星河',
        'headImgUrl': '',
        'status': 'ACTIVE',
        'days': 2,
        'createdAt': '2026-08-22T00:00:00Z',
      },
    ],
    'current': 1,
    'pageSize': 20,
    'total': 1,
    'pages': 1,
  },
  '/app-mini-api/mini/v1/cp/pending-requests' => <String, Object?>{
    'list': <Object?>[],
    'records': <Object?>[],
    'current': 1,
    'pageSize': 20,
    'total': 0,
    'pages': 0,
  },
  _ => <String, Object?>{},
};

Map<String, Object?> _closedGuildDetail(String guildId) => <String, Object?>{
  'guildId': guildId,
  'code': 'CLOSED001',
  'guildName': '已关闭公会',
  'name': '已关闭公会',
  'introduction': '历史公会资料仅供查看',
  'ownerUserId': 7,
  'ownerName': '原会长',
  'ownerAvatar': '',
  'artwork': '',
  'status': guildId.contains('active') ? 'ACTIVE' : 'CLOSED',
  'memberCount': 12,
  'onlineUsers': 0,
  'hasNewApplications': false,
  'viewerRole': guildId.endsWith('admin') ? 'ADMIN' : 'NONE',
  'joined': guildId.endsWith('admin'),
  'roomId': 'closed-room-1',
  'roomCode': '880217',
  'roomName': '已关闭公会房间',
  'createdAt': '2026-08-01T00:00:00Z',
  'updatedAt': '2026-08-20T00:00:00Z',
  'signedToday': false,
  'applicationPending': false,
  'businessDate': '2026-08-24',
};

// These tests exercise live pages -> BackendCommunityRepository -> ApiClient.
// Only HTTP responses are controlled; no page state or repository result is mocked.
void _guildPageRaceTests() {
  testWidgets('G3 old PENDING cannot replace post-approval APPROVED', (tester) async {
    final write = Completer<HttpClientResponse>();
    final stale = Completer<HttpClientResponse>();
    var applicationReads = 0;
    var approved = false;
    _releaseGuildGateOnTearDown(write);
    _releaseGuildGateOnTearDown(stale);
    final http = _GuildUiHttp((request) {
      if (request.uri.path.endsWith('approvalMembershipApplication')) return write.future;
      if (request.uri.path.endsWith('getMembershipApplications') && ++applicationReads == 2) {
        return stale.future;
      }
      return MediaFakeResponse.json(_guildUiData(request, approved: approved));
    });
    await _withGuildUi(tester, http, (dependencies) async {
      await _mountGuildUi(tester, dependencies, const GuildMembersPage(guildId: 'guild-a'));
      expect(find.text('申请 1'), findsOneWidget, reason: 'Fixture must finish initial HTTP loading');
      await tester.tap(find.text('申请 1'));
      await _pumpGuildUi(tester, until: () => find.widgetWithText(FilledButton, '通过').evaluate().isNotEmpty);
      final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
      await tester.tap(find.widgetWithText(FilledButton, '通过'));
      await _pumpGuildUi(tester, until: () => http.requests.any((r) => r.uri.path.endsWith('approvalMembershipApplication')));
      expect(http.requests.where((r) => r.uri.path.endsWith('approvalMembershipApplication')), hasLength(1));
      final oldRead = refresh();
      await _pumpGuildUi(tester, until: () => applicationReads == 2);
      expect(applicationReads, 2);
      approved = true;
      write.complete(MediaFakeResponse.json({
        'applicationId': 'application-1', 'guildId': 'guild-a', 'status': 'APPROVED',
      }));
      await _pumpGuildUi(tester, until: () => find.text('已通过').evaluate().isNotEmpty);
      expect(find.text('已通过'), findsOneWidget);
      expect(find.text('待审核'), findsNothing);
      stale.complete(MediaFakeResponse.json(_guildUiApplications(false)));
      await _finishGuildUi(tester, oldRead);
      expect(find.text('已通过'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '通过'), findsNothing);
      expect(applicationReads, 3);
      expect(http.requests.where((r) => r.uri.path.contains('guildManagement')), hasLength(1));
    });
  });

  testWidgets('G3 quit readback wins and a later legitimate rejoin is not cached out', (tester) async {
    final write = Completer<HttpClientResponse>();
    final stale = Completer<HttpClientResponse>();
    _releaseGuildGateOnTearDown(write);
    _releaseGuildGateOnTearDown(stale);
    var reads = 0;
    var joined = true;
    final http = _GuildUiHttp((request) {
      if (request.uri.path.endsWith('quitGuild')) return write.future;
      if (request.uri.path.endsWith('getGuildHomepageDetails') && ++reads == 2) return stale.future;
      return MediaFakeResponse.json(_guildUiData(request, role: joined ? 'MEMBER' : 'NONE'));
    });
    await _withGuildUi(tester, http, (dependencies) async {
      await _mountGuildUi(tester, dependencies, const GuildDetailPage(guildId: 'guild-a'));
      expect(find.text('退出公会'), findsOneWidget, reason: 'Fixture must finish initial HTTP loading');
      final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
      await tester.tap(find.text('退出公会'));
      await _pumpGuildUi(tester, until: () => find.text('确认退出').evaluate().isNotEmpty);
      await tester.tap(find.text('确认退出'));
      await _pumpGuildUi(tester, until: () => http.requests.any((r) => r.uri.path.endsWith('quitGuild')));
      final oldRead = refresh();
      await _pumpGuildUi(tester, until: () => reads == 2);
      expect(reads, 2);
      joined = false;
      write.complete(MediaFakeResponse.json({'guildId': 'guild-a', 'status': 'LEFT', 'left': true}));
      await _pumpGuildUi(tester, until: () => find.text('尚未加入').evaluate().isNotEmpty);
      expect(find.text('尚未加入'), findsOneWidget);
      stale.complete(MediaFakeResponse.json(_guildUiDetail('guild-a', role: 'MEMBER')));
      await _finishGuildUi(tester, oldRead);
      expect(find.text('退出公会'), findsNothing);
      expect(find.text('尚未加入'), findsOneWidget);
      joined = true;
      await _finishGuildUi(tester, tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh());
      expect(find.textContaining('你是主播'), findsOneWidget);
      expect(http.requests.where((r) => r.uri.path.contains('guildManagement')), hasLength(1));
    });
  });

  for (final oldError in [false, true]) {
    for (final newestFirst in [false, true]) {
      testWidgets('G3 stale detail error=$oldError newestFirst=$newestFirst cannot end new loading', (tester) async {
        final old = Completer<HttpClientResponse>();
        final latest = Completer<HttpClientResponse>();
        _releaseGuildGateOnTearDown(old);
        _releaseGuildGateOnTearDown(latest);
        var calls = 0;
        final http = _GuildUiHttp((request) {
          if (request.uri.path.endsWith('getGuildHomepageDetails')) {
            calls++;
            if (calls == 2) return old.future;
            if (calls == 3) return latest.future;
          }
          return MediaFakeResponse.json(_guildUiData(request));
        });
        await _withGuildUi(tester, http, (dependencies) async {
          await _mountGuildUi(tester, dependencies, const GuildDetailPage(guildId: 'guild-a'));
          final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
          final prior = refresh();
          await _pumpGuildUi(tester, until: () => calls == 2);
          final current = refresh();
          await _pumpGuildUi(tester, until: () => calls == 3);
          expect(calls, 3);
          if (newestFirst) {
            latest.complete(MediaFakeResponse.json(_guildUiDetail('guild-a', name: 'CURRENT')));
            await _finishGuildUi(tester, current);
          }
          if (oldError) {
            old.completeError(const SocketException('obsolete guild error'));
          } else {
            old.complete(MediaFakeResponse.json(_guildUiDetail('guild-a', name: 'OBSOLETE')));
          }
          await _finishGuildUi(tester, prior);
          if (!newestFirst) {
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
            expect(find.text('OBSOLETE'), findsNothing);
            latest.complete(MediaFakeResponse.json(_guildUiDetail('guild-a', name: 'CURRENT')));
            await _finishGuildUi(tester, current);
          }
          expect(find.text('CURRENT'), findsOneWidget);
          expect(find.text('OBSOLETE'), findsNothing);
          expect(find.textContaining('obsolete guild error'), findsNothing);
        });
      });
    }
  }

  for (final stage in ['getGuildHomepageDetails', 'getGuildMembers']) {
    testWidgets('G3 guildId change stops obsolete multi-stage read after $stage', (tester) async {
      final old = Completer<HttpClientResponse>();
      _releaseGuildGateOnTearDown(old);
      MediaFakeRequest? held;
      final http = _GuildUiHttp((request) {
        if (_guildUiId(request) == 'guild-a' && request.uri.path.endsWith(stage)) {
          held = request;
          return old.future;
        }
        return MediaFakeResponse.json(_guildUiData(request));
      });
      await _withGuildUi(tester, http, (dependencies) async {
        await _mountGuildUi(tester, dependencies, const GuildMembersPage(key: ValueKey('members'), guildId: 'guild-a'), ready: () => held != null);
        expect(held, isNotNull);
        await _mountGuildUi(tester, dependencies, const GuildMembersPage(key: ValueKey('members'), guildId: 'guild-b'));
        expect(find.text('公会 guild-b'), findsOneWidget);
        old.complete(MediaFakeResponse.json(_guildUiData(held!)));
        await _pumpGuildUi(tester);
        expect(find.text('公会 guild-b'), findsOneWidget);
        expect(http.requests.where((r) => _guildUiId(r) == 'guild-a' &&
            r.uri.path.endsWith('getMembershipApplications')), isEmpty);
        if (stage == 'getGuildHomepageDetails') {
          expect(http.requests.where((r) => _guildUiId(r) == 'guild-a' &&
              r.uri.path.endsWith('getGuildMembers')), isEmpty);
        }
      });
    });
  }

  testWidgets('G3 changed repository invalidates the same mounted guild page', (tester) async {
    final old = Completer<HttpClientResponse>();
    _releaseGuildGateOnTearDown(old);
    MediaFakeRequest? held;
    final http = _GuildUiHttp((request) {
      if (request.uri.host == 'guild-a.test' && request.uri.path.endsWith('getGuildHomepageDetails')) {
        held = request;
        return old.future;
      }
      return MediaFakeResponse.json(_guildUiData(request, name: 'NEW REPOSITORY'));
    });
    await _withGuildUi(tester, http, (dependencies) async {
      const page = GuildMembersPage(key: ValueKey('same'), guildId: 'guild-a');
      await _mountGuildUi(tester, dependencies, page, ready: () => held != null);
      expect(held, isNotNull);
      final replacement = await _guildUiDependencies('guild-b.test');
      try {
        await _mountGuildUi(tester, replacement, page);
        expect(find.text('NEW REPOSITORY'), findsOneWidget);
        old.complete(MediaFakeResponse.json(_guildUiData(held!)));
        await _pumpGuildUi(tester);
        expect(find.text('NEW REPOSITORY'), findsOneWidget);
        expect(http.requests.where((r) => r.uri.host == 'guild-a.test'), hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        replacement.dispose();
      }
    });
  });

  testWidgets('G3 disposed members page does not start the next read stage', (tester) async {
    final old = Completer<HttpClientResponse>();
    _releaseGuildGateOnTearDown(old);
    MediaFakeRequest? held;
    final http = _GuildUiHttp((request) {
      held = request;
      return old.future;
    });
    await _withGuildUi(tester, http, (dependencies) async {
      await _mountGuildUi(tester, dependencies, const GuildMembersPage(guildId: 'guild-a'), ready: () => held != null);
      expect(held, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      old.complete(MediaFakeResponse.json(_guildUiData(held!)));
      await _pumpGuildUi(tester);
      expect(http.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('G3 old search catch and finally cannot unlock new repository search', (tester) async {
    final old = Completer<HttpClientResponse>();
    final current = Completer<HttpClientResponse>();
    _releaseGuildGateOnTearDown(old);
    _releaseGuildGateOnTearDown(current);
    MediaFakeRequest? newSearch;
    final http = _GuildUiHttp((request) {
      if (request.uri.path.endsWith('searchGuild')) {
        if (request.uri.host == 'guild-a.test') return old.future;
        newSearch = request;
        return current.future;
      }
      return MediaFakeResponse.json(_guildUiData(request));
    });
    await _withGuildUi(tester, http, (dependencies) async {
      const page = GuildHomePage(key: ValueKey('same-home'));
      await _mountGuildUi(tester, dependencies, page);
      await tester.enterText(find.byType(TextField), 'old');
      await tester.tap(find.byTooltip('搜索'));
      await _pumpGuildUi(tester, until: () => http.requests.any((r) => r.uri.host == 'guild-a.test' && r.uri.path.endsWith('searchGuild')));
      final replacement = await _guildUiDependencies('guild-b.test');
      try {
        await _mountGuildUi(tester, replacement, page);
        await tester.enterText(find.byType(TextField), 'new');
        await tester.tap(find.byTooltip('搜索'));
        await _pumpGuildUi(tester, until: () => newSearch != null);
        expect(newSearch, isNotNull);
        old.completeError(const SocketException('obsolete search'));
        await _pumpGuildUi(tester);
        expect(tester.widget<IconButton>(find.byTooltip('搜索')).onPressed, isNull);
        expect(find.textContaining('obsolete search'), findsNothing);
        current.complete(MediaFakeResponse.json(_guildUiData(newSearch!)));
        await _pumpGuildUi(tester, until: () => find.text('搜索结果').evaluate().isNotEmpty);
        expect(tester.widget<IconButton>(find.byTooltip('搜索')).onPressed, isNotNull);
        expect(find.text('搜索结果'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        replacement.dispose();
      }
    });
  });
}

class _GuildUiHttp extends MediaFakeHttp {
  _GuildUiHttp(super.respond);
  @override
  Duration idleTimeout = const Duration(seconds: 2);
  @override
  void close({bool force = false}) {}
}

void _releaseGuildGateOnTearDown(Completer<HttpClientResponse> gate) {
  addTearDown(() {
    if (!gate.isCompleted) gate.complete(MediaFakeResponse.json(null, status: 503, code: 50301));
  });
}

Future<AppDependencies> _guildUiDependencies(String host) async {
  final dependencies = AppDependencies.forTestEnvironment(
    environment: AppEnvironment(
      backendMode: BackendMode.live,
      apiBaseUrl: 'https://$host/',
      clientType: 'Android',
      clientInnerVersion: '6',
      oauthClientId: 'public-test-client',
      realtimeEndpoint: '',
    ),
  );
  await dependencies.sessionManager.save(AuthSession(
    accessToken: 'guild-contract-only', tokenType: 'Bearer',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    userId: 10001, mobile: 'test-user', roles: 'USER',
  ));
  return dependencies;
}

Future<void> _withGuildUi(
  WidgetTester tester,
  _GuildUiHttp http,
  Future<void> Function(AppDependencies) run,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await HttpOverrides.runZoned(() async {
    final dependencies = await _guildUiDependencies('guild-a.test');
    try {
      await run(dependencies);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
    }
  }, createHttpClient: (_) => http);
}

Future<void> _mountGuildUi(WidgetTester tester, AppDependencies dependencies, Widget page, {bool Function()? ready}) async {
  await tester.pumpWidget(AppDependencyScope(
    dependencies: dependencies,
    child: MaterialApp(theme: AppTheme.social(), home: page),
  ));
  // Tests that deliberately hold the first response supply a request barrier.
  // Otherwise require a loaded refreshable page, not merely N elapsed frames.
  await _pumpGuildUi(tester, until: ready ?? () => find.byType(RefreshIndicator).evaluate().isNotEmpty);
}

Future<void> _finishGuildUi(WidgetTester tester, Future<void> operation) async {
  var finished = false;
  Object? failure;
  operation.then<void>((_) => finished = true, onError: (Object error, StackTrace _) {
    failure = error;
    finished = true;
  });
  await _pumpGuildUi(tester, until: () => finished);
  if (failure != null) throw failure!;
  await tester.pump();
}

Future<void> _pumpGuildUi(WidgetTester tester, {bool Function()? until}) async {
  // HTTP futures/streams need the real event loop as well as widget frames.
  // Never pumpAndSettle while a deliberately held response owns a spinner.
  for (var index = 0; index < 200; index++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 10));
    if (until != null ? until() : index >= 11) return;
  }
  fail('Guild async fixture did not reach its request/UI barrier; not a business RED.');
}

String _guildUiId(MediaFakeRequest request) {
  if (request.uri.queryParameters.containsKey('guildId')) return request.uri.queryParameters['guildId']!;
  if (request.body.isNotEmpty) {
    final body = jsonDecode(utf8.decode(request.body)) as Map<String, dynamic>;
    if (body['guildId'] is String) return body['guildId'] as String;
  }
  return 'guild-a';
}

Map<String, Object?> _guildUiDetail(String id, {String role = 'OWNER', String? name}) => {
  ..._closedGuildDetail(id),
  'guildName': name ?? '公会 $id', 'name': name ?? '公会 $id',
  'status': 'ACTIVE', 'ownerUserId': 10001, 'viewerRole': role,
  'joined': role != 'NONE', 'roomId': '', 'roomCode': '', 'roomName': '',
};

Map<String, Object?> _guildUiApplications(bool approved) {
  final rows = <Object?>[<String, Object?>{
    'applicationId': 'application-1', 'userId': 31, 'nickName': '申请人',
    'headImgUrl': '', 'message': '',
    'status': approved ? 'APPROVED' : 'PENDING',
    'createdAt': '2026-09-01T00:00:00Z',
    'resolvedAt': approved ? '2026-09-01T01:00:00Z' : '',
  }];
  return {'list': rows, 'records': rows, 'current': 1, 'pageSize': 50, 'total': 1, 'pages': 1};
}

Object? _guildUiData(MediaFakeRequest request, {bool approved = false, String role = 'OWNER', String? name}) {
  final id = _guildUiId(request);
  if (request.uri.path.endsWith('getGuildHomepageDetails')) return _guildUiDetail(id, role: role, name: name);
  if (request.uri.path.endsWith('getMembershipApplications')) return _guildUiApplications(approved);
  if (request.uri.path.endsWith('searchGuild')) {
    final rows = <Object?>[_guildUiDetail('guild-search', role: 'NONE')];
    return {'list': rows, 'records': rows, 'current': 1, 'pageSize': 50, 'total': 1, 'pages': 1};
  }
  return _communityResponseData(request.uri);
}
