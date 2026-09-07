import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

void main() {
  Future<GlobalKey<NavigatorState>> mount(
    WidgetTester tester,
    _ProfileRepository repository, {
    bool push = true,
  }) async {
    final navigator = GlobalKey<NavigatorState>();
    final page = PersonalCenterPage(session: null, onSignOut: () async {});
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: _Dependencies(repository),
        child: MaterialApp(
          navigatorKey: navigator,
          theme: AppTheme.social(),
          // No test-owned Scaffold or Material around the page or route.
          home: push ? const SizedBox(key: Key('origin')) : page,
        ),
      ),
    );
    if (push) {
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(builder: (_) => page),
        ),
      );
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return navigator;
  }

  testWidgets(
    'pushed personal center supplies Material text and a working back',
    (WidgetTester tester) async {
      final navigator = await mount(tester, _ProfileRepository());
      final Finder settings = find.byTooltip('账号与安全');
      expect(settings, findsOneWidget);
      expect(
        find.ancestor(of: settings, matching: find.byType(Scaffold)),
        findsOneWidget,
      );
      final BuildContext textContext = tester.element(find.text('用户号 10001'));
      expect(Material.maybeOf(textContext), isNotNull);
      expect(
        DefaultTextStyle.of(textContext).style.decoration,
        isNot(TextDecoration.underline),
      );
      expect(find.byTooltip('返回').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(navigator.currentState!.canPop(), isFalse);
      expect(find.byKey(const Key('origin')), findsOneWidget);
      expect(find.byType(PersonalCenterPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final bool error in <bool>[false, true]) {
    testWidgets('${error ? 'error' : 'loading'} state has a working back', (
      WidgetTester tester,
    ) async {
      final pending = Completer<SocialProfile>();
      final repository = _ProfileRepository()..result = pending.future;
      final navigator = await mount(tester, repository);
      if (error) {
        pending.completeError(
          const ApiException(kind: ApiFailureKind.network, message: '资料加载失败'),
        );
        await tester.pumpAndSettle();
        expect(find.text('资料加载失败'), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);
      } else {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
      expect(find.byTooltip('返回').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(navigator.currentState!.canPop(), isFalse);
      expect(find.byKey(const Key('origin')), findsOneWidget);
      if (!error) {
        pending.complete(await MockSocialRepository().fetchMyProfile());
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final bool failure in <bool>[false, true]) {
    testWidgets(
      'pushed page displays clipboard ${failure ? 'failure' : 'success'} feedback',
      (WidgetTester tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            if (call.method == 'Clipboard.setData') {
              if (failure)
                throw PlatformException(code: 'clipboard_unavailable');
              copied =
                  (call.arguments as Map<Object?, Object?>)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await mount(tester, _ProfileRepository());
        await tester.tap(find.text('用户号 10001'));
        await tester.pumpAndSettle();
        expect(copied, failure ? isNull : '10001');
        expect(
          find.text(failure ? '暂时无法复制用户 ID，请重试' : '用户 ID 已复制'),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'root mode has no false back affordance and keeps the settings row',
    (WidgetTester tester) async {
      final navigator = await mount(tester, _ProfileRepository(), push: false);
      expect(navigator.currentState!.canPop(), isFalse);
      expect(find.byTooltip('返回'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('账号与安全'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ProfileRepository extends MockSocialRepository {
  Future<SocialProfile>? result;

  @override
  Future<SocialProfile> fetchMyProfile() => result ?? super.fetchMyProfile();
}

class _Dependencies implements AppDependencies {
  _Dependencies(this.socialRepository);

  @override
  final SocialRepository socialRepository;

  @override
  AppEnvironment get environment => AppEnvironment.mock();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
