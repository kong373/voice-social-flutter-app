import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';

void main() {
  testWidgets('rejected real-name form cannot submit after account ABA', (
    tester,
  ) async {
    final compliance = _Compliance(VerificationState.rejected);
    final dependencies = _dependencies(compliance);
    addTearDown(dependencies.dispose);
    await dependencies.sessionManager.save(_session());
    await tester.pumpWidget(
      _page(
        dependencies,
        const RealNamePage(account: 'test', currentVersion: 6, platformType: 1),
      ),
    );
    await _settle(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '测试用户');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      '110101199001010010',
    );
    await dependencies.sessionManager.clear();
    await dependencies.sessionManager.save(_session());
    await tester.tap(find.text('提交认证'));
    await _settle(tester);
    expect(compliance.submissions, 0);
  });

  testWidgets(
    'REJECTED real-name submission is immediately available and becomes pending',
    (tester) async {
      final compliance = _Compliance(VerificationState.rejected);
      final dependencies = _dependencies(compliance);
      addTearDown(dependencies.dispose);
      await tester.pumpWidget(
        _page(
          dependencies,
          const RealNamePage(
            account: 'test',
            currentVersion: 6,
            platformType: 1,
          ),
        ),
      );
      await _settle(tester);
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.enterText(find.byType(TextFormField).at(0), '测试用户');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '110101199001010010',
      );
      await tester.tap(find.text('提交认证'));
      await _settle(tester);
      expect(compliance.submissions, 1);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('审核中'), findsOneWidget);
    },
  );

  for (final state in [
    VerificationState.unverified,
    VerificationState.rejected,
    VerificationState.pending,
  ]) {
    testWidgets(
      '$state cannot POST a guild application and receives the real-name guide',
      (tester) async {
        await _guild(tester, _Compliance(state), (dependencies, http) async {
          await tester.tap(find.text('申请加入'));
          await _settle(tester);
          expect(http.applications, 0);
          if (state == VerificationState.pending) {
            expect(find.text('实名审核中，请审核通过后再申请加入公会'), findsOneWidget);
            expect(find.text('去实名认证'), findsNothing);
          } else {
            expect(find.text('去实名认证'), findsOneWidget);
            await tester.tap(find.text('去实名认证'));
            await _settle(tester);
            expect(find.byType(RealNamePage), findsOneWidget);
            expect(find.byType(TextFormField), findsNWidgets(2));
            expect(http.applications, 0);
          }
        });
      },
    );
  }

  testWidgets(
    'verified account explicitly submits once without duplicate pending taps',
    (tester) async {
      await _guild(tester, _Compliance(VerificationState.verified), (
        dependencies,
        http,
      ) async {
        await tester.tap(find.text('申请加入'));
        await tester.tap(find.text('申请加入'));
        await _settle(tester);
        expect(http.applications, 1);
        expect(find.text('入会申请已提交'), findsOneWidget);
      });
    },
  );

  for (final mode in ['unavailable', 'restricted', 'youth']) {
    testWidgets('$mode account status never permits an application', (
      tester,
    ) async {
      final compliance =
          _Compliance(
              mode == 'unavailable'
                  ? VerificationState.unavailable
                  : VerificationState.verified,
            )
            ..usable = mode != 'restricted'
            ..locked = mode == 'youth';
      await _guild(tester, compliance, (dependencies, http) async {
        await tester.tap(find.text('申请加入'));
        await _settle(tester);
        expect(http.applications, 0);
        expect(find.text('入会申请已提交'), findsNothing);
      });
    });
  }

  testWidgets(
    'late verified result after account ABA cannot send an application',
    (tester) async {
      final compliance = _Compliance(VerificationState.verified)
        ..pause = Completer<void>();
      await _guild(tester, compliance, (dependencies, http) async {
        await tester.tap(find.text('申请加入'));
        await tester.pump();
        await dependencies.sessionManager.clear();
        await dependencies.sessionManager.save(_session());
        compliance.pause!.complete();
        await _settle(tester);
        expect(http.applications, 0);
        expect(find.text('入会申请已提交'), findsNothing);
      });
    },
  );

  testWidgets(
    'server real-name revocation after preflight guides without replay',
    (tester) async {
      await _guild(tester, _Compliance(VerificationState.verified), (
        dependencies,
        http,
      ) async {
        http.denialCode = 40368;
        await tester.tap(find.text('申请加入'));
        await _settle(tester);
        expect(http.applications, 1);
        expect(find.text('去实名认证'), findsOneWidget);
        expect(find.text('入会申请已提交'), findsNothing);
      });
    },
  );

  testWidgets(
    'known-underage denial is not success or an automatic real-name retry',
    (tester) async {
      await _guild(tester, _Compliance(VerificationState.verified), (
        dependencies,
        http,
      ) async {
        http.denialCode = 40369;
        await tester.tap(find.text('申请加入'));
        await _settle(tester);
        expect(http.applications, 1);
        expect(find.text('未满18岁暂不能加入公会'), findsOneWidget);
        expect(find.text('去实名认证'), findsNothing);
        expect(find.text('入会申请已提交'), findsNothing);
      });
    },
  );
}

AuthSession _session() => AuthSession(
  accessToken: 'q02-test-token',
  tokenType: 'Bearer',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  userId: 20,
  mobile: 'test',
  roles: 'USER',
);
AppDependencies _dependencies(_Compliance compliance) =>
    AppDependencies.forTestEnvironment(
      environment: const AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: 'https://q02.test',
        clientType: 'Android',
        clientInnerVersion: '6',
        oauthClientId: 'test',
        realtimeEndpoint: '',
      ),
      accountComplianceRepository: compliance,
    );
Widget _page(AppDependencies dependencies, Widget child) => AppDependencyScope(
  dependencies: dependencies,
  child: MaterialApp(home: child),
);

Future<void> _guild(
  WidgetTester tester,
  _Compliance compliance,
  Future<void> Function(AppDependencies, _Http) action,
) async {
  final http = _Http();
  await HttpOverrides.runZoned(() async {
    final dependencies = _dependencies(compliance);
    await dependencies.sessionManager.save(_session());
    await tester.pumpWidget(
      _page(dependencies, const GuildDetailPage(guildId: 'guild')),
    );
    await _settle(tester);
    expect(find.text('申请加入'), findsOneWidget);
    try {
      await action(dependencies, http);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      dependencies.dispose();
    }
  }, createHttpClient: (_) => http);
}

Future<void> _settle(WidgetTester tester) async {
  // HttpOverrides uses the same real async stream boundary as existing live UI tests.
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _Compliance extends MockAccountComplianceRepository {
  _Compliance(this.state);
  VerificationState state;
  bool usable = true;
  bool locked = false;
  int submissions = 0;
  Completer<void>? pause;
  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    int? expectedUserId,
    required int currentVersion,
    required int platformType,
  }) async {
    await pause?.future;
    return (await super.fetchSnapshot(
      account: account,
      expectedUserId: expectedUserId,
      currentVersion: currentVersion,
      platformType: platformType,
    )).copyWith(
      verificationState: state,
      accountUsable: usable,
      youthModeEnabled: locked,
    );
  }

  @override
  Future<void> submitRealName({
    required String realName,
    required String idNumber,
  }) async {
    submissions++;
    state = VerificationState.pending;
  }
}

class _Http implements HttpClient {
  int applications = 0;
  int? denialCode;
  @override
  void close({bool force = false}) {}
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _Request(() {
        final apply = url.path.endsWith('/applyForMembership');
        if (apply) applications++;
        final code = apply ? denialCode : null;
        return _Response(
          code ?? 200,
          code == 40369 ? '未满18岁暂不能加入公会' : '完成实名认证后才能申请或批准加入公会',
          apply
              ? {
                  'applicationId': 'application',
                  'guildId': 'guild',
                  'status': 'PENDING',
                }
              : {
                  'guildId': 'guild',
                  'guildName': '测试公会',
                  'name': '测试公会',
                  'status': 'ACTIVE',
                  'viewerRole': 'NONE',
                  'joined': false,
                  'roomId': '',
                  'roomCode': '',
                  'roomName': '',
                  'code': 'GUILD',
                  'artwork': '',
                  'ownerAvatar': '',
                  'ownerUserId': 10,
                  'ownerName': '会长',
                  'memberCount': 1,
                  'onlineUsers': 0,
                  'introduction': '',
                  'hasNewApplications': false,
                  'applicationPending': applications > 0 && denialCode == null,
                  'createdAt': '2026-09-10T00:00:00Z',
                  'updatedAt': '2026-09-10T00:00:00Z',
                },
        );
      });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final HttpClientResponse Function() response;
  @override
  final HttpHeaders headers = _Headers();
  @override
  void write(Object? object) {}
  @override
  Future<HttpClientResponse> close() async => response();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends StreamView<List<int>> implements HttpClientResponse {
  _Response(this.code, String message, Object data)
    : super(
        Stream.value(
          utf8.encode(
            jsonEncode({'code': code, 'message': message, 'data': data}),
          ),
        ),
      );
  final int code;
  @override
  int get statusCode => code == 200 ? 200 : 403;
  @override
  final HttpHeaders headers = _Headers();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
