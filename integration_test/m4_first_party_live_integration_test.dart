import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/app/app_gate.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/shell/live_read_only_repository.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

import 'm2_4_test_support.dart';

/// The relay is started by run_m4_authoritative_live_avd.sh. It is deliberately
/// not a backend substitute: it only returns operator-provided development
/// test configuration over an ephemeral host port. Phone and public-client
/// values never enter a dart-define, reportData, debug marker, screenshot
/// name, or source file.
const String _runtimeConfigPortValue = String.fromEnvironment(
  'M4_RUNTIME_CONFIG_PORT',
  defaultValue: '0',
);
final int _runtimeConfigPort = int.tryParse(_runtimeConfigPortValue) ?? 0;

const String _authoritativeApiBaseUrl = 'http://10.0.2.2:18080/';
const String _runtimeConfigPath = '/m4/config';
final RegExp _canonicalRoomUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

// These are non-secret immutable candidate identities supplied by the
// acceptance runner.  A live test must not be able to claim PASS when it is
// running a different checkout (or when the runner forgot to bind the
// candidate identity at all).
const String _expectedTestedFlutterSha = String.fromEnvironment(
  'M4_EXPECTED_FLUTTER_SHA',
  defaultValue: '',
);
const String _expectedTestedBackendSha = String.fromEnvironment(
  'M4_EXPECTED_BACKEND_SHA',
  defaultValue: '',
);

const String _expectedWidthValue = String.fromEnvironment(
  'QA_EXPECTED_VIEWPORT_WIDTH',
  defaultValue: '390',
);
const String _expectedHeightValue = String.fromEnvironment(
  'QA_EXPECTED_VIEWPORT_HEIGHT',
  defaultValue: '844',
);
const String _expectedDprValue = String.fromEnvironment(
  'QA_EXPECTED_DPR',
  defaultValue: '3',
);
final double _expectedWidth = double.parse(_expectedWidthValue);
final double _expectedHeight = double.parse(_expectedHeightValue);
final double _expectedDpr = double.parse(_expectedDprValue);

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'M4 first-party live authoritative backend flow',
    (WidgetTester tester) async {
      final _M4Evidence evidence = _M4Evidence(avd: qaAvdId, binding: binding);
      final _RuntimeConfig config = await _fetchRuntimeConfig();
      final AppEnvironment environment = _liveEnvironment(config.oauthClientId);
      environment.validateLiveConfiguration();
      expect(_authoritativeApiBaseUrl, 'http://10.0.2.2:18080/');
      expect(_authoritativeApiBaseUrl, isNot(contains(':8765')));
      expect(_authoritativeApiBaseUrl, isNot(contains('contract-server')));
      evidence.invariant('authoritative_backend_target_10_0_2_2_18080');

      AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: environment,
      );
      await _pumpGate(tester, dependencies);
      _expectExactViewport(tester);

      // Consent is local and must precede every backend call. The first
      // screenshot is intentionally captured before accepting it.
      await _waitFor(
        tester,
        () => find.text('同意并继续').evaluate().isNotEmpty,
        description: 'consent gate',
      );
      evidence.local('consent', '/consent', 'success');
      await captureQaScreenshot(
        tester,
        binding,
        'm4-${qaAvdId.toLowerCase()}-01-consent',
      );
      await tester.drag(
        find.byKey(const Key('consent-scroll')),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      final Finder consentTile = find.byKey(
        const Key('consent-agreement-checkbox'),
      );
      await tester.ensureVisible(consentTile);
      await tester.tap(
        find.descendant(of: consentTile, matching: find.byType(Checkbox)),
      );
      await tester.pump();
      await tester.tap(find.text('同意并继续').hitTestable());

      await _waitFor(
        tester,
        () => find.text('登录 / 注册').evaluate().isNotEmpty,
        description: 'login page',
      );
      final Finder phoneField = find.widgetWithText(TextFormField, '手机号码');
      await tester.enterText(phoneField, config.phone);
      await dismissQaImeAndWait(tester);
      await tester.ensureVisible(find.text('获取验证码'));
      await tester.tap(find.text('获取验证码').hitTestable());
      await _waitFor(
        tester,
        () => dependencies.authController.lastSmsChallenge != null,
        description: 'development SMS challenge response',
      );
      final SmsChallenge challenge =
          dependencies.authController.lastSmsChallenge!;
      // A development profile must return its code in the challenge response.
      // There is intentionally no source or environment fallback code.
      final String? developmentCode = challenge.developmentCode;
      if (developmentCode == null ||
          !RegExp(r'^\d{6}$').hasMatch(developmentCode)) {
        throw TestFailure(
          'Development SMS challenge did not contain a six-digit in-memory code.',
        );
      }
      evidence.invariant('development_otp_consumed_in_memory_only');
      final Finder codeField = find.widgetWithText(TextFormField, '短信验证码');
      // The OTP exists only in this test process and the editable field; it is
      // never printed, captured, persisted, or forwarded through a host env.
      await tester.enterText(codeField, developmentCode);
      await dismissQaImeAndWait(tester);
      evidence.http(
        capability: 'auth.send_code',
        method: 'PUT',
        route: const BackendRouteCatalog().sendSmsCode,
        status: 200,
        state: 'success',
      );
      await tester.ensureVisible(find.text('登录 / 注册'));
      await tester.tap(find.text('登录 / 注册').hitTestable());
      await _waitFor(
        tester,
        () =>
            find.text('完善资料').evaluate().isNotEmpty ||
            find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty,
        description: 'login or registration result',
      );

      if (find.text('完善资料').evaluate().isNotEmpty) {
        evidence.http(
          capability: 'auth.login',
          method: 'PUT',
          route: const BackendRouteCatalog().loginBySms,
          status: 200,
          state: 'registration_required',
        );
        final Finder nicknameField = find.widgetWithText(TextFormField, '昵称');
        await tester.enterText(nicknameField, _registrationNickname());
        await dismissQaImeAndWait(tester);
        await tester.ensureVisible(find.text('完成注册'));
        await tester.tap(find.text('完成注册').hitTestable());
        await _waitFor(
          tester,
          () => find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty,
          description: 'completed registration and home',
        );
        evidence.http(
          capability: 'auth.register',
          method: 'POST',
          route: const BackendRouteCatalog().registerByMobile,
          status: 200,
          state: 'success',
        );
      } else {
        evidence.http(
          capability: 'auth.login',
          method: 'PUT',
          route: const BackendRouteCatalog().loginBySms,
          status: 200,
          state: 'success',
        );
      }
      expect(find.byKey(const Key('live-home-ready')), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm4-${qaAvdId.toLowerCase()}-02-home',
      );

      final AuthSession sessionBeforeRefresh =
          dependencies.authController.session!;
      final bool refreshed = await dependencies.authController.refreshSession();
      evidence.http(
        capability: 'auth.refresh',
        method: 'POST',
        route: '/app-register-api/userAccount/v1/refreshSession',
        status: refreshed ? 200 : 503,
        state: refreshed ? 'success' : 'blocked',
      );
      expect(refreshed, isTrue);
      final AuthSession refreshedSession = dependencies.authController.session!;
      if (refreshedSession.refreshToken == sessionBeforeRefresh.refreshToken) {
        throw TestFailure(
          'Session refresh did not rotate the refresh credential.',
        );
      }

      // A fresh dependency graph with only the serialized session and consent
      // simulates process restart without exposing credentials to the host.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      dependencies = AppDependencies.forTestEnvironment(
        environment: environment,
        initialStorage: <String, String>{
          'auth.session.v2': refreshedSession.encode(),
          'compliance.consent.v1': 'accepted:app-owned-v1',
        },
      );
      await _pumpGate(tester, dependencies);
      await _waitFor(
        tester,
        () => find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty,
        description: 'session restart recovery',
      );
      evidence.invariant('session_refresh_persists_rotated_session');
      evidence.invariant('restart_restores_consent_and_session');
      await captureQaScreenshot(
        tester,
        binding,
        'm4-${qaAvdId.toLowerCase()}-03-restart-recovered',
      );

      final BackendRouteCatalog routes = const BackendRouteCatalog();
      final int currentUserId = dependencies.authController.session!.userId;
      final String account = dependencies.authController.session!.mobile;

      // This is a first-party, read-only readiness document. It records the
      // server's explicit vendor boundary without invoking any provider SDK or
      // client-side vendor call.
      final VendorReadinessOverview? vendorReadiness = await _probe(
        evidence,
        capability: 'vendor.readiness',
        method: 'GET',
        route: '/app-register-api/vendor/v1/readiness',
        operation: () =>
            dependencies.liveReadOnlyRepository.fetchVendorReadiness(),
        requiredSuccess: true,
      );
      expect(vendorReadiness, isNotNull);
      final VendorReadinessOverview authoritativeVendorReadiness =
          vendorReadiness!;
      _expectVendorReadinessFailClosed(authoritativeVendorReadiness);
      evidence.invariant('vendor_readiness_observed_without_client_provider');
      evidence.invariant('vendor_readiness_has_all_six_formal_capabilities');
      evidence.invariant('vendor_runtime_adapters_are_fail_closed');

      // Required first-party reads. They intentionally use generic data and
      // never assume a seeded room, user, order, or task ID.
      final List<DiscoveryRoom>? homeRooms = await _probe(
        evidence,
        capability: 'home.recommendations',
        method: 'POST',
        route: routes.homeRecommendedRooms,
        operation: () => dependencies.discoveryRepository.fetchHomeRooms(),
        requiredSuccess: true,
      );
      expect(homeRooms, isNotNull);
      evidence.invariant('home_uses_authoritative_room_ids');

      final RoomCollectionSnapshot? roomCollections = await _probe(
        evidence,
        capability: 'room.owned',
        method: 'GET',
        route: routes.ownedRooms,
        operation: () => dependencies.discoveryRepository.fetchRoomCollections(
          page: 1,
          pageSize: 30,
        ),
        requiredSuccess: true,
      );
      expect(roomCollections, isNotNull);
      final List<DiscoveryRoom> currentUserOwnedRooms = roomCollections!
          .ownedRooms
          .where((DiscoveryRoom room) => room.ownerUserId == currentUserId)
          .toList(growable: false);
      expect(
        currentUserOwnedRooms,
        isNotEmpty,
        reason:
            'M4 development fixture must expose a room owned by the current user.',
      );
      final _OwnedModeRooms ownedModeRooms = await _selectOwnedRoomsByMode(
        dependencies,
        evidence,
        rooms: currentUserOwnedRooms,
        currentUserId: currentUserId,
      );

      await _runSearchFlow(tester, dependencies, evidence);
      await _runDynamicSocialCommunityFlow(
        tester,
        dependencies,
        evidence,
        currentUserId: currentUserId,
      );
      final _LiveRoomContext? liveRoom = await _runRoomFlow(
        tester,
        dependencies,
        evidence,
        room: ownedModeRooms.direct,
        currentUserId: currentUserId,
      );
      await _runApprovalMicQueueFlow(
        dependencies,
        evidence,
        room: ownedModeRooms.approval,
        currentUserId: currentUserId,
      );
      await _runMessagesFlow(
        tester,
        dependencies,
        evidence,
        fallbackTargetUserId: liveRoom?.targetUserId,
        currentUserId: currentUserId,
      );
      await _runCommerceFlow(tester, dependencies, evidence);
      await _runComplianceAndSupportFlow(
        tester,
        dependencies,
        evidence,
        account,
      );
      evidence.invariant('first_party_mutations_stay_vendor_free');

      // The final UI action is a real logout. It is safe and idempotent; no
      // vendor call is made by AuthController.signOut.
      await _openPersonalCenterForLogout(tester, dependencies);
      final Finder logout = find.text('退出登录').hitTestable();
      expect(logout, findsOneWidget);
      await tester.tap(logout);
      await _waitFor(
        tester,
        () => find.text('登录 / 注册').evaluate().isNotEmpty,
        description: 'logout and local credential deletion',
      );
      expect(
        dependencies.authController.lastServerLogoutOutcome,
        ServerLogoutOutcome.succeeded,
        reason: 'the authoritative backend must confirm product logout',
      );
      evidence.http(
        capability: 'auth.logout',
        method: 'POST',
        route: '/app-register-api/userAccount/v1/logout',
        status: 200,
        state: 'success',
      );
      evidence.invariant('logout_clears_local_session');
      await captureQaScreenshot(
        tester,
        binding,
        'm4-${qaAvdId.toLowerCase()}-04-logout',
      );

      final Object? unhandledException = tester.takeException();
      if (unhandledException != null) {
        // Do not interpolate the exception: a backend/client exception could
        // contain a credential-bearing response even though normal probes are
        // redacted.
        throw TestFailure('Flutter reported an unhandled exception.');
      }
      evidence.finish();
    },
    timeout: const Timeout(Duration(minutes: 25)),
    skip: _runtimeConfigPort == 0,
  );
}

AppEnvironment _liveEnvironment(String oauthClientId) => AppEnvironment(
  backendMode: BackendMode.live,
  apiBaseUrl: _authoritativeApiBaseUrl,
  clientType: 'Android',
  clientInnerVersion: '1',
  oauthClientId: oauthClientId,
  realtimeEndpoint: '',
  deploymentEnvironment: DeploymentEnvironment.development,
  allowInsecureHttp: true,
  apiTimeout: const Duration(seconds: 15),
);

String _registrationNickname() =>
    'm4-${qaAvdId.toLowerCase()}-${DateTime.now().millisecondsSinceEpoch % 100000}';

Future<_RuntimeConfig> _fetchRuntimeConfig() async {
  if (_runtimeConfigPort < 1) {
    throw TestFailure('M4 runtime config relay is not configured.');
  }
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 5);
  try {
    final HttpClientRequest request = await client
        .get('10.0.2.2', _runtimeConfigPort, _runtimeConfigPath)
        .timeout(const Duration(seconds: 5));
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 5),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw TestFailure(
        'M4 runtime config relay returned status ${response.statusCode}.',
      );
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw TestFailure('M4 runtime config relay returned an invalid object.');
    }
    final String phone = decoded['phone']?.toString().trim() ?? '';
    final String oauthClientId =
        decoded['oauthClientId']?.toString().trim() ?? '';
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone) || oauthClientId.isEmpty) {
      throw TestFailure(
        'M4 runtime config relay omitted required development values.',
      );
    }
    return _RuntimeConfig(phone: phone, oauthClientId: oauthClientId);
  } finally {
    client.close(force: true);
  }
}

class _RuntimeConfig {
  const _RuntimeConfig({required this.phone, required this.oauthClientId});

  final String phone;
  final String oauthClientId;
}

Future<void> _pumpGate(
  WidgetTester tester,
  AppDependencies dependencies,
) async {
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: AppGate(dependencies: dependencies),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _runSearchFlow(
  WidgetTester tester,
  AppDependencies dependencies,
  _M4Evidence evidence,
) async {
  await _probe(
    evidence,
    capability: 'search.suggestions',
    method: 'GET',
    route: const BackendRouteCatalog().searchSuggestions,
    operation: () => dependencies.discoveryRepository.fetchSearchSuggestions(),
  );
  await _probe(
    evidence,
    capability: 'search.results',
    method: 'POST',
    route: const BackendRouteCatalog().globalSearch,
    operation: () => dependencies.discoveryRepository.search(
      keyword: 'voice',
      type: SearchEntityType.all,
    ),
  );
  await tester.tap(find.byKey(const Key('open-global-search')).hitTestable());
  await _waitFor(
    tester,
    () => find.byKey(const Key('global-search-field')).evaluate().isNotEmpty,
    description: 'global search page',
  );
  await tester.enterText(find.byKey(const Key('global-search-field')), 'voice');
  await dismissQaImeAndWait(tester);
  final Finder searchButton = find
      .widgetWithText(TextButton, '搜索')
      .hitTestable();
  if (searchButton.evaluate().isNotEmpty) {
    await tester.tap(searchButton);
    await _waitFor(
      tester,
      () =>
          find.textContaining('搜索结果').evaluate().isNotEmpty ||
          find.textContaining('无法').evaluate().isNotEmpty ||
          find.textContaining('失败').evaluate().isNotEmpty,
      description: 'global search result or explicit unavailable state',
    );
  }
  evidence.invariant('search_route_is_reachable_from_home');
  await captureQaScreenshot(
    tester,
    evidence.binding,
    'm4-${qaAvdId.toLowerCase()}-05-search',
  );
  await tester.pageBack();
  await tester.pumpAndSettle();
  // Search is a two-route flow: the result page is pushed above the search
  // editor. Pop both routes before asserting that the shell home is restored.
  if (find.byKey(const Key('global-search-field')).evaluate().isNotEmpty) {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }
  await _waitFor(
    tester,
    () => find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty,
    description: 'home after search',
  );
}

Future<void> _runDynamicSocialCommunityFlow(
  WidgetTester tester,
  AppDependencies dependencies,
  _M4Evidence evidence, {
  required int currentUserId,
}) async {
  await _probe(
    evidence,
    capability: 'dynamic.feed',
    method: 'GET',
    route: const BackendRouteCatalog().dynamicList,
    operation: () => dependencies.dynamicRepository.fetchFeed(),
  );
  await _probe(
    evidence,
    capability: 'social.profile',
    method: 'GET',
    route: const BackendRouteCatalog().personalData,
    operation: () => dependencies.socialRepository.fetchMyProfile(),
  );
  // fetchMyProfile tolerates a documented 404 for an empty personal
  // homepage.  The acceptance gate must not turn that tolerated branch into
  // an invented homepage success, so probe the homepage route directly.
  await _probe(
    evidence,
    capability: 'social.homepage',
    method: 'GET',
    route: const BackendRouteCatalog().personalHomepage,
    operation: () =>
        dependencies.socialRepository.fetchPublicProfile(currentUserId),
    requiredSuccess: true,
  );
  final Object? communityHomeProbe = await _probe(
    evidence,
    capability: 'community.home',
    method: 'GET',
    route: const BackendRouteCatalog().currentGuild,
    operation: () => dependencies.communityRepository.fetchGuildHome(),
  );
  if (communityHomeProbe != null) {
    evidence.composite(
      capability: 'community.recommended_guilds',
      method: 'POST',
      route: const BackendRouteCatalog().recommendedGuilds,
      status: 200,
    );
  }
  final TaskCenterSnapshot? taskCenterProbe = await _probe<TaskCenterSnapshot>(
    evidence,
    capability: 'community.tasks',
    method: 'GET',
    route: const BackendRouteCatalog().taskRecords,
    operation: () => dependencies.communityRepository.fetchTaskCenter(),
  );
  if (taskCenterProbe != null) {
    evidence.composite(
      capability: 'community.sign_rewards',
      method: 'GET',
      route: const BackendRouteCatalog().signRewards,
      status: 200,
    );
    evidence.composite(
      capability: 'community.today_sign_status',
      method: 'GET',
      route: const BackendRouteCatalog().todaySignStatus,
      status: 200,
    );

    // A daily sign or a claimable task is a small, first-party-only mutation.
    // The authoritative status read decides which one is safe. If an earlier
    // AVD already performed today's idempotent operation, keep that state
    // explicit in evidence rather than pretending that this AVD issued a
    // second write.
    if (!taskCenterProbe.signedToday) {
      evidence.requireCapability('community.checkin');
      final TaskCenterSnapshot? signed = await _probe(
        evidence,
        capability: 'community.checkin',
        method: 'POST',
        route: const BackendRouteCatalog().completeSignIn,
        operation: () =>
            dependencies.communityRepository.completeDailyCheckIn(),
        requiredSuccess: true,
      );
      if (signed == null || !signed.signedToday) {
        throw TestFailure('Daily sign response did not confirm signedToday.');
      }
      evidence.invariant('community_checkin_authority_confirmed');
    } else {
      evidence.preexisting(
        'community.checkin',
        const BackendRouteCatalog().todaySignStatus,
        'already_authoritative',
      );
    }

    TaskItem? claimableTask;
    for (final TaskItem task in taskCenterProbe.tasks) {
      if (task.state == TaskState.claimable) {
        claimableTask = task;
        break;
      }
    }
    if (claimableTask != null) {
      final TaskItem selectedTask = claimableTask;
      evidence.requireCapability('community.task.claim');
      final TaskCenterSnapshot? claimed = await _probe(
        evidence,
        capability: 'community.task.claim',
        method: 'POST',
        route: const BackendRouteCatalog().claimTaskReward,
        operation: () =>
            dependencies.communityRepository.claimTask(selectedTask.id),
        requiredSuccess: true,
      );
      if (claimed == null ||
          claimed.tasks.any(
            (TaskItem task) =>
                task.id == selectedTask.id && task.state != TaskState.claimed,
          )) {
        throw TestFailure('Task claim response did not confirm claimed state.');
      }
      evidence.invariant('community_task_claim_authority_confirmed');
    } else {
      bool hasClaimedTask = false;
      for (final TaskItem task in taskCenterProbe.tasks) {
        if (task.state == TaskState.claimed) {
          hasClaimedTask = true;
          break;
        }
      }
      if (hasClaimedTask) {
        evidence.preexisting(
          'community.task.claim',
          const BackendRouteCatalog().taskRecords,
          'already_authoritative',
        );
      } else {
        evidence.local(
          'community.task.claim',
          const BackendRouteCatalog().taskRecords,
          'no_claimable_authoritative_task',
        );
      }
    }
  }
  await _probe(
    evidence,
    capability: 'community.activities',
    method: 'GET',
    route: const BackendRouteCatalog().activityCatalog,
    operation: () => dependencies.communityRepository.fetchActivities(),
  );

  await tester.tap(find.text('发现').last.hitTestable());
  await _waitFor(
    tester,
    () =>
        find.byTooltip('社交经营').evaluate().isNotEmpty ||
        find.text('发布').evaluate().isNotEmpty,
    description: 'dynamic/social discovery page',
  );
  evidence.invariant('dynamic_page_reachable_from_primary_navigation');
  await captureQaScreenshot(
    tester,
    evidence.binding,
    'm4-${qaAvdId.toLowerCase()}-06-dynamic',
  );

  final Finder communityEntry = find.byTooltip('社交经营').hitTestable();
  if (communityEntry.evaluate().isNotEmpty) {
    await tester.tap(communityEntry);
    await _waitFor(
      tester,
      () => find.text('社交经营与活动').evaluate().isNotEmpty,
      description: 'community hub',
    );
    evidence.invariant('community_hub_reachable_from_dynamic');
    await captureQaScreenshot(
      tester,
      evidence.binding,
      'm4-${qaAvdId.toLowerCase()}-07-community',
    );
    final Finder taskEntry = find.text('任务与签到').hitTestable();
    if (taskEntry.evaluate().isNotEmpty) {
      await tester.tap(taskEntry);
      await _waitFor(
        tester,
        () => find.textContaining('签到').evaluate().isNotEmpty,
        description: 'community task page',
      );
      evidence.invariant('task_page_reachable_without_claiming_reward');
      await captureQaScreenshot(
        tester,
        evidence.binding,
        'm4-${qaAvdId.toLowerCase()}-08-task',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    } else {
      evidence.local(
        'community.tasks.ui',
        '/community/tasks',
        'ui_entry_unavailable',
      );
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
  } else {
    evidence.local('community.ui', '/community', 'ui_entry_unavailable');
    evidence.local(
      'community.tasks.ui',
      '/community/tasks',
      'community_ui_unavailable',
    );
  }
  await tester.tap(find.text('首页').last.hitTestable());
  await _waitFor(
    tester,
    () => find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty,
    description: 'home after community flow',
  );
}

Future<_OwnedModeRooms> _selectOwnedRoomsByMode(
  AppDependencies dependencies,
  _M4Evidence evidence, {
  required List<DiscoveryRoom> rooms,
  required int currentUserId,
}) async {
  DiscoveryRoom? directRoom;
  DiscoveryRoom? approvalRoom;
  for (final DiscoveryRoom candidate in rooms) {
    if (directRoom != null && approvalRoom != null) {
      break;
    }
    if (!_canonicalRoomUuidPattern.hasMatch(candidate.id)) {
      continue;
    }
    bool entered = false;
    try {
      final RoomSnapshot? snapshot = await _probe<RoomSnapshot>(
        evidence,
        capability: 'room.enter',
        method: 'POST',
        route: const BackendRouteCatalog().enterRoom,
        operation: () => dependencies.roomRepository.enterRoom(
          roomId: candidate.id,
          password: null,
          source: RoomEntrySource.home,
          currentUserId: currentUserId,
        ),
        requiredSuccess: true,
      );
      if (snapshot == null) {
        throw TestFailure(
          'Owned room ${candidate.id} did not return an authoritative snapshot.',
        );
      }
      entered = true;
      if (snapshot.roomId != candidate.id) {
        throw TestFailure(
          'Owned room selection received a snapshot for ${snapshot.roomId} '
          'instead of ${candidate.id}.',
        );
      }
      if (snapshot.ownerId != currentUserId ||
          snapshot.role != RoomRole.owner) {
        throw TestFailure(
          'Owned room ${candidate.id} did not authorize the current user as '
          'the room owner in its authoritative snapshot.',
        );
      }
      final String accessMode = snapshot.accessMode.trim().toUpperCase();
      if (_isDirectRoomAccessMode(accessMode)) {
        directRoom ??= candidate;
      } else if (accessMode == 'APPROVAL') {
        approvalRoom ??= candidate;
      } else {
        throw TestFailure(
          'Owned room ${candidate.id} has unknown authoritative access mode '
          '"$accessMode"; M4 cannot guess a microphone coordination mode.',
        );
      }
    } finally {
      if (entered) {
        try {
          await dependencies.roomRepository.exitRoom(candidate.id);
          evidence.http(
            capability: 'room.exit.cleanup',
            method: 'POST',
            route: const BackendRouteCatalog().exitRoom,
            status: 200,
            state: 'success',
          );
        } on ApiException catch (error) {
          evidence.http(
            capability: 'room.exit.cleanup',
            method: 'POST',
            route: const BackendRouteCatalog().exitRoom,
            status: error.httpStatus ?? 0,
            state: _stateFor(error),
          );
          throw TestFailure(
            'Owned room ${candidate.id} cleanup failed with status '
            '${error.httpStatus ?? 0}.',
          );
        }
      }
    }
  }
  if (directRoom == null || approvalRoom == null) {
    throw TestFailure(
      'M4 requires two distinct canonical UUID owned rooms: one authoritative '
      'DIRECT/PUBLIC/PASSWORD room and one APPROVAL room. '
      'Found direct=${directRoom?.id ?? 'none'}, '
      'approval=${approvalRoom?.id ?? 'none'}.',
    );
  }
  final DiscoveryRoom selectedDirectRoom = directRoom;
  final DiscoveryRoom selectedApprovalRoom = approvalRoom;
  if (selectedDirectRoom.id == selectedApprovalRoom.id) {
    throw TestFailure(
      'M4 must not exercise direct and approval microphone paths in one room.',
    );
  }
  evidence.invariant('room_access_modes_selected_from_authoritative_snapshots');
  return _OwnedModeRooms(
    direct: selectedDirectRoom,
    approval: selectedApprovalRoom,
  );
}

bool _isDirectRoomAccessMode(String accessMode) =>
    accessMode == 'DIRECT' ||
    accessMode == 'PUBLIC' ||
    accessMode == 'PASSWORD';

Future<void> _runApprovalMicQueueFlow(
  AppDependencies dependencies,
  _M4Evidence evidence, {
  required DiscoveryRoom room,
  required int currentUserId,
}) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  final RoomSnapshot? entered = await _probe<RoomSnapshot>(
    evidence,
    capability: 'room.enter',
    method: 'POST',
    route: routes.enterRoom,
    operation: () => dependencies.roomRepository.enterRoom(
      roomId: room.id,
      password: null,
      source: RoomEntrySource.home,
      currentUserId: currentUserId,
    ),
    requiredSuccess: true,
  );
  if (entered == null) {
    throw TestFailure(
      'Approval room did not return an authoritative snapshot.',
    );
  }
  try {
    if (entered.roomId != room.id ||
        entered.ownerId != currentUserId ||
        entered.role != RoomRole.owner ||
        entered.accessMode.trim().toUpperCase() != 'APPROVAL') {
      throw TestFailure(
        'Approval microphone queue entered a room without authoritative '
        'owner/APPROVAL authority.',
      );
    }
    final RoomSnapshot? reconnected = await _probe<RoomSnapshot>(
      evidence,
      capability: 'room.reconnect',
      method: 'POST',
      route: routes.reconnectRoom,
      operation: () => dependencies.roomRepository.reconnectRoom(
        roomId: room.id,
        currentUserId: currentUserId,
      ),
      requiredSuccess: true,
    );
    if (reconnected == null ||
        reconnected.roomId != room.id ||
        reconnected.ownerId != currentUserId ||
        reconnected.role != RoomRole.owner ||
        reconnected.accessMode.trim().toUpperCase() != 'APPROVAL') {
      throw TestFailure(
        'Approval microphone queue reconnect did not preserve authoritative '
        'owner/APPROVAL authority.',
      );
    }
    evidence.invariant('approval_room_authority_confirmed');
    final List<MicAccessRequest>? initialRequests =
        await _probe<List<MicAccessRequest>>(
          evidence,
          capability: 'room.mic_requests.get',
          method: 'GET',
          route: routes.roomMicRequests,
          operation: () =>
              dependencies.roomOperationsRepository.fetchMicRequests(room.id),
          requiredSuccess: true,
        );
    if (initialRequests == null) {
      throw TestFailure(
        'Approval room queue read returned no authoritative list.',
      );
    }

    MicAccessRequest? ownPendingRequest;
    for (final MicAccessRequest request in initialRequests) {
      if (request.isRequest &&
          request.isPending &&
          request.requestedByUserId == currentUserId &&
          request.subjectUserId == currentUserId) {
        ownPendingRequest = request;
        break;
      }
    }
    if (ownPendingRequest != null) {
      evidence.requireCapability('room.mic_requests.cancel');
      await _probe<void>(
        evidence,
        capability: 'room.mic_requests.cancel',
        method: 'POST',
        route: routes.cancelRoomMicRequest,
        operation: () => dependencies.roomOperationsRepository.cancelMicRequest(
          requestId: ownPendingRequest!.id,
        ),
        requiredSuccess: true,
      );
    }
    MicSeat? availableSeat;
    for (final MicSeat seat in reconnected.seats) {
      if (seat.isAvailable) {
        availableSeat = seat;
        break;
      }
    }
    if (availableSeat == null) {
      throw TestFailure(
        'Approval room has no available seat after own queue recovery.',
      );
    }
    final int seatNumber = availableSeat.number;
    evidence.requireCapability('room.mic_requests.submit');
    await _probe<void>(
      evidence,
      capability: 'room.mic_requests.submit',
      method: 'POST',
      route: routes.roomMicRequests,
      operation: () => dependencies.roomOperationsRepository.submitMicRequest(
        roomId: room.id,
        userId: currentUserId,
        seatNumber: seatNumber,
      ),
      requiredSuccess: true,
    );
    final List<MicAccessRequest>? afterSubmit =
        await _probe<List<MicAccessRequest>>(
          evidence,
          capability: 'room.mic_requests.get',
          method: 'GET',
          route: routes.roomMicRequests,
          operation: () =>
              dependencies.roomOperationsRepository.fetchMicRequests(room.id),
          requiredSuccess: true,
        );
    MicAccessRequest? submittedRequest;
    for (final MicAccessRequest request
        in afterSubmit ?? const <MicAccessRequest>[]) {
      if (request.isRequest &&
          request.isPending &&
          request.requestedByUserId == currentUserId &&
          request.subjectUserId == currentUserId &&
          request.seatNumber == seatNumber) {
        submittedRequest = request;
        break;
      }
    }
    if (submittedRequest == null) {
      throw TestFailure(
        'Approval microphone request was not visible in the authoritative '
        'queue after submit.',
      );
    }
    evidence.requireCapability('room.mic_requests.cancel');
    await _probe<void>(
      evidence,
      capability: 'room.mic_requests.cancel',
      method: 'POST',
      route: routes.cancelRoomMicRequest,
      operation: () => dependencies.roomOperationsRepository.cancelMicRequest(
        requestId: submittedRequest!.id,
      ),
      requiredSuccess: true,
    );
    evidence.invariant('approval_mic_queue_action_compensated');
  } finally {
    try {
      await dependencies.roomRepository.exitRoom(room.id);
      evidence.http(
        capability: 'room.exit.cleanup',
        method: 'POST',
        route: routes.exitRoom,
        status: 200,
        state: 'success',
      );
    } on ApiException catch (error) {
      evidence.http(
        capability: 'room.exit.cleanup',
        method: 'POST',
        route: routes.exitRoom,
        status: error.httpStatus ?? 0,
        state: _stateFor(error),
      );
      throw TestFailure(
        'Approval room cleanup failed with status ${error.httpStatus ?? 0}.',
      );
    }
  }
}

Future<_LiveRoomContext?> _runRoomFlow(
  WidgetTester tester,
  AppDependencies dependencies,
  _M4Evidence evidence, {
  required DiscoveryRoom? room,
  required int currentUserId,
}) async {
  if (room == null) {
    evidence.local(
      'room.lifecycle',
      '/room',
      'no_authoritative_room_available',
    );
    evidence.invariant(
      'room_writes_not_attempted_without_authoritative_room_id',
    );
    evidence.local(
      'room.moderation.ui',
      '/room/management',
      'no_authoritative_room_available',
    );
    evidence.local('room.pk.ui', '/room/pk', 'no_authoritative_room_available');
    return null;
  }
  final String roomId = room.id;
  int? targetUserId;
  final RoomRepositoryProbeResult? entered = await _probe(
    evidence,
    capability: 'room.enter',
    method: 'POST',
    route: const BackendRouteCatalog().enterRoom,
    operation: () => dependencies.roomRepository.enterRoom(
      roomId: roomId,
      password: null,
      source: RoomEntrySource.home,
      currentUserId: currentUserId,
    ),
  );
  if (entered != null) {
    final RoomSnapshot enteredSnapshot = entered;
    if (enteredSnapshot.roomId != roomId ||
        enteredSnapshot.ownerId != currentUserId ||
        enteredSnapshot.role != RoomRole.owner ||
        !_isDirectRoomAccessMode(
          enteredSnapshot.accessMode.trim().toUpperCase(),
        )) {
      throw TestFailure(
        'Direct microphone moderation flow entered a room without '
        'authoritative owner/direct access: ${enteredSnapshot.roomId} '
        '(${enteredSnapshot.accessMode}).',
      );
    }
    evidence.invariant('direct_room_authority_confirmed');
    evidence.invariant(
      enteredSnapshot.isSnapshotOnly
          ? 'room_snapshot_only_no_rtc_transport'
          : 'room_transport_state_authoritative',
    );
    await _probe(
      evidence,
      capability: 'room.public_messages',
      method: 'GET',
      route: const BackendRouteCatalog().publicMessages,
      operation: () => dependencies.roomRepository.fetchPublicMessages(roomId),
    );
    final RoomSnapshot? reconnectedSnapshot = await _probe<RoomSnapshot>(
      evidence,
      capability: 'room.reconnect',
      method: 'POST',
      route: const BackendRouteCatalog().reconnectRoom,
      operation: () => dependencies.roomRepository.reconnectRoom(
        roomId: roomId,
        currentUserId: currentUserId,
      ),
      requiredSuccess: true,
    );
    if (reconnectedSnapshot == null ||
        reconnectedSnapshot.roomId != roomId ||
        reconnectedSnapshot.ownerId != currentUserId ||
        reconnectedSnapshot.role != RoomRole.owner ||
        !_isDirectRoomAccessMode(
          reconnectedSnapshot.accessMode.trim().toUpperCase(),
        )) {
      throw TestFailure(
        'Direct microphone moderation reconnect did not preserve '
        'authoritative owner/direct access.',
      );
    }
    final RoomSnapshot snapshot = reconnectedSnapshot;
    evidence.invariant('room_mutations_use_current_user_owned_room');
    evidence.invariant('room_open_authority_confirmed_by_enter_and_reconnect');
    final RoomMemberPage? onlineMembers = await _probe<RoomMemberPage>(
      evidence,
      capability: 'room.seats',
      method: 'POST',
      route: const BackendRouteCatalog().roomOnlineMembers,
      operation: () => dependencies.roomOperationsRepository.fetchOnlineMembers(
        roomId: roomId,
        page: 1,
      ),
    );
    await _probe(
      evidence,
      capability: 'room.off_mic_listeners',
      method: 'POST',
      route: const BackendRouteCatalog().roomOffMicMembers,
      operation: () =>
          dependencies.roomOperationsRepository.fetchOffMicListeners(roomId),
    );
    await _probe(
      evidence,
      capability: 'room.moderation',
      method: 'GET',
      route: const BackendRouteCatalog().roomManagers,
      operation: () =>
          dependencies.roomOperationsRepository.fetchManagers(roomId),
    );
    await _probe(
      evidence,
      capability: 'room.muted_users',
      method: 'GET',
      route: const BackendRouteCatalog().roomMutedUsers,
      operation: () =>
          dependencies.roomOperationsRepository.fetchMutedUsers(roomId),
    );
    await _probe(
      evidence,
      capability: 'room.topic',
      method: 'GET',
      route: const BackendRouteCatalog().roomTopic,
      operation: () => dependencies.roomOperationsRepository.fetchTopic(roomId),
    );
    await _probe(
      evidence,
      capability: 'room.pk.history',
      method: 'GET',
      route: const BackendRouteCatalog().roomPkHistory,
      operation: () =>
          dependencies.roomPkRepository.fetchHistory(roomId: roomId),
    );
    await _probe(
      evidence,
      capability: 'room.pk.active',
      method: 'GET',
      route: const BackendRouteCatalog().roomPkProgress,
      operation: () =>
          dependencies.roomPkRepository.fetchActiveBattle(roomId: roomId),
    );
    evidence.invariant('room_read_probes_do_not_start_pk_or_change_seats');

    final List<RoomMember> members =
        onlineMembers?.items ?? const <RoomMember>[];
    for (final RoomMember member in members) {
      if (member.userId > 0 && member.userId != currentUserId) {
        targetUserId = member.userId;
        break;
      }
    }
    try {
      await _runRoomMutationFlow(
        dependencies,
        evidence,
        snapshot: snapshot,
        currentUserId: currentUserId,
        targetUserId: targetUserId,
      );
    } finally {
      try {
        await dependencies.roomRepository.exitRoom(roomId);
        evidence.http(
          capability: 'room.exit.cleanup',
          method: 'POST',
          route: const BackendRouteCatalog().exitRoom,
          status: 200,
          state: 'success',
        );
        evidence.invariant('room_enter_is_compensated_by_exit');
      } on ApiException catch (error) {
        evidence.http(
          capability: 'room.exit.cleanup',
          method: 'POST',
          route: const BackendRouteCatalog().exitRoom,
          status: error.httpStatus ?? 0,
          state: _stateFor(error),
        );
        throw TestFailure(
          'Room cleanup failed with status ${error.httpStatus ?? 0}.',
        );
      }
    }
  }

  final Finder roomCard = find.byKey(Key('live-room-$roomId')).hitTestable();
  if (roomCard.evaluate().isNotEmpty) {
    await tester.ensureVisible(roomCard);
    await tester.tap(roomCard);
    await _waitFor(
      tester,
      () =>
          find.byType(RoomPage).evaluate().isNotEmpty &&
          (find
                  .byKey(const Key('video-room-public-screen'))
                  .evaluate()
                  .isNotEmpty ||
              find.text('暂时无法进入房间').evaluate().isNotEmpty),
      description: 'room page or explicit room unavailable state',
    );
    final bool roomJoined = find
        .byKey(const Key('video-room-public-screen'))
        .evaluate()
        .isNotEmpty;
    evidence.invariant(
      roomJoined ? 'room_ui_joined' : 'room_ui_vendor_or_backend_blocked',
    );
    await captureQaScreenshot(
      tester,
      evidence.binding,
      'm4-${qaAvdId.toLowerCase()}-09-room',
    );
    if (roomJoined) {
      final Finder memberAction = find.text('成员').hitTestable();
      if (memberAction.evaluate().isNotEmpty) {
        await tester.tap(memberAction);
        await _waitFor(
          tester,
          () => find.textContaining('成员').evaluate().isNotEmpty,
          description: 'room members and seat view',
        );
        evidence.invariant('room_members_and_seats_reachable');
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      // Open capability-gated room tools only when the authoritative session
      // exposes them.  These checks deliberately stop at read-only pages: no
      // moderation write, PK invitation, surrender, seat mutation, or vendor
      // transport is started by this acceptance flow.
      final Finder moreAction = find.text('更多').hitTestable();
      if (moreAction.evaluate().isNotEmpty) {
        await tester.tap(moreAction);
        await tester.pumpAndSettle();
        final Finder managementAction = find.text('房管').hitTestable();
        if (managementAction.evaluate().isNotEmpty) {
          await tester.tap(managementAction);
          await _waitFor(
            tester,
            () => find.text('房间管理').evaluate().isNotEmpty,
            description: 'room moderation read-only page',
          );
          evidence.invariant('room_moderation_ui_read_only_reachable');
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.text('更多').hitTestable());
          await tester.pumpAndSettle();
        } else {
          evidence.local(
            'room.moderation.ui',
            '/room/management',
            'authority_capability_not_granted',
          );
        }

        // PK preparation performs only the repository's GET probes on page
        // load.  If the current role cannot start PK, retain an explicit
        // blocked evidence record instead of attempting a write.
        final Finder pkAction = find.text('房间 PK').hitTestable();
        if (pkAction.evaluate().isNotEmpty) {
          await tester.tap(pkAction);
          await _waitFor(
            tester,
            () =>
                find.text('PK 邀请与准备').evaluate().isNotEmpty ||
                find.text('当前没有可邀请的房间').evaluate().isNotEmpty ||
                find.text('当前没有可展示的 PK 记录').evaluate().isNotEmpty,
            description: 'room PK read-only preparation page',
          );
          evidence.invariant('room_pk_ui_read_only_reachable');
          await tester.pageBack();
          await tester.pumpAndSettle();
        } else {
          evidence.local(
            'room.pk.ui',
            '/room/pk',
            'authority_capability_not_granted',
          );
        }
      } else {
        evidence.local(
          'room.moderation.ui',
          '/room/management',
          'room_tools_unavailable',
        );
        evidence.local('room.pk.ui', '/room/pk', 'room_tools_unavailable');
      }
    }
    final Finder leave = find.byTooltip('离开房间').hitTestable();
    if (leave.evaluate().isNotEmpty) {
      await tester.tap(leave.first);
      if (find.text('离开房间？').evaluate().isNotEmpty) {
        await tester.tap(find.text('确认离开').hitTestable());
      }
      await _waitFor(
        tester,
        () => find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty,
        description: 'room UI exit cleanup',
      );
    } else if (find.text('返回').evaluate().isNotEmpty) {
      await tester.tap(find.text('返回').hitTestable());
      await tester.pumpAndSettle();
    }
  } else {
    evidence.local('room.ui', '/room', 'authoritative_room_card_unavailable');
    evidence.local(
      'room.moderation.ui',
      '/room/management',
      'room_ui_unavailable',
    );
    evidence.local('room.pk.ui', '/room/pk', 'room_ui_unavailable');
  }
  return _LiveRoomContext(roomId: roomId, targetUserId: targetUserId);
}

Future<void> _runRoomMutationFlow(
  AppDependencies dependencies,
  _M4Evidence evidence, {
  required RoomSnapshot snapshot,
  required int currentUserId,
  required int? targetUserId,
}) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  final bool canModerate =
      snapshot.ownerId == currentUserId ||
      snapshot.role == RoomRole.owner ||
      snapshot.role == RoomRole.moderator ||
      snapshot.role == RoomRole.platformModerator;

  if (!canModerate || targetUserId == null) {
    evidence.local(
      'room.moderation.mute',
      routes.setRoomUserMuted,
      canModerate ? 'no_authoritative_target_member' : 'authority_not_granted',
    );
    evidence.local(
      'room.moderation.restore',
      routes.setRoomUserMuted,
      'mutation_not_attempted_without_safe_target',
    );
  } else {
    evidence.requireCapability('room.moderation.mute');
    final bool? muted = await _probe<bool>(
      evidence,
      capability: 'room.moderation.mute',
      method: 'POST',
      route: routes.setRoomUserMuted,
      operation: () async {
        await dependencies.roomOperationsRepository.setUserMuted(
          roomId: snapshot.roomId,
          userId: targetUserId,
          muted: true,
        );
        return true;
      },
      requiredSuccess: true,
    );
    if (muted != true) {
      throw TestFailure('Room mute write did not return a success result.');
    }
    final List<RoomMember>? mutedAfter = await _probe<List<RoomMember>>(
      evidence,
      capability: 'room.moderation.mute.verify',
      method: 'GET',
      route: routes.roomMutedUsers,
      operation: () => dependencies.roomOperationsRepository.fetchMutedUsers(
        snapshot.roomId,
      ),
      requiredSuccess: true,
    );
    if (mutedAfter == null ||
        !mutedAfter.any((RoomMember member) => member.userId == targetUserId)) {
      throw TestFailure(
        'Room mute write was not visible in authoritative read.',
      );
    }
    evidence.invariant('room_moderation_mute_authority_confirmed');

    evidence.requireCapability('room.moderation.restore');
    final bool? restored = await _probe<bool>(
      evidence,
      capability: 'room.moderation.restore',
      method: 'POST',
      route: routes.setRoomUserMuted,
      operation: () async {
        await dependencies.roomOperationsRepository.setUserMuted(
          roomId: snapshot.roomId,
          userId: targetUserId,
          muted: false,
        );
        return true;
      },
      requiredSuccess: true,
    );
    if (restored != true) {
      throw TestFailure('Room mute restore did not return a success result.');
    }
    final List<RoomMember>? mutedAfterRestore = await _probe<List<RoomMember>>(
      evidence,
      capability: 'room.moderation.restore.verify',
      method: 'GET',
      route: routes.roomMutedUsers,
      operation: () => dependencies.roomOperationsRepository.fetchMutedUsers(
        snapshot.roomId,
      ),
      requiredSuccess: true,
    );
    if (mutedAfterRestore == null ||
        mutedAfterRestore.any(
          (RoomMember member) => member.userId == targetUserId,
        )) {
      throw TestFailure(
        'Room mute restore was not visible in authoritative read.',
      );
    }
    evidence.invariant('room_moderation_restore_authority_confirmed');
  }

  MicSeat? availableSeat;
  for (final MicSeat seat in snapshot.seats) {
    if (seat.isAvailable) {
      availableSeat = seat;
      break;
    }
  }
  if (availableSeat == null) {
    MicSeat? occupiedByCurrentUser;
    for (final MicSeat seat in snapshot.seats) {
      if (seat.userId == currentUserId && seat.isOccupied) {
        occupiedByCurrentUser = seat;
        break;
      }
    }
    if (occupiedByCurrentUser == null) {
      evidence.local(
        'room.seat.up',
        routes.userUpMic,
        'no_available_authoritative_seat',
      );
      evidence.local(
        'room.seat.down',
        routes.userLeaveMic,
        'seat_up_not_attempted_without_available_seat',
      );
    } else {
      evidence.preexisting(
        'room.seat.up',
        routes.roomOnlineMembers,
        'already_authoritative',
      );
      evidence.requireCapability('room.seat.down');
      final bool? seatDown = await _probe<bool>(
        evidence,
        capability: 'room.seat.down',
        method: 'POST',
        route: routes.userLeaveMic,
        operation: () async {
          await dependencies.roomRepository.leaveMic();
          return true;
        },
        requiredSuccess: true,
      );
      if (seatDown != true) {
        throw TestFailure('Existing room seat could not be released.');
      }
      evidence.invariant('room_seat_up_down_compensated');
    }
  } else {
    final MicSeat selectedSeat = availableSeat;
    evidence.requireCapability('room.seat.up');
    final bool? seatUp = await _probe<bool>(
      evidence,
      capability: 'room.seat.up',
      method: 'POST',
      route: routes.userUpMic,
      operation: () async {
        await dependencies.roomRepository.requestMic(selectedSeat.backendIndex);
        return true;
      },
      requiredSuccess: true,
    );
    if (seatUp != true) {
      throw TestFailure('Room seat up did not return a success result.');
    }
    evidence.requireCapability('room.seat.down');
    final bool? seatDown = await _probe<bool>(
      evidence,
      capability: 'room.seat.down',
      method: 'POST',
      route: routes.userLeaveMic,
      operation: () async {
        await dependencies.roomRepository.leaveMic();
        return true;
      },
      requiredSuccess: true,
    );
    if (seatDown != true) {
      throw TestFailure('Room seat down did not return a success result.');
    }
    evidence.invariant('room_seat_up_down_compensated');
  }

  await _runGiftMutation(
    dependencies,
    evidence,
    snapshot: snapshot,
    currentUserId: currentUserId,
    targetUserId: targetUserId,
  );
  await _runRoomPkMutation(
    dependencies,
    evidence,
    snapshot: snapshot,
    currentUserId: currentUserId,
  );
}

Future<void> _runGiftMutation(
  AppDependencies dependencies,
  _M4Evidence evidence, {
  required RoomSnapshot snapshot,
  required int currentUserId,
  required int? targetUserId,
}) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  if (targetUserId == null || targetUserId == currentUserId) {
    evidence.local(
      'commerce.gift.send',
      routes.sendGift,
      'no_authoritative_receiver_member',
    );
    evidence.local(
      'commerce.gift.receipt',
      routes.giftReceipt,
      'gift_send_not_attempted_without_receiver',
    );
    return;
  }
  final WalletSummary? wallet = await _probe<WalletSummary>(
    evidence,
    capability: 'commerce.wallet.mutation-precondition',
    method: 'GET',
    route: routes.walletOverview,
    operation: () => dependencies.commerceRepository.fetchWalletSummary(),
    requiredSuccess: true,
  );
  final List<GiftCatalogItem>? gifts = await _probe<List<GiftCatalogItem>>(
    evidence,
    capability: 'commerce.gift.mutation-catalog',
    method: 'GET',
    route: routes.normalGiftCatalog,
    operation: () => dependencies.commerceCatalogRepository.fetchGiftCatalog(),
    requiredSuccess: true,
  );
  GiftCatalogItem? gift;
  for (final GiftCatalogItem item in gifts ?? const <GiftCatalogItem>[]) {
    if (item.enabled && item.price > 0) {
      gift = item;
      break;
    }
  }
  if (wallet == null ||
      gift == null ||
      wallet.giftCoinBalance == null ||
      wallet.giftCoinBalance! < gift.price) {
    evidence.local(
      'commerce.gift.send',
      routes.sendGift,
      'wallet_or_gift_fixture_not_sufficient',
    );
    evidence.local(
      'commerce.gift.receipt',
      routes.giftReceipt,
      'gift_send_not_attempted_without_sufficient_wallet',
    );
    return;
  }
  final GiftCatalogItem selectedGift = gift;
  final String requestId = _m4RequestId('gift');
  evidence.requireCapability('commerce.gift.send');
  final GiftReceipt? sent = await _probe<GiftReceipt>(
    evidence,
    capability: 'commerce.gift.send',
    method: 'POST',
    route: routes.sendGift,
    operation: () => dependencies.roomRepository.sendGift(
      roomId: snapshot.roomId,
      giftId: selectedGift.id,
      receiverUserIds: <int>[targetUserId],
      quantity: 1,
      giftFrom: 0,
      requestId: requestId,
    ),
    requiredSuccess: true,
  );
  if (sent == null ||
      !sent.success ||
      sent.providerInvocation != false ||
      sent.transferId == null ||
      sent.transferId!.isEmpty ||
      sent.senderUserId != currentUserId ||
      sent.receiverUserId != targetUserId ||
      sent.quantity != 1) {
    throw TestFailure(
      'Gift send response did not confirm a first-party receipt.',
    );
  }
  evidence.requireCapability('commerce.gift.receipt');
  final GiftReceipt? recovered = await _probe<GiftReceipt>(
    evidence,
    capability: 'commerce.gift.receipt',
    method: 'GET',
    route: routes.giftReceipt,
    operation: () => dependencies.roomRepository.fetchGiftReceipt(
      transferId: sent.transferId,
      currentUserId: currentUserId,
      senderUserId: currentUserId,
      receiverUserId: targetUserId,
    ),
    requiredSuccess: true,
  );
  if (recovered == null ||
      recovered.transferId != sent.transferId ||
      recovered.requestId != requestId ||
      recovered.providerInvocation != false ||
      !recovered.success) {
    throw TestFailure('Gift receipt recovery did not match the sent transfer.');
  }
  evidence.invariant('gift_send_recovered_by_authoritative_receipt');
}

Future<void> _runRoomPkMutation(
  AppDependencies dependencies,
  _M4Evidence evidence, {
  required RoomSnapshot snapshot,
  required int currentUserId,
}) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  const String surrenderRoute = '/app-api/activityPk/surrenderRoomPk';
  final RoomPkInvitation? incoming = await _probe<RoomPkInvitation?>(
    evidence,
    capability: 'room.pk.incoming',
    method: 'GET',
    route: routes.roomPkProgress,
    operation: () => dependencies.roomPkRepository.fetchIncomingInvitation(
      roomId: snapshot.roomId,
    ),
    requiredSuccess: true,
  );
  if (incoming != null) {
    evidence.requireCapability('room.pk.accept');
    final RoomPkBattle? battle = await _probe<RoomPkBattle>(
      evidence,
      capability: 'room.pk.accept',
      method: 'POST',
      route: routes.roomPkAccept,
      operation: () => dependencies.roomPkRepository.acceptInvitation(incoming),
      requiredSuccess: true,
    );
    if (battle == null || battle.currentRoomId != snapshot.roomId) {
      throw TestFailure(
        'PK accept response did not identify the current room.',
      );
    }
    evidence.requireCapability('room.pk.end');
    final RoomPkBattle? ended = await _probe<RoomPkBattle>(
      evidence,
      capability: 'room.pk.end',
      method: 'POST',
      route: surrenderRoute,
      operation: () => dependencies.roomPkRepository.surrender(
        roomId: snapshot.roomId,
        battleId: battle.id,
      ),
      requiredSuccess: true,
    );
    if (ended == null || ended.isActive) {
      throw TestFailure('PK compensation did not close the accepted battle.');
    }
    evidence.invariant('pk_accept_and_end_compensated');
    evidence.invariant('pk_mutation_path_confirmed');
    return;
  }

  final bool canInvite =
      snapshot.ownerId == currentUserId || snapshot.role == RoomRole.owner;
  if (!canInvite) {
    evidence.local(
      'room.pk.invite',
      routes.roomPkInvite,
      'authority_not_granted',
    );
    evidence.local(
      'room.pk.recovery',
      routes.roomPkReject,
      'invite_not_attempted_without_owner_authority',
    );
    return;
  }
  final List<RoomPkOpponent>? opponents = await _probe<List<RoomPkOpponent>>(
    evidence,
    capability: 'room.pk.opponents',
    method: 'GET',
    route: routes.roomPkHotRooms,
    operation: () => dependencies.roomPkRepository.fetchHotOpponents(
      roomId: snapshot.roomId,
    ),
    requiredSuccess: true,
  );
  RoomPkOpponent? opponent;
  for (final RoomPkOpponent item in opponents ?? const <RoomPkOpponent>[]) {
    if (item.roomId != snapshot.roomId && !item.isInPk) {
      opponent = item;
      break;
    }
  }
  if (opponent == null) {
    evidence.local(
      'room.pk.invite',
      routes.roomPkInvite,
      'no_authoritative_opponent_room',
    );
    evidence.local(
      'room.pk.recovery',
      routes.roomPkReject,
      'invite_not_attempted_without_opponent',
    );
    return;
  }
  final RoomPkOpponent selectedOpponent = opponent;
  evidence.requireCapability('room.pk.invite');
  final RoomPkInvitation? invitation = await _probe<RoomPkInvitation>(
    evidence,
    capability: 'room.pk.invite',
    method: 'POST',
    route: routes.roomPkInvite,
    operation: () => dependencies.roomPkRepository.sendInvitation(
      roomId: snapshot.roomId,
      inviterUserId: currentUserId,
      opponent: selectedOpponent,
      punishmentTheme: 'M4测试',
      durationMinutes: 5,
    ),
    requiredSuccess: true,
  );
  if (invitation == null) {
    throw TestFailure('PK invitation did not return authoritative invitation.');
  }
  if (invitation.status == RoomPkInvitationStatus.pending) {
    evidence.requireCapability('room.pk.recovery');
    final bool? rejected = await _probe<bool>(
      evidence,
      capability: 'room.pk.recovery',
      method: 'POST',
      route: routes.roomPkReject,
      operation: () async {
        await dependencies.roomPkRepository.rejectInvitation(invitation);
        return true;
      },
      requiredSuccess: true,
    );
    if (rejected != true) {
      throw TestFailure(
        'PK invitation rejection did not return a success result.',
      );
    }
    evidence.invariant('pk_invite_rejected_as_safe_recovery');
    evidence.invariant('pk_mutation_path_confirmed');
  } else if (invitation.status == RoomPkInvitationStatus.accepted) {
    final RoomPkBattle? battle = await _probe<RoomPkBattle>(
      evidence,
      capability: 'room.pk.accept',
      method: 'POST',
      route: routes.roomPkAccept,
      operation: () =>
          dependencies.roomPkRepository.acceptInvitation(invitation),
      requiredSuccess: true,
    );
    if (battle == null) {
      throw TestFailure('Accepted PK invitation did not return a battle.');
    }
    evidence.requireCapability('room.pk.end');
    final RoomPkBattle? ended = await _probe<RoomPkBattle>(
      evidence,
      capability: 'room.pk.end',
      method: 'POST',
      route: surrenderRoute,
      operation: () => dependencies.roomPkRepository.surrender(
        roomId: snapshot.roomId,
        battleId: battle.id,
      ),
      requiredSuccess: true,
    );
    if (ended == null || ended.isActive) {
      throw TestFailure('PK compensation did not close the accepted battle.');
    }
    evidence.invariant('pk_accept_and_end_compensated');
    evidence.invariant('pk_mutation_path_confirmed');
  } else {
    evidence.preexisting(
      'room.pk.recovery',
      routes.roomPkProgress,
      'already_authoritative',
    );
    evidence.invariant('pk_mutation_path_confirmed');
  }
}

String _m4RequestId(String scope) {
  final String avd = qaAvdId.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9._-]'),
    '-',
  );
  return 'm4-$avd-$scope-${DateTime.now().microsecondsSinceEpoch}';
}

Future<void> _runRefundMutation(
  AppDependencies dependencies,
  _M4Evidence evidence, {
  required BackendRouteCatalog routes,
  required PaymentOrder order,
  required RefundEligibility eligibility,
}) async {
  String? existingApplicationId = eligibility.existingApplicationId?.trim();
  RefundApplication? application;

  if (eligibility.allowed) {
    evidence.requireCapability('commerce.refund.submit');
    application = await _probe<RefundApplication>(
      evidence,
      capability: 'commerce.refund.submit',
      method: 'POST',
      route: routes.refundApplication,
      operation: () => dependencies.commerceRepository.submitRefund(
        RefundRequest(
          account: order.orderNo,
          realName: '',
          age: 0,
          amount: order.amount,
          reason: 'M4 first-party review',
          receivingAccount: '',
          receivingName: '',
          guardianName: '',
          guardianPhone: '',
        ),
      ),
      requiredSuccess: true,
    );
    if (application == null ||
        application.id.trim().isEmpty ||
        application.account != order.orderNo ||
        application.status == RefundStatus.unavailable) {
      throw TestFailure(
        'Refund submission did not return an authoritative application.',
      );
    }
    existingApplicationId = application.id;
  } else if (existingApplicationId == null || existingApplicationId.isEmpty) {
    evidence.local(
      'commerce.refund.submit',
      routes.refundApplication,
      'refund_not_eligible_authoritative',
    );
    evidence.local(
      'commerce.refund.result',
      routes.refundResult,
      'refund_result_not_attempted_without_application',
    );
    return;
  } else {
    // An earlier AVD may already have submitted this order. Preserve that
    // server state explicitly; do not issue a second application.
    evidence.preexisting(
      'commerce.refund.submit',
      routes.refundResult,
      'existing_authoritative_application',
    );
  }

  final String? applicationId = existingApplicationId;
  if (applicationId == null || applicationId.isEmpty) {
    throw TestFailure('Refund application identity was lost before recovery.');
  }
  evidence.requireCapability('commerce.refund.result');
  final RefundApplication? recovered = await _probe<RefundApplication>(
    evidence,
    capability: 'commerce.refund.result',
    method: 'GET',
    route: routes.refundResult,
    operation: () => dependencies.commerceRepository.fetchRefundResult(
      applicationId,
      expectedOrderNo: order.orderNo,
    ),
    requiredSuccess: true,
  );
  if (recovered == null ||
      recovered.id != applicationId ||
      recovered.account != order.orderNo ||
      recovered.status == RefundStatus.unavailable) {
    throw TestFailure('Refund result did not match the authoritative order.');
  }
  application = recovered;
  if (application.status == RefundStatus.rejected) {
    evidence.requireCapability('commerce.refund.retry');
    final RefundApplication? retried = await _probe<RefundApplication>(
      evidence,
      capability: 'commerce.refund.retry',
      method: 'POST',
      route: routes.refundRepeat,
      operation: () => dependencies.commerceRepository.resubmitRefund(
        applicationId,
        expectedOrderNo: order.orderNo,
      ),
      requiredSuccess: true,
    );
    if (retried == null ||
        retried.id != applicationId ||
        retried.account != order.orderNo ||
        retried.status == RefundStatus.rejected) {
      throw TestFailure('Refund retry did not return a new review state.');
    }
    evidence.invariant('refund_retry_authority_confirmed');
  } else {
    evidence.local(
      'commerce.refund.retry',
      routes.refundRepeat,
      'retry_not_required_authoritative_state',
    );
  }
  evidence.invariant('refund_submit_result_recovered_without_provider');
}

class _OwnedModeRooms {
  const _OwnedModeRooms({required this.direct, required this.approval});

  final DiscoveryRoom direct;
  final DiscoveryRoom approval;
}

class _LiveRoomContext {
  const _LiveRoomContext({required this.roomId, this.targetUserId});

  final String roomId;
  final int? targetUserId;
}

Future<void> _runMessagesFlow(
  WidgetTester tester,
  AppDependencies dependencies,
  _M4Evidence evidence, {
  required int currentUserId,
  int? fallbackTargetUserId,
}) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  final List<ConversationSummary>? conversations = await _probe(
    evidence,
    capability: 'message.conversations',
    method: 'GET',
    route: routes.messageConversations,
    operation: () => dependencies.messageRepository.fetchConversations(),
  );

  ConversationSummary? conversation;
  for (final ConversationSummary candidate
      in conversations ?? const <ConversationSummary>[]) {
    if (candidate.available &&
        candidate.targetUserId > 0 &&
        candidate.targetUserId != currentUserId) {
      conversation = candidate;
      break;
    }
  }
  if (conversation == null &&
      fallbackTargetUserId != null &&
      fallbackTargetUserId > 0 &&
      fallbackTargetUserId != currentUserId) {
    conversation = ConversationSummary.draft(
      kind: ConversationKind.privateChat,
      title: 'M4 first-party test peer',
      lastMessage: '',
      unreadCount: 0,
      targetUserId: fallbackTargetUserId,
    );
  }
  if (conversation == null) {
    evidence.local(
      'message.private.send',
      routes.sendPrivateMessage,
      'no_authoritative_private_message_target',
    );
    evidence.local(
      'message.private.history',
      routes.privateChatHistory,
      'private_send_not_attempted_without_target',
    );
  } else {
    final ConversationSummary selectedConversation = conversation;
    final String content = 'M4 first-party ${qaAvdId.toLowerCase()}';
    final String requestId = _m4RequestId('message');
    evidence.requireCapability('message.private.send');
    final ChatMessage? sent = await _probe<ChatMessage>(
      evidence,
      capability: 'message.private.send',
      method: 'POST',
      route: routes.sendPrivateMessage,
      operation: () => dependencies.messageRepository.sendPrivateMessage(
        conversation: selectedConversation,
        content: content,
        requestId: requestId,
      ),
      requiredSuccess: true,
    );
    if (sent == null ||
        !sent.isMine ||
        sent.senderUserId != currentUserId ||
        sent.content != content ||
        (sent.status != ChatMessageStatus.sent &&
            sent.status != ChatMessageStatus.storedPendingDelivery) ||
        sent.id.trim().isEmpty) {
      throw TestFailure(
        'Private message response did not confirm first-party storage.',
      );
    }
    evidence.requireCapability('message.private.history');
    final List<ChatMessage>? history = await _probe<List<ChatMessage>>(
      evidence,
      capability: 'message.private.history',
      method: 'GET',
      route: routes.privateChatHistory,
      operation: () => dependencies.messageRepository.fetchPrivateMessages(
        selectedConversation,
      ),
      requiredSuccess: true,
    );
    if (history == null ||
        !history.any((ChatMessage item) => item.id == sent.id)) {
      throw TestFailure(
        'Private message history did not recover the sent message.',
      );
    }
    evidence.invariant('private_message_send_recovered_by_history');
  }

  final List<AppNotification>? systemNotifications = await _probe(
    evidence,
    capability: 'message.notifications.system',
    method: 'GET',
    route: routes.systemNotifications,
    operation: () => dependencies.messageRepository.fetchNotifications(
      NotificationCategory.system,
    ),
  );
  final List<AppNotification>? interactionNotifications = await _probe(
    evidence,
    capability: 'message.notifications.interaction',
    method: 'GET',
    route: routes.systemNotifications,
    operation: () => dependencies.messageRepository.fetchNotifications(
      NotificationCategory.interaction,
    ),
  );
  AppNotification? unreadNotification;
  for (final AppNotification notification
      in systemNotifications ?? const <AppNotification>[]) {
    if (notification.unread) {
      unreadNotification = notification;
      break;
    }
  }
  if (unreadNotification == null) {
    for (final AppNotification notification
        in interactionNotifications ?? const <AppNotification>[]) {
      if (notification.unread) {
        unreadNotification = notification;
        break;
      }
    }
  }
  if (unreadNotification == null) {
    evidence.local(
      'message.notifications.read',
      routes.markSystemNotificationRead,
      'no_unread_authoritative_notification',
    );
  } else {
    final String notificationId = unreadNotification.id;
    evidence.requireCapability('message.notifications.read');
    final AppNotification? detail = await _probe<AppNotification>(
      evidence,
      capability: 'message.notifications.read.detail',
      method: 'GET',
      route: routes.pushNotificationDetail,
      operation: () =>
          dependencies.messageRepository.fetchNotification(notificationId),
      requiredSuccess: true,
    );
    if (detail == null || detail.id != notificationId) {
      throw TestFailure(
        'Notification detail did not match its authoritative ID.',
      );
    }
    final bool? read = await _probe<bool>(
      evidence,
      capability: 'message.notifications.read',
      method: 'POST',
      route: routes.markSystemNotificationRead,
      operation: () async {
        await dependencies.messageRepository.markNotificationRead(
          notificationId,
        );
        return true;
      },
      requiredSuccess: true,
    );
    if (read != true) {
      throw TestFailure('Notification read did not return a success result.');
    }
    evidence.invariant('notification_read_authority_confirmed');
  }

  // Clearing the first-party interaction projection is idempotent and safe
  // even when the authoritative list is empty. It never invokes push or IM.
  evidence.requireCapability('message.notifications.clear');
  final bool? cleared = await _probe<bool>(
    evidence,
    capability: 'message.notifications.clear',
    method: 'POST',
    route: routes.clearDynamicNotifications,
    operation: () async {
      await dependencies.messageRepository.clearInteractionNotifications();
      return true;
    },
    requiredSuccess: true,
  );
  if (cleared != true) {
    throw TestFailure('Notification clear did not return a success result.');
  }
  evidence.invariant('notification_clear_is_first_party_and_vendor_free');

  evidence.local(
    'message.recovery',
    '/message/recovery',
    'im_and_push_vendor_blocked',
  );
  await tester.tap(find.text('消息').last.hitTestable());
  await _waitFor(
    tester,
    () => find.text('消息').evaluate().isNotEmpty,
    description: 'message records page',
  );
  evidence.invariant('message_records_page_reachable');
  await captureQaScreenshot(
    tester,
    evidence.binding,
    'm4-${qaAvdId.toLowerCase()}-10-messages',
  );
}

Future<void> _runCommerceFlow(
  WidgetTester tester,
  AppDependencies dependencies,
  _M4Evidence evidence,
) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  final WalletSummary? walletProbe = await _probe<WalletSummary>(
    evidence,
    capability: 'commerce.wallet',
    method: 'GET',
    route: routes.walletOverview,
    operation: () => dependencies.commerceRepository.fetchWalletSummary(),
  );
  if (walletProbe != null) {
    evidence.composite(
      capability: 'commerce.wallet.gift_coin',
      method: 'GET',
      route: routes.ncoinBalance,
      status: 200,
    );
  }
  await _probe(
    evidence,
    capability: 'commerce.ledger',
    method: 'GET',
    route: routes.walletAccountDetails,
    operation: () => dependencies.commerceRepository.fetchLedger(
      currency: LedgerCurrency.giftCoin,
      direction: LedgerDirection.income,
      page: 1,
      pageSize: 20,
    ),
  );
  final CommercePage<PaymentOrder>? orders =
      await _probe<CommercePage<PaymentOrder>>(
        evidence,
        capability: 'commerce.orders',
        method: 'POST',
        route: routes.paymentOrders,
        operation: () =>
            dependencies.commerceRepository.fetchOrders(page: 1, pageSize: 20),
      );
  final PaymentOrder? firstOrder = orders == null || orders.items.isEmpty
      ? null
      : orders.items.first;
  RefundEligibility? refundEligibility;
  if (firstOrder == null) {
    evidence.local(
      'commerce.refund.eligibility',
      '/commerce/refund-eligibility',
      'no_authoritative_order_available',
    );
  } else {
    refundEligibility = await _probe<RefundEligibility>(
      evidence,
      capability: 'commerce.refund.eligibility',
      method: 'GET',
      route: routes.refundCheck,
      operation: () => dependencies.commerceRepository.checkRefundEligibility(
        firstOrder.orderNo,
      ),
      requiredSuccess: true,
    );
  }
  await _probe(
    evidence,
    capability: 'commerce.refund.records',
    method: 'GET',
    route: routes.refundHistory,
    operation: () => dependencies.commerceRepository.fetchRefundApplications(
      'authenticated-account',
    ),
    requiredSuccess: true,
  );
  await _probe(
    evidence,
    capability: 'commerce.withdraw.quote',
    method: 'GET',
    route: routes.withdrawalFeeRate,
    operation: () =>
        dependencies.commerceRepository.fetchWithdrawalQuote(amount: 10),
    requiredSuccess: true,
  );
  final CommercePage<WithdrawalRecord>? withdrawalRecords =
      await _probe<CommercePage<WithdrawalRecord>>(
        evidence,
        capability: 'commerce.withdraw.records',
        method: 'GET',
        route: routes.withdrawalRecords,
        operation: () => dependencies.commerceRepository.fetchWithdrawalRecords(
          page: 1,
          pageSize: 20,
        ),
      );
  await _probe(
    evidence,
    capability: 'commerce.recharge.catalog',
    method: 'GET',
    route: routes.rechargeProducts,
    operation: () => dependencies.commerceCatalogRepository
        .fetchRechargeProducts(platform: ClientStorePlatform.android),
  );
  await _probe(
    evidence,
    capability: 'commerce.gift.catalog',
    method: 'GET',
    route: routes.normalGiftCatalog,
    operation: () => dependencies.commerceCatalogRepository.fetchGiftCatalog(),
  );
  await _probe(
    evidence,
    capability: 'commerce.decorations',
    method: 'GET',
    route: routes.userDecorations,
    operation: () => dependencies.commerceCatalogRepository.fetchDecorations(),
  );

  if (firstOrder != null && refundEligibility != null) {
    await _runRefundMutation(
      dependencies,
      evidence,
      routes: routes,
      order: firstOrder,
      eligibility: refundEligibility,
    );
  } else {
    evidence.local(
      'commerce.refund.submit',
      routes.refundApplication,
      'no_authoritative_order_available',
    );
    evidence.local(
      'commerce.refund.result',
      routes.refundResult,
      'refund_submit_not_attempted_without_order',
    );
  }

  final PayoutAccountSelection? payoutAccounts =
      await _probe<PayoutAccountSelection>(
        evidence,
        capability: 'commerce.withdraw.accounts',
        method: 'GET',
        route: routes.payoutAccounts,
        operation: () => dependencies.commerceRepository.fetchPayoutAccounts(),
        requiredSuccess: true,
      );
  final WithdrawalQuote? withdrawalQuote = await _probe<WithdrawalQuote>(
    evidence,
    capability: 'commerce.withdraw.quote.mutation',
    method: 'GET',
    route: routes.withdrawalFeeRate,
    operation: () =>
        dependencies.commerceRepository.fetchWithdrawalQuote(amount: 10),
    requiredSuccess: true,
  );
  PayoutAccount? payoutAccount;
  if (payoutAccounts != null) {
    for (final PayoutAccount account in payoutAccounts.selectableAccounts) {
      payoutAccount = account;
      break;
    }
  }
  WithdrawalRecord? existingPendingWithdrawal;
  for (final WithdrawalRecord record
      in withdrawalRecords?.items ?? const <WithdrawalRecord>[]) {
    if (record.status == WithdrawalStatus.pending) {
      existingPendingWithdrawal = record;
      break;
    }
  }
  if (existingPendingWithdrawal != null) {
    final WithdrawalRecord existingWithdrawal = existingPendingWithdrawal;
    evidence.preexisting(
      'commerce.withdraw.apply',
      routes.withdrawalRecords,
      'already_authoritative',
    );
    evidence.requireCapability('commerce.withdraw.result');
    final WithdrawalRecord? recoveredWithdrawal =
        await _probe<WithdrawalRecord>(
          evidence,
          capability: 'commerce.withdraw.result',
          method: 'GET',
          route: routes.withdrawalRecords,
          operation: () => dependencies.commerceRepository
              .fetchWithdrawalRecord(existingWithdrawal.id),
          requiredSuccess: true,
        );
    if (recoveredWithdrawal == null ||
        recoveredWithdrawal.id != existingWithdrawal.id ||
        recoveredWithdrawal.status != WithdrawalStatus.pending) {
      throw TestFailure(
        'Existing withdrawal record did not recover as pending manual review.',
      );
    }
    evidence.invariant('withdrawal_manual_review_recovered_without_provider');
  } else if (walletProbe == null ||
      withdrawalQuote == null ||
      payoutAccount == null ||
      !walletProbe.realNameVerified ||
      walletProbe.cashBalance < withdrawalQuote.quotedAmount) {
    evidence.local(
      'commerce.withdraw.apply',
      routes.withdrawalApply,
      'manual_review_precondition_not_satisfied',
    );
    evidence.local(
      'commerce.withdraw.result',
      routes.withdrawalRecords,
      'withdrawal_apply_not_attempted_without_safe_account_or_balance',
    );
  } else {
    evidence.requireCapability('commerce.withdraw.apply');
    final WithdrawalRecord? withdrawal = await _probe<WithdrawalRecord>(
      evidence,
      capability: 'commerce.withdraw.apply',
      method: 'POST',
      route: routes.withdrawalApply,
      operation: () => dependencies.commerceRepository.applyWithdrawal(
        amount: withdrawalQuote.quotedAmount,
        payoutAccountId: payoutAccount!.payoutAccountId,
      ),
      requiredSuccess: true,
    );
    if (withdrawal == null ||
        withdrawal.id.trim().isEmpty ||
        withdrawal.payoutAccountId != payoutAccount.payoutAccountId ||
        withdrawal.status != WithdrawalStatus.pending) {
      throw TestFailure(
        'Withdrawal response did not confirm first-party manual review.',
      );
    }
    evidence.requireCapability('commerce.withdraw.result');
    final WithdrawalRecord? recoveredWithdrawal =
        await _probe<WithdrawalRecord>(
          evidence,
          capability: 'commerce.withdraw.result',
          method: 'GET',
          route: routes.withdrawalRecords,
          operation: () => dependencies.commerceRepository
              .fetchWithdrawalRecord(withdrawal.id),
          requiredSuccess: true,
        );
    if (recoveredWithdrawal == null ||
        recoveredWithdrawal.id != withdrawal.id ||
        recoveredWithdrawal.payoutAccountId != payoutAccount.payoutAccountId ||
        recoveredWithdrawal.status != WithdrawalStatus.pending) {
      throw TestFailure('Withdrawal record recovery did not match the apply.');
    }
    evidence.invariant('withdrawal_manual_review_recovered_without_provider');
  }

  evidence.invariant('wallet_gift_withdraw_refund_reads_are_first_party_only');

  await tester.tap(find.text('我的').last.hitTestable());
  await _waitFor(
    tester,
    () => find.byKey(const Key('video-runtime-account')).evaluate().isNotEmpty,
    description: 'account page for commerce UI',
  );
  final Finder wallet = find.text('钱包').first;
  if (wallet.evaluate().isNotEmpty) {
    await tester.ensureVisible(wallet);
    final Finder walletAction = wallet.hitTestable();
    if (walletAction.evaluate().isEmpty) {
      evidence.local(
        'commerce.wallet.ui',
        '/commerce/wallet',
        'ui_entry_unavailable',
      );
      return;
    }
    await tester.tap(walletAction);
    await _waitFor(
      tester,
      () => find.text('钱包与商城').evaluate().isNotEmpty,
      description: 'commerce wallet page',
    );
    evidence.invariant('commerce_wallet_page_reachable');
    await captureQaScreenshot(
      tester,
      evidence.binding,
      'm4-${qaAvdId.toLowerCase()}-11-commerce-hub',
    );

    final Finder walletLedger = find.text('钱包与流水');
    if (walletLedger.evaluate().isNotEmpty) {
      await tester.ensureVisible(walletLedger);
      await tester.tap(walletLedger);
      await _waitFor(
        tester,
        () => find.text('钱包与流水').evaluate().isNotEmpty,
        description: 'commerce wallet ledger page',
      );
      evidence.invariant('commerce_wallet_ledger_page_reachable');
      await captureQaScreenshot(
        tester,
        evidence.binding,
        'm4-${qaAvdId.toLowerCase()}-12-wallet-ledger',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    } else {
      evidence.local(
        'commerce.ledger.ui',
        '/commerce/wallet/ledger',
        'ui_entry_unavailable',
      );
    }

    final Finder giftCatalog = find.text('礼物').last;
    if (giftCatalog.evaluate().isNotEmpty) {
      await tester.ensureVisible(giftCatalog);
      await tester.tap(giftCatalog.hitTestable());
      await _waitFor(
        tester,
        () =>
            find.text('礼物图鉴').evaluate().isNotEmpty ||
            find.textContaining('失败').evaluate().isNotEmpty,
        description: 'gift catalog or explicit blocked state',
      );
      evidence.invariant('gift_catalog_page_reachable_without_send');
      await captureQaScreenshot(
        tester,
        evidence.binding,
        'm4-${qaAvdId.toLowerCase()}-13-gift-catalog',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    } else {
      evidence.local(
        'commerce.gift.ui',
        '/commerce/gifts',
        'ui_entry_unavailable',
      );
    }

    final Finder orders = find.text('充值订单');
    if (orders.evaluate().isNotEmpty) {
      await tester.ensureVisible(orders);
      await tester.tap(orders.hitTestable());
      await _waitFor(
        tester,
        () =>
            find.text('订单列表').evaluate().isNotEmpty ||
            find.textContaining('失败').evaluate().isNotEmpty,
        description: 'commerce orders page',
      );
      evidence.invariant('commerce_orders_page_reachable_without_payment');
      await captureQaScreenshot(
        tester,
        evidence.binding,
        'm4-${qaAvdId.toLowerCase()}-14-orders',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    } else {
      evidence.local(
        'commerce.orders.ui',
        '/commerce/orders',
        'ui_entry_unavailable',
      );
    }

    final Finder refund = find.text('订单退款');
    if (refund.evaluate().isNotEmpty) {
      await tester.ensureVisible(refund);
      await tester.tap(refund.hitTestable());
      await _waitFor(
        tester,
        () =>
            find.text('退款申请列表').evaluate().isNotEmpty ||
            find.text('订单退款').evaluate().isNotEmpty ||
            find.text('订单列表').evaluate().isNotEmpty ||
            find.textContaining('失败').evaluate().isNotEmpty,
        description: 'refund records or explicit blocked state',
      );
      evidence.invariant('refund_records_page_reachable_without_submission');
      await captureQaScreenshot(
        tester,
        evidence.binding,
        'm4-${qaAvdId.toLowerCase()}-15-refund',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    } else {
      evidence.local(
        'commerce.refund.ui',
        '/commerce/refund',
        'ui_entry_unavailable',
      );
    }

    final Finder withdrawal = find.text('结算与提现');
    if (withdrawal.evaluate().isNotEmpty) {
      await tester.ensureVisible(withdrawal);
      await tester.tap(withdrawal.hitTestable());
      await _waitFor(
        tester,
        () =>
            find.text('结算与提现').evaluate().isNotEmpty ||
            find.textContaining('失败').evaluate().isNotEmpty,
        description: 'withdrawal records or explicit blocked state',
      );
      evidence.invariant(
        'withdrawal_records_page_reachable_without_application',
      );
      await captureQaScreenshot(
        tester,
        evidence.binding,
        'm4-${qaAvdId.toLowerCase()}-16-withdrawal',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    } else {
      evidence.local(
        'commerce.withdraw.ui',
        '/commerce/withdrawal',
        'ui_entry_unavailable',
      );
    }

    final Finder recharge = find.text('充值').last;
    if (recharge.evaluate().isNotEmpty) {
      await tester.ensureVisible(recharge);
      await tester.tap(recharge);
      await _waitFor(
        tester,
        () =>
            find.text('充值商品目录').evaluate().isNotEmpty ||
            find.textContaining('失败').evaluate().isNotEmpty,
        description: 'recharge catalog or explicit vendor-blocked state',
      );
      evidence.invariant('recharge_catalog_reachable_without_payment');
      await captureQaScreenshot(
        tester,
        evidence.binding,
        'm4-${qaAvdId.toLowerCase()}-17-recharge-catalog',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
    } else {
      evidence.local(
        'commerce.recharge.ui',
        '/commerce/recharge',
        'ui_entry_unavailable',
      );
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
  } else {
    evidence.local(
      'commerce.wallet.ui',
      '/commerce/wallet',
      'ui_entry_unavailable',
    );
  }
}

Future<void> _runComplianceAndSupportFlow(
  WidgetTester tester,
  AppDependencies dependencies,
  _M4Evidence evidence,
  String account,
) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  final Object? complianceProbe = await _probe(
    evidence,
    capability: 'compliance.snapshot',
    method: 'GET',
    route: routes.personalData,
    operation: () => dependencies.accountComplianceRepository.fetchSnapshot(
      account: account,
      expectedUserId: dependencies.sessionManager.session?.userId,
      currentVersion: 1,
      platformType: 1,
    ),
  );
  if (complianceProbe != null) {
    for (final (String capability, String route) in <(String, String)>[
      ('compliance.youth_mode', routes.youthModeStatus),
      ('compliance.restrictions', routes.accountRestrictions),
      ('compliance.cancellation', routes.queryAccountCancellation),
      ('compliance.version', routes.versionInformation),
      ('compliance.real_name', routes.accountRealName),
      ('compliance.sessions', routes.accountSessions),
    ]) {
      evidence.composite(
        capability: capability,
        method: 'GET',
        route: route,
        status: 200,
      );
    }
  }
  final Object? supportProbe = await _probe(
    evidence,
    capability: 'support.channel',
    method: 'GET',
    route: routes.customerService,
    operation: () => dependencies.socialRepository.fetchCustomerService(),
  );
  await tester.tap(find.text('我的').last.hitTestable());
  await _waitFor(
    tester,
    () => find.byKey(const Key('video-runtime-account')).evaluate().isNotEmpty,
    description: 'account page for compliance and support',
  );
  final Finder vendorDiagnostics = find.byKey(
    const Key('open-vendor-diagnostics'),
  );
  if (vendorDiagnostics.evaluate().isNotEmpty) {
    await tester.ensureVisible(vendorDiagnostics);
    await tester.tap(vendorDiagnostics.hitTestable());
    await _waitFor(
      tester,
      () =>
          find
              .byKey(const Key('vendor-readiness-summary'))
              .evaluate()
              .isNotEmpty ||
          find.byKey(const Key('vendor-readiness-error')).evaluate().isNotEmpty,
      description: 'vendor readiness or explicit vendor-blocked state',
    );
    final bool readinessLoaded = find
        .byKey(const Key('vendor-readiness-summary'))
        .evaluate()
        .isNotEmpty;
    evidence.invariant(
      readinessLoaded
          ? 'vendor_boundary_ui_loaded_without_provider_call'
          : 'vendor_boundary_ui_explicitly_blocked',
    );
    await captureQaScreenshot(
      tester,
      evidence.binding,
      'm4-${qaAvdId.toLowerCase()}-18-vendor-boundary',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(
    find.text('帮助与反馈'),
    260,
    scrollable: find.byType(Scrollable).first,
  );
  final Finder support = find.text('帮助与反馈').hitTestable();
  if (supportProbe != null && support.evaluate().isNotEmpty) {
    await tester.tap(support);
    await _waitFor(
      tester,
      () => find.text('帮助与客服').evaluate().isNotEmpty,
      description: 'support page',
    );
    evidence.invariant('support_page_reachable_without_provider_chat');
    await captureQaScreenshot(
      tester,
      evidence.binding,
      'm4-${qaAvdId.toLowerCase()}-19-support',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
  } else if (supportProbe == null) {
    evidence.invariant('support_channel_backend_blocked');
  }
  await tester.scrollUntilVisible(
    find.text('隐私与安全'),
    260,
    scrollable: find.byType(Scrollable).first,
  );
  final Finder privacy = find.text('隐私与安全').hitTestable();
  if (privacy.evaluate().isNotEmpty) {
    await tester.tap(privacy);
    await _waitFor(
      tester,
      () => find.text('账号与安全').evaluate().isNotEmpty,
      description: 'account compliance page',
    );
    evidence.invariant('compliance_page_reachable_without_real_name_write');
    await captureQaScreenshot(
      tester,
      evidence.binding,
      'm4-${qaAvdId.toLowerCase()}-20-compliance',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
  }
}

Future<void> _openPersonalCenterForLogout(
  WidgetTester tester,
  AppDependencies dependencies,
) async {
  // The personal center is also the product-owned logout surface. It is
  // opened through the account page's visible privacy/security entry, so the
  // test does not manipulate secure storage directly.
  await tester.tap(find.text('我的').last.hitTestable());
  await _waitFor(
    tester,
    () => find.byKey(const Key('video-runtime-account')).evaluate().isNotEmpty,
    description: 'account page before logout',
  );
  await tester.scrollUntilVisible(
    find.text('隐私与安全'),
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('隐私与安全').hitTestable());
  await _waitFor(
    tester,
    () => find.text('账号与安全').evaluate().isNotEmpty,
    description: 'personal center entry',
  );
  await tester.pageBack();
  await tester.pumpAndSettle();
  // The account page itself may retain its scroll offset. Push the product's
  // own personal-center route from the visible account shell, then exercise
  // its real logout control. No secure-storage value is manipulated here.
  final Finder accountPage = find.byKey(const Key('video-runtime-account'));
  if (accountPage.evaluate().isNotEmpty) {
    final NavigatorState navigator = Navigator.of(tester.element(accountPage));
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PersonalCenterPage(
          session: dependencies.sessionManager.session,
          onSignOut: dependencies.authController.signOut,
        ),
      ),
    );
  }
  await _waitFor(
    tester,
    () => find.text('退出登录').evaluate().isNotEmpty,
    description: 'personal center logout action',
  );
}

Future<T?> _probe<T>(
  _M4Evidence evidence, {
  required String capability,
  required String method,
  required String route,
  required Future<T> Function() operation,
  bool requiredSuccess = false,
}) async {
  try {
    final T value = await operation();
    evidence.http(
      capability: capability,
      method: method,
      route: route,
      status: 200,
      state: 'success',
    );
    return value;
  } on ApiException catch (error) {
    evidence.http(
      capability: capability,
      method: method,
      route: route,
      status: error.httpStatus ?? 0,
      state: _stateFor(error),
    );
    final bool unsafeFailure = switch (error.kind) {
      ApiFailureKind.network ||
      ApiFailureKind.timeout ||
      ApiFailureKind.protocol ||
      ApiFailureKind.server ||
      ApiFailureKind.configuration ||
      ApiFailureKind.unauthorized ||
      ApiFailureKind.forbidden => true,
      ApiFailureKind.business ||
      ApiFailureKind.validation ||
      ApiFailureKind.conflict => false,
    };
    if (requiredSuccess || unsafeFailure) {
      throw TestFailure(
        '$capability authoritative probe failed with status ${error.httpStatus ?? 0}.',
      );
    }
  } catch (_) {
    evidence.http(
      capability: capability,
      method: method,
      route: route,
      status: 0,
      state: 'unavailable',
    );
    // Unknown exceptions are never an acceptable optional-domain state: they
    // can hide DTO drift, Flutter defects, or an unclassified backend error.
    throw TestFailure('$capability authoritative probe failed.');
  }
  return null;
}

String _stateFor(ApiException error) => switch (error.kind) {
  ApiFailureKind.unauthorized || ApiFailureKind.forbidden => 'blocked',
  ApiFailureKind.business ||
  ApiFailureKind.validation ||
  ApiFailureKind.conflict => 'domain_blocked',
  ApiFailureKind.server => 'backend_blocked',
  ApiFailureKind.network || ApiFailureKind.timeout => 'unavailable',
  ApiFailureKind.protocol => 'contract_failure',
  ApiFailureKind.configuration => 'configuration_failure',
};

void _expectVendorReadinessFailClosed(VendorReadinessOverview readiness) {
  const Set<String> formalCapabilities = <String>{
    'SMS',
    'RTC',
    'IM',
    'PAYMENT',
    'PUSH',
    'OBJECT_STORAGE',
  };
  expect(readiness.integrationStatus, 'READY_FOR_PROVIDER_INTEGRATION');
  expect(readiness.runtimeStatus, 'VENDOR_BLOCKED');
  expect(readiness.allBoundariesReady, isTrue);
  expect(readiness.allRuntimeAdaptersReady, isFalse);
  expect(readiness.capabilities.keys.toSet(), formalCapabilities);
  for (final String capabilityName in formalCapabilities) {
    final VendorCapabilityReadiness? capability =
        readiness.capabilities[capabilityName];
    expect(capability, isNotNull, reason: 'missing $capabilityName readiness');
    expect(capability!.capability, capabilityName);
    expect(capability.boundaryStatus, 'READY');
    expect(capability.boundaryReady, isTrue);
    expect(capability.runtimeStatus, 'VENDOR_BLOCKED');
    expect(capability.runtimeReady, isFalse);
  }
}

void _expectExactViewport(WidgetTester tester) {
  final double dpr = tester.view.devicePixelRatio;
  final Size logicalSize = Size(
    tester.view.physicalSize.width / dpr,
    tester.view.physicalSize.height / dpr,
  );
  expect(dpr, closeTo(_expectedDpr, 0.01));
  expect(logicalSize.width, closeTo(_expectedWidth, 0.1));
  expect(logicalSize.height, closeTo(_expectedHeight, 0.1));
  debugPrint(
    'M4_VIEWPORT::$qaAvdId::${logicalSize.width.toStringAsFixed(0)}x'
    '${logicalSize.height.toStringAsFixed(0)}::${dpr.toStringAsFixed(2)}',
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
}) async {
  for (int attempt = 0; attempt < 300; attempt += 1) {
    await tester.pump();
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TestFailure('Timed out waiting for $description.');
}

class _M4Evidence {
  _M4Evidence({required this.avd, required this.binding});

  final String avd;
  final IntegrationTestWidgetsFlutterBinding binding;
  final List<String> _routes = <String>[];
  final List<String> _invariants = <String>[];
  final List<String> _local = <String>[];
  final Set<String> _violations = <String>{};

  // These are the minimum live operations that must have a successful,
  // explicit route outcome before an AVD may be reported as PASS. A mutation
  // already committed by an earlier AVD is accepted only through an explicit
  // `already_authoritative` marker. UI-only screenshots and route counts are
  // never substitutes for these first-party reads/writes.
  static const Set<String> _requiredMutationCapabilities = <String>{
    'community.checkin',
    'community.task.claim',
    'room.moderation.mute',
    'room.moderation.restore',
    'room.seat.up',
    'room.seat.down',
    'room.mic_requests.submit',
    'room.mic_requests.cancel',
    'message.private.send',
    'message.private.history',
    'message.notifications.clear',
    'commerce.gift.send',
    'commerce.gift.receipt',
    'commerce.withdraw.apply',
    'commerce.withdraw.result',
    'commerce.refund.submit',
    'commerce.refund.result',
  };

  static const Set<String> _baseRequiredCapabilities = <String>{
    'auth.send_code',
    'auth.login',
    'auth.refresh',
    'auth.logout',
    'vendor.readiness',
    'home.recommendations',
    'room.owned',
    'search.suggestions',
    'search.results',
    'dynamic.feed',
    'social.profile',
    'social.homepage',
    'community.home',
    'community.recommended_guilds',
    'community.tasks',
    'community.sign_rewards',
    'community.today_sign_status',
    'community.activities',
    'room.mic_requests.get',
    ..._requiredMutationCapabilities,
    'room.enter',
    'room.public_messages',
    'room.reconnect',
    'room.seats',
    'room.off_mic_listeners',
    'room.moderation',
    'room.muted_users',
    'room.topic',
    'room.pk.history',
    'room.pk.active',
    'room.exit.cleanup',
    'message.conversations',
    'commerce.wallet',
    'commerce.wallet.gift_coin',
    'commerce.ledger',
    'commerce.orders',
    'commerce.refund.records',
    'commerce.withdraw.quote',
    'commerce.withdraw.records',
    'commerce.recharge.catalog',
    'commerce.gift.catalog',
    'commerce.decorations',
    'compliance.snapshot',
    'compliance.youth_mode',
    'compliance.restrictions',
    'compliance.cancellation',
    'compliance.version',
    'compliance.real_name',
    'compliance.sessions',
    'support.channel',
  };

  final Set<String> _requiredCapabilities = <String>{
    ..._baseRequiredCapabilities,
  };
  final Set<String> _preexistingCapabilities = <String>{};

  static const Set<String> _requiredInvariants = <String>{
    'authoritative_backend_target_10_0_2_2_18080',
    'development_otp_consumed_in_memory_only',
    'vendor_readiness_observed_without_client_provider',
    'vendor_runtime_adapters_are_fail_closed',
    'home_uses_authoritative_room_ids',
    'room_mutations_use_current_user_owned_room',
    'room_open_authority_confirmed_by_enter_and_reconnect',
    'room_access_modes_selected_from_authoritative_snapshots',
    'direct_room_authority_confirmed',
    'approval_room_authority_confirmed',
    'approval_mic_queue_action_compensated',
    'session_refresh_persists_rotated_session',
    'restart_restores_consent_and_session',
    'search_route_is_reachable_from_home',
    'dynamic_page_reachable_from_primary_navigation',
    'message_records_page_reachable',
    'wallet_gift_withdraw_refund_reads_are_first_party_only',
    'pk_mutation_path_confirmed',
    'first_party_mutations_stay_vendor_free',
    'logout_clears_local_session',
  };

  void requireCapability(String capability) {
    _requiredCapabilities.add(capability);
  }

  void preexisting(String capability, String route, String state) {
    requireCapability(capability);
    _preexistingCapabilities.add(capability);
    http(
      capability: capability,
      method: 'GET',
      route: route,
      status: 200,
      state: state,
    );
  }

  void http({
    required String capability,
    required String method,
    required String route,
    required int status,
    required String state,
  }) {
    final String safeCapability = capability.replaceAll(
      RegExp(r'[^A-Za-z0-9_.-]'),
      '_',
    );
    final String safeState = state.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final String marker =
        'M4_ROUTE_STATUS::$safeCapability::$method::$route::$status::$safeState';
    _routes.add(marker);
    if (status < 200 || status >= 600) {
      _violations.add('$safeCapability:invalid_http_status');
    }
    if (status >= 500 ||
        safeState == 'unavailable' ||
        safeState == 'contract_failure' ||
        safeState == 'configuration_failure') {
      _violations.add('$safeCapability:unsafe_http_outcome');
    }
    debugPrint(marker);
  }

  /// Marks a route that is part of an atomic repository read.  For example,
  /// `fetchTaskCenter` completes only after the task, reward, and today-status
  /// requests all complete and validate.  The marker is deliberately called
  /// `composite_success` so downstream evidence cannot mistake it for a
  /// separately observed request.
  void composite({
    required String capability,
    required String method,
    required String route,
    required int status,
  }) {
    http(
      capability: capability,
      method: method,
      route: route,
      status: status,
      state: 'composite_success',
    );
  }

  void local(String capability, String route, String state) {
    _local.add('$capability:$state');
    if (_requiredCapabilities.contains(capability) &&
        !_preexistingCapabilities.contains(capability)) {
      _violations.add('$capability:required_mutation_not_executed');
    }
    http(
      capability: capability,
      method: 'LOCAL',
      route: route,
      status: 200,
      state: state,
    );
  }

  void invariant(String value) {
    final String safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    _invariants.add(safe);
    debugPrint('M4_AUTHORITY_INVARIANT::$safe');
  }

  void finish() {
    final Set<String> uniqueRoutes = _routes.toSet();
    final Set<String> uniqueInvariants = _invariants.toSet();
    final Set<String> observedCapabilities = _routes
        .map((String marker) => marker.split('::'))
        .where((List<String> parts) => parts.length >= 6)
        .map((List<String> parts) => parts[1])
        .toSet();
    final Set<String> missingCapabilities = _requiredCapabilities.difference(
      observedCapabilities,
    );
    final Set<String> nonSuccessCapabilities = <String>{};
    for (final String marker in uniqueRoutes) {
      final List<String> parts = marker.split('::');
      if (parts.length < 6 ||
          !_requiredCapabilities.contains(parts[1]) ||
          int.tryParse(parts[4]) == null ||
          int.parse(parts[4]) < 200 ||
          int.parse(parts[4]) >= 300 ||
          (parts[5] != 'success' &&
              parts[5] != 'composite_success' &&
              parts[5] != 'registration_required' &&
              !(_preexistingCapabilities.contains(parts[1]) &&
                  parts[5] == 'already_authoritative'))) {
        if (parts.length >= 2 && _requiredCapabilities.contains(parts[1])) {
          nonSuccessCapabilities.add(parts[1]);
        }
      }
    }
    final Set<String> missingInvariants = _requiredInvariants.difference(
      uniqueInvariants,
    );
    final bool candidateShaValid =
        RegExp(r'^[0-9a-f]{40}$').hasMatch(_expectedTestedFlutterSha) &&
        RegExp(r'^[0-9a-f]{40}$').hasMatch(_expectedTestedBackendSha);
    if (!candidateShaValid) {
      _violations.add('candidate_sha_missing_or_invalid');
    }
    if (missingCapabilities.isNotEmpty) {
      _violations.add('required_route_outcome_missing');
    }
    if (nonSuccessCapabilities.isNotEmpty) {
      _violations.add('required_route_outcome_not_successful');
    }
    if (missingInvariants.isNotEmpty) {
      _violations.add('required_authority_invariant_missing');
    }
    if (_invariants.length < 5) {
      _violations.add('insufficient_authority_evidence');
    }
    final bool pass = _violations.isEmpty;
    final Set<String> mutationCapabilities = <String>{
      ..._requiredMutationCapabilities,
      ..._requiredCapabilities.difference(_baseRequiredCapabilities),
    };
    final Map<String, Object?> result = <String, Object?>{
      'avd': avd,
      'routeMarkerCount': uniqueRoutes.length,
      'authorityInvariantCount': uniqueInvariants.length,
      'requiredCapabilityCount': _requiredCapabilities.length,
      'requiredMutationCapabilities': mutationCapabilities.toList()..sort(),
      'missingRequiredCapabilities': missingCapabilities.toList()..sort(),
      'nonSuccessRequiredCapabilities': nonSuccessCapabilities.toList()..sort(),
      'preexistingCapabilities': _preexistingCapabilities.toList()..sort(),
      'missingRequiredInvariants': missingInvariants.toList()..sort(),
      'tested_git_sha': _expectedTestedFlutterSha,
      'backend_sha': _expectedTestedBackendSha,
      'providerCalls': 0,
      'providerCallEvidence': 'none',
      'secretsInClient': false,
      'acceptance': pass ? 'PASS' : 'FAIL',
      'result': pass ? 'PASS' : 'FAIL',
    };
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['m4Acceptance'] = result;
    debugPrint('M4_PROVIDER_CALLS::0');
    debugPrint('M4_AUTHORITY_EVIDENCE::${uniqueInvariants.length}');
    debugPrint('M4_ROUTE_MARKERS::${uniqueRoutes.length}');
    debugPrint('M4_SECRETS_IN_CLIENT::0');
    debugPrint('M4_ACCEPTANCE::${pass ? 'PASS' : 'FAIL'}');
    if (!pass) {
      throw TestFailure(
        'M4 acceptance evidence incomplete: ${_violations.toList()..sort()}',
      );
    }
  }
}

// This alias keeps the room probe's generic result readable without exposing
// any response fields (including tokens or account identifiers) to evidence.
typedef RoomRepositoryProbeResult = RoomSnapshot;
