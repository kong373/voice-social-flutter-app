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

void main() {
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

  testWidgets('live UI preserves unavailable guild authority and CP days', (
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

      await pumpPage(const CpRelationPage());
      expect(find.text('已相伴 2 天'), findsOneWidget);
      expect(find.text('相伴天数未知'), findsNothing);
      expect(find.text('建立于 2026-08-22T00:00:00Z'), findsOneWidget);
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
      expect(find.text('成员与管理'), findsNothing);
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
  'status': 'CLOSED',
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
