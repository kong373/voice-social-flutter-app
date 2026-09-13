import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/data/mock_auth_repository.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/im/domain/im_session_adapter.dart';

void main() {
  testWidgets(
    'create completion after clear and relogin cannot invoke payment',
    (WidgetTester tester) async {
      final _ControlledCatalogRepository repository =
          _ControlledCatalogRepository(
            createResult: _createdOrder(),
            queryResult: _succeededOrder(),
            holdCreate: true,
          );
      final AppDependencies dependencies = _dependencies(repository);
      addTearDown(dependencies.dispose);
      await dependencies.sessionManager.save(_session('before'));

      await _pumpPage(
        tester,
        dependencies,
        const PaymentSubmissionPage(
          product: _product,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        ),
      );
      await tester.tap(find.text('提交充值订单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pump();
      expect(repository.createStarted.isCompleted, isTrue);

      await dependencies.sessionManager.clear();
      await dependencies.sessionManager.save(_session('relogin'));
      repository.createRelease.complete();
      await tester.pumpAndSettle();

      expect(repository.createCalls, 1);
      expect(repository.invokeCalls, 0);
      expect(find.byType(PaymentResultPage), findsNothing);
      expect(find.text('登录身份已失效，请重新登录'), findsOneWidget);
    },
  );

  testWidgets(
    'confirmation cannot create an order after controller logout begins',
    (WidgetTester tester) async {
      final _ControlledCatalogRepository repository =
          _ControlledCatalogRepository(
            createResult: _createdOrder(),
            queryResult: _succeededOrder(),
          );
      final _DelayedLogoutAuthRepository authRepository =
          _DelayedLogoutAuthRepository();
      final AppDependencies dependencies = _dependencies(
        repository,
        authRepository: authRepository,
      );
      addTearDown(() async {
        await dependencies.imSessionCoordinator.logout();
        dependencies.dispose();
      });
      await dependencies.sessionManager.save(_session('before-logout'));

      await _pumpPage(
        tester,
        dependencies,
        const PaymentSubmissionPage(
          product: _product,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        ),
      );
      await tester.tap(find.text('提交充值订单'));
      await tester.pumpAndSettle();
      expect(find.text('确认充值信息'), findsOneWidget);

      final Future<void> logout = dependencies.authController.signOut();
      await authRepository.logoutStarted.future;
      expect(dependencies.authController.signingOut, isTrue);

      await tester.tap(find.text('确认提交'));
      await tester.pump();
      authRepository.logoutRelease.complete();
      await logout;
      await tester.pumpAndSettle();

      expect(repository.createCalls, 0);
      expect(repository.invokeCalls, 0);
      expect(find.byType(PaymentResultPage), findsNothing);
      expect(find.text('登录身份已失效，请重新登录'), findsOneWidget);
    },
  );

  testWidgets(
    'late result after same-account clear and relogin is not rendered',
    (WidgetTester tester) async {
      final _ControlledCatalogRepository repository =
          _ControlledCatalogRepository(
            createResult: _createdOrder(),
            queryResult: _succeededOrder(),
            holdQuery: true,
          );
      final AppDependencies dependencies = _dependencies(repository);
      addTearDown(dependencies.dispose);
      await dependencies.sessionManager.save(_session('before-query'));

      await _pumpPage(
        tester,
        dependencies,
        PaymentResultPage(order: _pendingOrder()),
        settle: false,
      );
      await tester.pump();
      expect(repository.queryStarted.isCompleted, isTrue);

      await dependencies.sessionManager.clear();
      await dependencies.sessionManager.save(_session('relogin-query'));
      repository.queryRelease.complete();
      await tester.pumpAndSettle();

      expect(repository.queryCalls, 1);
      expect(find.text('充值成功'), findsNothing);
      expect(find.text('登录身份已失效，请重新登录'), findsOneWidget);
    },
  );

  testWidgets(
    'same-account access-token rotation keeps the result query alive',
    (WidgetTester tester) async {
      final _ControlledCatalogRepository repository =
          _ControlledCatalogRepository(
            createResult: _createdOrder(),
            queryResult: _succeededOrder(),
            holdQuery: true,
          );
      final AppDependencies dependencies = _dependencies(repository);
      addTearDown(dependencies.dispose);
      await dependencies.sessionManager.save(_session('before-refresh'));

      await _pumpPage(
        tester,
        dependencies,
        PaymentResultPage(order: _pendingOrder()),
        settle: false,
      );
      await tester.pump();
      expect(repository.queryStarted.isCompleted, isTrue);

      await dependencies.sessionManager.save(_session('after-refresh'));
      repository.queryRelease.complete();
      await tester.pumpAndSettle();

      expect(repository.queryCalls, 1);
      expect(find.text('充值成功'), findsOneWidget);
      expect(find.text('登录身份已失效，请重新登录'), findsNothing);
    },
  );

  testWidgets(
    'normal AuthController refresh keeps the payment result query alive',
    (WidgetTester tester) async {
      final _ControlledCatalogRepository repository =
          _ControlledCatalogRepository(
            createResult: _createdOrder(),
            queryResult: _succeededOrder(),
            holdQuery: true,
          );
      final _DelayedRefreshAuthRepository authRepository =
          _DelayedRefreshAuthRepository();
      final AppDependencies dependencies = _dependencies(
        repository,
        authRepository: authRepository,
      );
      addTearDown(() async {
        await dependencies.imSessionCoordinator.logout();
        dependencies.dispose();
      });
      await dependencies.sessionManager.save(
        _session(
          'before-controller-refresh',
          accessExpiresIn: const Duration(seconds: 1),
        ),
      );

      await _pumpPage(
        tester,
        dependencies,
        PaymentResultPage(order: _pendingOrder()),
        settle: false,
      );
      await tester.pump();
      expect(repository.queryStarted.isCompleted, isTrue);

      final Future<bool> refresh = dependencies.authController.refreshSession();
      await authRepository.refreshStarted.future;
      expect(dependencies.authController.signingOut, isFalse);
      authRepository.refreshResult.complete(
        _session('after-controller-refresh'),
      );
      expect(await refresh, isTrue);

      repository.queryRelease.complete();
      await tester.pumpAndSettle();

      expect(repository.queryCalls, 1);
      expect(find.text('充值成功'), findsOneWidget);
      expect(find.text('登录身份已失效，请重新登录'), findsNothing);
    },
  );
}

const RechargeProduct _product = RechargeProduct(
  id: 'payment-fence-product',
  giftCoins: 60,
  priceCny: 6,
);

Future<void> _pumpPage(
  WidgetTester tester,
  AppDependencies dependencies,
  Widget page, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(theme: AppTheme.social(), home: page),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

AppDependencies _dependencies(
  _ControlledCatalogRepository repository, {
  MockAuthRepository? authRepository,
}) => AppDependencies.forTestEnvironment(
  environment: AppEnvironment.mock(),
  authRepositoryOverride:
      authRepository ?? const _ImmediateLogoutAuthRepository(),
  commerceCatalogRepositoryOverride: repository,
  imSessionAdapter: const BlockedImSessionAdapter(),
);

AuthSession _session(
  String suffix, {
  Duration accessExpiresIn = const Duration(hours: 1),
}) => AuthSession(
  accessToken: 'payment-access-$suffix',
  tokenType: 'Bearer',
  expiresAt: DateTime.now().add(accessExpiresIn),
  refreshToken: 'payment-refresh-$suffix',
  refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
  deviceId: 'payment-device',
  clientId: 'voice-social-mobile-public',
  userId: 10001,
  mobile: '13800138000',
  roles: 'USER',
);

RechargeOrder _createdOrder() => RechargeOrder(
  orderNo: 'payment-created-order',
  account: '13800138000',
  product: _product,
  channel: PaymentChannelType.alipay,
  state: RechargeOrderState.created,
  createdAt: DateTime(2026, 9, 13),
  message: '订单已创建',
);

RechargeOrder _pendingOrder() => RechargeOrder(
  orderNo: 'payment-pending-order',
  account: '13800138000',
  product: _product,
  channel: PaymentChannelType.alipay,
  state: RechargeOrderState.confirming,
  createdAt: DateTime(2026, 9, 13),
  message: '等待服务端确认',
);

RechargeOrder _succeededOrder() => _pendingOrder().copyWith(
  state: RechargeOrderState.succeeded,
  message: '服务端已确认到账',
);

class _ControlledCatalogRepository implements CommerceCatalogRepository {
  _ControlledCatalogRepository({
    required this.createResult,
    required this.queryResult,
    this.holdCreate = false,
    this.holdQuery = false,
  });

  final RechargeOrder createResult;
  final RechargeOrder queryResult;
  final bool holdCreate;
  final bool holdQuery;
  final Completer<void> createStarted = Completer<void>();
  final Completer<void> createRelease = Completer<void>();
  final Completer<void> queryStarted = Completer<void>();
  final Completer<void> queryRelease = Completer<void>();
  int createCalls = 0;
  int invokeCalls = 0;
  int queryCalls = 0;

  @override
  bool get supportsRechargeCatalog => true;

  @override
  bool get supportsPaymentChannelInvocation => true;

  @override
  List<PaymentChannelType> availableChannels(ClientStorePlatform platform) =>
      const <PaymentChannelType>[PaymentChannelType.alipay];

  @override
  Future<List<RechargeProduct>> fetchRechargeProducts({
    required ClientStorePlatform platform,
  }) async => const <RechargeProduct>[];

  @override
  Future<RechargeEligibility> checkRechargeEligibility({
    required bool youthModeEnabled,
  }) async => const RechargeEligibility(allowed: true, message: 'ok');

  @override
  Future<RechargeOrder> createRechargeOrder({
    required String account,
    required RechargeProduct product,
    required PaymentChannelType channel,
    required ClientStorePlatform platform,
    required bool youthModeEnabled,
  }) async {
    createCalls += 1;
    if (!createStarted.isCompleted) {
      createStarted.complete();
    }
    if (holdCreate) {
      await createRelease.future;
    }
    return createResult;
  }

  @override
  Future<RechargeOrder> invokePayment(RechargeOrder order) async {
    invokeCalls += 1;
    return order.copyWith(
      state: RechargeOrderState.confirming,
      message: '支付返回后正在等待服务端确认',
    );
  }

  @override
  Future<RechargeOrder> queryRechargeOrder(RechargeOrder order) async {
    queryCalls += 1;
    if (!queryStarted.isCompleted) {
      queryStarted.complete();
    }
    if (holdQuery) {
      await queryRelease.future;
    }
    return queryResult;
  }

  @override
  Future<List<GiftCatalogItem>> fetchGiftCatalog() async =>
      const <GiftCatalogItem>[];

  @override
  Future<List<DecorationItem>> fetchDecorations() async =>
      const <DecorationItem>[];

  @override
  Future<DecorationItem> purchaseDecoration(String decorationId) =>
      Future<DecorationItem>.error(UnimplementedError());

  @override
  Future<DecorationItem> setDecorationEquipped({
    required String decorationId,
    required bool equipped,
  }) => Future<DecorationItem>.error(UnimplementedError());
}

class _ImmediateLogoutAuthRepository extends MockAuthRepository {
  const _ImmediateLogoutAuthRepository();
}

class _DelayedLogoutAuthRepository extends MockAuthRepository {
  final Completer<void> logoutStarted = Completer<void>();
  final Completer<void> logoutRelease = Completer<void>();

  @override
  Future<void> logout(AuthSession session) async {
    if (!logoutStarted.isCompleted) {
      logoutStarted.complete();
    }
    await logoutRelease.future;
  }
}

class _DelayedRefreshAuthRepository extends MockAuthRepository {
  final Completer<void> refreshStarted = Completer<void>();
  final Completer<AuthSession> refreshResult = Completer<AuthSession>();

  @override
  Future<AuthSession> refreshSession(AuthSession session) {
    if (!refreshStarted.isCompleted) {
      refreshStarted.complete();
    }
    return refreshResult.future;
  }
}
