import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

const PrivacySettings _settings = PrivacySettings(
  onlyFollowedCanFollow: false,
  serverValueKnown: true,
);
const SocialUser _blockedUser = SocialUser(
  userId: 20004,
  name: '黑名单用户',
  signature: '',
  avatarUrl: '',
  isFollowing: false,
  isFollower: false,
  isFriend: false,
  isBlocked: true,
  isOnline: false,
);
const ApiException _denied = ApiException(
  kind: ApiFailureKind.forbidden,
  message: '无权执行此操作',
);

void main() {
  Future<void> mount(WidgetTester tester, _SocialRepository repository) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: _Dependencies(repository),
        child: MaterialApp(
          theme: AppTheme.social(),
          home: const PrivacyBlacklistPage(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('uses a legal page size and finishes the initial load', (
    WidgetTester tester,
  ) async {
    final repository = _SocialRepository();
    await mount(tester, repository);
    expect(repository.pageSizes, <int>[50]);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('黑名单用户'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reads remaining pages before declaring the blacklist complete', (
    WidgetTester tester,
  ) async {
    final repository = _SocialRepository()
      ..onFetchPage = (int page, int size) async => SocialPage<SocialUser>(
        items: page == 1
            ? List<SocialUser>.filled(50, _blockedUser)
            : <SocialUser>[_blockedUser.copyWith(name: '第二页用户')],
        page: page,
        pageSize: size,
        total: 51,
        hasMore: page == 1,
      );
    await mount(tester, repository);
    expect(repository.pages, <int>[1, 2]);
    expect(repository.pageSizes, everyElement(50));
    expect(find.text('第二页用户'), findsOneWidget);
    expect(find.text('黑名单为空'), findsNothing);
  });

  for (final String failure in <String>[
    'privacy',
    'blacklist',
    'second page',
  ]) {
    testWidgets('$failure failure is retryable and never fakes empty data', (
      WidgetTester tester,
    ) async {
      final repository = _SocialRepository();
      if (failure == 'privacy') {
        repository.onFetchPrivacy = () async => throw _denied;
      } else {
        repository.onFetchPage = (int page, int size) async {
          if (failure == 'blacklist' || page == 2) throw _denied;
          return SocialPage<SocialUser>(
            items: List<SocialUser>.filled(50, _blockedUser),
            page: page,
            pageSize: size,
            total: 51,
            hasMore: true,
          );
        };
      }
      await mount(tester, repository);
      expect(find.text('无权执行此操作'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('黑名单为空'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final int calls = repository.privacyCalls;
      await mount(tester, repository); // Inherited dependency notification.
      expect(repository.privacyCalls, calls);
      repository.onFetchPrivacy = null;
      repository.onFetchPage = null;
      repository.items = <SocialUser>[];
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('黑名单为空'), findsOneWidget);
      expect(find.text('无权执行此操作'), findsNothing);
      expect(repository.privacyCalls, calls + 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dependency changes do not duplicate an in-flight load', (
    WidgetTester tester,
  ) async {
    final pending = Completer<PrivacySettings>();
    final repository = _SocialRepository()
      ..onFetchPrivacy = () => pending.future;
    await mount(tester, repository);
    await mount(tester, repository);
    expect(repository.privacyCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('黑名单为空'), findsNothing);
    pending.complete(_settings);
    await tester.pumpAndSettle();
    expect(find.text('黑名单用户'), findsOneWidget);
  });

  testWidgets(
    'privacy mutation failure preserves unknown value and gives feedback',
    (WidgetTester tester) async {
      final repository = _SocialRepository()
        ..onFetchPrivacy = () async => const PrivacySettings(
          onlyFollowedCanFollow: false,
          serverValueKnown: false,
        );
      repository.onUpdate = (_) async => throw _denied;
      await mount(tester, repository);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('无权执行此操作'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('首次修改后可确认服务端状态'), findsOneWidget);
      expect(repository.updateValues, <bool>[true]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'privacy save is single-flight and adopts only the server value',
    (WidgetTester tester) async {
      final pending = Completer<PrivacySettings>();
      final repository = _SocialRepository()..onUpdate = (_) => pending.future;
      await mount(tester, repository);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '移出'))
            .onPressed,
        isNull,
      );
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      pending.complete(_settings.copyWith(onlyFollowedCanFollow: true));
      await tester.pumpAndSettle();
      expect(repository.updateValues, <bool>[true]);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    },
  );

  testWidgets('unblock failure preserves the row and allows retry', (
    WidgetTester tester,
  ) async {
    final repository = _SocialRepository()
      ..onUnblock = () async => throw _denied;
    await mount(tester, repository);
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    expect(find.text('无权执行此操作'), findsOneWidget);
    expect(find.text('黑名单用户'), findsOneWidget);
    expect(find.text('黑名单为空'), findsNothing);
    repository.onUnblock = () async {
      repository.items = <SocialUser>[];
    };
    await tester.tap(find.text('移出'));
    await tester.pumpAndSettle();
    expect(repository.unblocks, <(int, bool)>[(20004, false), (20004, false)]);
    expect(find.text('黑名单为空'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unblock refresh failure remains an error until a successful retry',
    (WidgetTester tester) async {
      final repository = _SocialRepository();
      repository.onUnblock = () async {
        repository.onFetchPage = (_, _) async => throw _denied;
      };
      await mount(tester, repository);
      await tester.tap(find.text('移出'));
      await tester.pumpAndSettle();
      expect(find.text('无权执行此操作'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('黑名单为空'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a pending load may finish after leaving the page', (
    WidgetTester tester,
  ) async {
    final pending = Completer<PrivacySettings>();
    final repository = _SocialRepository()
      ..onFetchPrivacy = () => pending.future;
    await mount(tester, repository);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.completeError(_denied);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _Dependencies implements AppDependencies {
  _Dependencies(this.socialRepository);

  @override
  final SocialRepository socialRepository;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SocialRepository implements SocialRepository {
  int privacyCalls = 0;
  final List<int> pages = <int>[];
  final List<int> pageSizes = <int>[];
  final List<bool> updateValues = <bool>[];
  final List<(int, bool)> unblocks = <(int, bool)>[];
  List<SocialUser> items = <SocialUser>[_blockedUser];
  Future<PrivacySettings> Function()? onFetchPrivacy;
  Future<SocialPage<SocialUser>> Function(int, int)? onFetchPage;
  Future<PrivacySettings> Function(bool)? onUpdate;
  Future<void> Function()? onUnblock;

  @override
  Future<PrivacySettings> fetchPrivacySettings() {
    privacyCalls += 1;
    return onFetchPrivacy?.call() ?? Future<PrivacySettings>.value(_settings);
  }

  @override
  Future<SocialPage<SocialUser>> fetchBlacklist({
    required int page,
    required int pageSize,
  }) async {
    pages.add(page);
    pageSizes.add(pageSize);
    // Match the real repository's request contract, unlike the permissive mock.
    if (page < 1 || pageSize < 1 || pageSize > 50) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: 'pageSize 必须为 1 至 50',
      );
    }
    return onFetchPage?.call(page, pageSize) ??
        SocialPage<SocialUser>(
          items: items,
          page: page,
          pageSize: pageSize,
          total: items.length,
          hasMore: false,
        );
  }

  @override
  Future<PrivacySettings> updatePrivacySettings({
    required bool onlyFollowedCanFollow,
  }) {
    updateValues.add(onlyFollowedCanFollow);
    return onUpdate?.call(onlyFollowedCanFollow) ??
        Future<PrivacySettings>.value(_settings);
  }

  @override
  Future<void> setBlocked({required int userId, required bool blocked}) async {
    unblocks.add((userId, blocked));
    await onUnblock?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
