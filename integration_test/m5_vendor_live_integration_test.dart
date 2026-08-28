import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/im/application/tencent_im_avchat_room_coordinator.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';
import 'package:voice_social_app/features/im/domain/im_room_events.dart';
import 'package:voice_social_app/features/im/domain/im_session_adapter.dart';
import 'package:voice_social_app/features/im/domain/im_session_events.dart';
import 'package:voice_social_app/features/im/domain/tencent_im_room_models.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';

import 'm2_4_test_support.dart';

/// M5 is an opt-in, provider-live acceptance test.  Its markers are
/// deliberately disjoint from M4: a zero-provider M4 result can never satisfy
/// this test's positive Tencent/Alipay evidence requirements.
const String _runtimeConfigPortValue = String.fromEnvironment(
  'M5_RUNTIME_CONFIG_PORT',
  defaultValue: '0',
);
final int _runtimeConfigPort = int.tryParse(_runtimeConfigPortValue) ?? 0;

const String _apiBaseUrl = 'http://10.0.2.2:18080/';
const String _runtimeConfigPath = '/m5/config';
const String _runtimeTokenPath =
    '/data/user/0/com.kong373.voice_social_app/cache/m5-runtime-relay-token';
const String _runtimeTokenFallbackPath =
    '/data/data/com.kong373.voice_social_app/cache/m5-runtime-relay-token';
const String _fixtureId = String.fromEnvironment(
  'QA_M5_FIXTURE_ID',
  defaultValue: '',
);
const String _runId = String.fromEnvironment('QA_M5_RUN_ID', defaultValue: '');
final RegExp _fixturePattern = RegExp(r'^m5-fresh-[A-Za-z0-9_.:-]{1,64}$');
final RegExp _runIdPattern = RegExp(r'^[A-Za-z0-9_.:-]{1,80}$');
const int _workerCycleWaitAttempts = 1200;
const Duration _workerCycleWaitStep = Duration(milliseconds: 100);
const String _expectedFlutterSha = String.fromEnvironment(
  'M5_EXPECTED_FLUTTER_SHA',
  defaultValue: '',
);
const String _expectedBackendSha = String.fromEnvironment(
  'M5_EXPECTED_BACKEND_SHA',
  defaultValue: '',
);
const String _expectedBackendDigest = String.fromEnvironment(
  'M5_EXPECTED_BACKEND_DIGEST',
  defaultValue: '',
);
const bool _allowExternalPayment = bool.fromEnvironment(
  'M5_ALLOW_EXTERNAL_PAYMENT',
  defaultValue: false,
);
const bool _enableAlipayAppPay = bool.fromEnvironment(
  'ENABLE_ALIPAY_APP_PAY',
  defaultValue: false,
);
const String _paymentConfirmation = String.fromEnvironment(
  'M5_PAYMENT_CONFIRMATION',
  defaultValue: '',
);
const String _paymentScenario = String.fromEnvironment(
  'M5_ALIPAY_SCENARIO',
  defaultValue: 'none',
);
const String _successConfirmation = String.fromEnvironment(
  'M5_SUCCESS_CONFIRMATION',
  defaultValue: '',
);
String get _c2cMessageContent =>
    'M5 ${_runId.isEmpty ? _fixtureId : _runId} HTTP authority avd-a';

String _avdForRole(String role) => role == 'receiver' ? 'AVD-B' : 'AVD-A';

({double width, double height, double dpr}) _viewportForRole(String role) =>
    role == 'receiver'
    ? (width: 360, height: 800, dpr: 2.4)
    : (width: 390, height: 844, dpr: 3);

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'M5 Tencent IM and Alipay sandbox live acceptance',
    (WidgetTester tester) async {
      final _M5Evidence evidence = _M5Evidence(avd: 'AVD-A', binding: binding);
      AppDependencies? dependencies;
      StreamSubscription<ImSessionEvent>? eventSubscription;
      try {
        final _RuntimeConfig config = await _fetchRuntimeConfig();
        final String avd = _avdForRole(config.role);
        evidence.avd = avd;
        final bool fixtureValid = _fixturePattern.hasMatch(_fixtureId);
        final bool attestationValid =
            _isSha40(_expectedFlutterSha) &&
            _isSha40(_expectedBackendSha) &&
            _isSha256(_expectedBackendDigest);
        if (!fixtureValid) {
          evidence.violation('fixture_missing_or_invalid');
        } else if (!attestationValid) {
          evidence.violation('candidate_attestation_missing_or_invalid');
        } else {
          final AppEnvironment environment = _liveEnvironment(
            config.oauthClientId,
          );
          environment.validateLiveConfiguration();
          evidence.invariant('authoritative_backend_target_10_0_2_2_18080');
          evidence.viewport(tester, config.role);
          final bool validScenario = <String>{
            'none',
            'cancel',
            'success',
          }.contains(_paymentScenario);
          final bool paymentRequested =
              _allowExternalPayment && _paymentScenario != 'none';
          final bool paymentOptedIn =
              paymentRequested &&
              _enableAlipayAppPay &&
              _paymentConfirmation == 'I_UNDERSTAND_SANDBOX_PAYMENT' &&
              (_paymentScenario != 'success' ||
                  _successConfirmation ==
                      'I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT');
          if (!validScenario) {
            evidence.violation('payment_scenario_invalid');
          }
          if (_allowExternalPayment && _paymentScenario == 'none') {
            evidence.violation('payment_scenario_required_when_enabled');
          }
          if (paymentRequested &&
              _paymentConfirmation != 'I_UNDERSTAND_SANDBOX_PAYMENT') {
            evidence.violation('payment_opt_in_confirmation_invalid');
          }
          if (paymentRequested && !_enableAlipayAppPay) {
            evidence.violation('alipay_provider_build_flag_missing');
          }
          if (_allowExternalPayment &&
              _paymentScenario == 'success' &&
              _successConfirmation != 'I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT') {
            evidence.violation('payment_success_confirmation_invalid');
          }
          evidence.paymentOptIn(paymentOptedIn, owner: config.role == 'sender');

          if (paymentOptedIn || !_allowExternalPayment) {
            dependencies = AppDependencies.forTestEnvironment(
              environment: environment,
            );
            await _pumpGate(tester, dependencies);
            await _authenticate(tester, dependencies, config, evidence);
            await _waitForAuthenticatedHome(
              tester,
              dependencies.authController,
              description: 'M5 authenticated home',
            );
            await captureQaScreenshot(
              tester,
              binding,
              'm5-${avd.toLowerCase()}-home',
            );

            eventSubscription = dependencies.imSessionAdapter.events.listen(
              evidence.providerEventFromSdk,
            );
            final AuthSession session = dependencies.authController.session!;
            await _runTencentCredentialAndLogin(
              dependencies,
              evidence,
              session,
            );
            await _runC2cHttpAuthority(
              dependencies,
              evidence,
              session,
              config,
              avd,
            );
            await _runAvChatRoom(dependencies, evidence, session, config);
            await _runAlipaySandbox(
              dependencies,
              evidence,
              session,
              paymentOwner: config.role == 'sender',
            );
          }
        }
      } catch (_) {
        // Never retain or re-emit SDK/backend exception text: some vendor
        // libraries echo request material in their exception descriptions.
        evidence.violation('unhandled_live_acceptance_exception');
      } finally {
        await eventSubscription?.cancel();
        dependencies?.dispose();
      }
      if (!evidence.finish()) {
        throw TestFailure('M5 live acceptance evidence is incomplete.');
      }
    },
    timeout: const Timeout(Duration(minutes: 25)),
    skip: _runtimeConfigPort == 0,
  );
}

AppEnvironment _liveEnvironment(String oauthClientId) => AppEnvironment(
  backendMode: BackendMode.live,
  apiBaseUrl: _apiBaseUrl,
  clientType: 'Android',
  clientInnerVersion: '1',
  oauthClientId: oauthClientId,
  realtimeEndpoint: '',
  deploymentEnvironment: DeploymentEnvironment.development,
  allowInsecureHttp: true,
  enableTencentIm: true,
  enableAlipayAppPay: _enableAlipayAppPay,
  apiTimeout: const Duration(seconds: 15),
);

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
}

Future<void> _authenticate(
  WidgetTester tester,
  AppDependencies dependencies,
  _RuntimeConfig config,
  _M5Evidence evidence,
) async {
  final AuthController controller = dependencies.authController;
  await _waitFor(
    tester,
    () => controller.stage != AuthFlowStage.initializing,
    description: 'M5 auth initialization',
  );
  if (controller.stage == AuthFlowStage.consentRequired) {
    await controller.acceptConsent();
    evidence.route(
      capability: 'auth.consent',
      method: 'LOCAL',
      route: '/consent',
      status: 200,
      state: 'success',
    );
  }
  await _waitFor(
    tester,
    () =>
        controller.stage == AuthFlowStage.signedOut ||
        controller.stage == AuthFlowStage.signedIn,
    description: 'M5 signed-out auth page',
  );
  if (controller.stage == AuthFlowStage.signedIn) {
    return;
  }
  final bool challengeSent = await controller.sendSmsCode(config.phone);
  evidence.route(
    capability: 'auth.send_code',
    method: 'PUT',
    route: const BackendRouteCatalog().sendSmsCode,
    status: challengeSent ? 200 : 0,
    state: challengeSent ? 'success' : 'blocked',
  );
  if (!challengeSent) {
    throw TestFailure('M5 development SMS challenge failed.');
  }
  final String? code = controller.lastSmsChallenge?.developmentCode;
  if (code == null || !RegExp(r'^\d{6}$').hasMatch(code)) {
    throw TestFailure(
      'M5 development SMS challenge omitted an in-memory code.',
    );
  }
  evidence.invariant('development_otp_consumed_in_memory_only');
  final bool signedIn = await controller.signInWithSms(
    phone: config.phone,
    smsCode: code,
  );
  if (!signedIn) {
    evidence.route(
      capability: 'auth.login',
      method: 'PUT',
      route: const BackendRouteCatalog().loginBySms,
      status: 0,
      state: 'blocked',
    );
    throw TestFailure('M5 login did not complete.');
  }
  evidence.route(
    capability: 'auth.login',
    method: 'PUT',
    route: const BackendRouteCatalog().loginBySms,
    status: 200,
    state: controller.stage == AuthFlowStage.registrationRequired
        ? 'registration_required'
        : 'success',
  );
  if (controller.stage == AuthFlowStage.registrationRequired) {
    final bool registered = await controller.completeRegistration(
      RegistrationProfile(nickname: _registrationNickname(), sex: 0),
    );
    evidence.route(
      capability: 'auth.register',
      method: 'POST',
      route: const BackendRouteCatalog().registerByMobile,
      status: registered ? 200 : 0,
      state: registered ? 'success' : 'blocked',
    );
    if (!registered) {
      throw TestFailure('M5 registration did not complete.');
    }
  }
}

String _registrationNickname() {
  if (!_fixturePattern.hasMatch(_fixtureId)) {
    throw TestFailure('M5 fixture identity is missing.');
  }
  final String digest = sha256.convert(utf8.encode(_fixtureId)).toString();
  return 'm5-${digest.substring(0, 13)}';
}

String _m5C2cRequestId(String avd) {
  if (_runId.isEmpty ||
      !_runIdPattern.hasMatch(_runId) ||
      !_fixturePattern.hasMatch(_fixtureId)) {
    throw TestFailure('M5 C2C request identity is missing or invalid.');
  }
  final String normalizedAvd = avd.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9._-]'),
    '-',
  );
  if (normalizedAvd.isEmpty) {
    throw TestFailure('M5 C2C AVD identity is missing.');
  }
  final String identity =
      'm5-c2c|run=$_runId|fixture=$_fixtureId|avd=$normalizedAvd';
  final String digest = sha256.convert(utf8.encode(identity)).toString();
  final String requestId = 'm5-c2c-$digest';
  if (!RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(requestId)) {
    throw TestFailure('M5 C2C request identity is unsafe.');
  }
  return requestId;
}

Future<void> _runTencentCredentialAndLogin(
  AppDependencies dependencies,
  _M5Evidence evidence,
  AuthSession session,
) async {
  try {
    await dependencies.imSessionCoordinator.ensureAuthenticated(session);
    evidence.route(
      capability: 'tencent.credential',
      method: 'POST',
      route: const BackendRouteCatalog().imCredential,
      status: 200,
      state: 'success',
    );
  } on Object {
    evidence.route(
      capability: 'tencent.credential',
      method: 'POST',
      route: const BackendRouteCatalog().imCredential,
      status: 0,
      state: 'blocked',
    );
    evidence.lane('tencent.credential', 'FAIL');
    evidence.lane('tencent.login', 'FAIL');
    throw TestFailure('Tencent credential/login did not reach READY.');
  }
  if (!dependencies.imSessionCoordinator.realtimeReady ||
      dependencies.imSessionAdapter.status != ImSessionStatus.ready) {
    evidence.lane('tencent.credential', 'FAIL');
    evidence.lane('tencent.login', 'FAIL');
    throw TestFailure('Tencent session was not provider READY.');
  }
  // ensureAuthenticated returns only after the adapter's initialize/login
  // callback has produced a matching READY state. Count that callback, not
  // the client-side credential intent, as provider evidence.
  evidence.providerCallback('tencent-im', 'login_ready');
  evidence.lane('tencent.credential', 'PASS');
  evidence.lane('tencent.login', 'PASS');
}

Future<void> _runC2cHttpAuthority(
  AppDependencies dependencies,
  _M5Evidence evidence,
  AuthSession session,
  _RuntimeConfig config,
  String avd,
) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  try {
    if (!dependencies.messageRepository.supportsPrivateHistory ||
        !dependencies.messageRepository.supportsPrivateSend) {
      evidence.lane('tencent.c2c.http-authority', 'BLOCKED');
      return;
    }
    await _registerRelayFirstPartyUserId(config, session.userId);
    final int? peerUserId = await _pollRelayPeerUserId(config, session.userId);
    if (peerUserId == null) {
      evidence.lane('tencent.c2c.http-authority', 'BLOCKED');
      return;
    }
    final List<ConversationSummary> conversations = await dependencies
        .messageRepository
        .fetchConversations();
    evidence.route(
      capability: 'tencent.c2c.conversations',
      method: 'GET',
      route: routes.messageConversations,
      status: 200,
      state: 'success',
    );
    final ConversationSummary selected =
        conversations.where((ConversationSummary candidate) {
          return candidate.available &&
              !candidate.isDraft &&
              candidate.targetUserId == peerUserId;
        }).firstOrNull ??
        ConversationSummary.draft(
          kind: ConversationKind.privateChat,
          title: 'M5 live peer',
          lastMessage: '',
          unreadCount: 0,
          targetUserId: peerUserId,
        );
    if (selected.isDraft) {
      evidence.invariant(
        'tencent_c2c_draft_conversation_from_relay_peer_user_id',
      );
    }
    final List<ChatMessage> history = await dependencies.messageRepository
        .fetchPrivateMessages(selected);
    evidence.route(
      capability: 'tencent.c2c.history',
      method: 'GET',
      route: routes.privateChatHistory,
      status: 200,
      state: 'success',
    );
    if (config.role == 'receiver') {
      // Start a fresh hint window before coordinating with the sender. A
      // matching backend message ID is still required below, so an event
      // arriving while the sender is being scheduled cannot become a PASS.
      evidence.beginC2cHintAttempt();
      await _postRelaySignal(config, '/m5/c2c/receiver-ready');
      bool senderSent = false;
      for (int attempt = 0; attempt < _workerCycleWaitAttempts; attempt += 1) {
        senderSent = await _readRelaySignal(config, '/m5/c2c/sender-sent');
        if (senderSent) {
          break;
        }
        await Future<void>.delayed(_workerCycleWaitStep);
      }
      if (!senderSent) {
        evidence.lane('tencent.c2c.http-authority', 'BLOCKED');
        return;
      }
      // The receiver accepts only the provider-neutral custom-element event;
      // message content still comes from the first-party HTTP history route.
      for (
        int attempt = 0;
        attempt < _workerCycleWaitAttempts && !evidence.c2cHintObserved;
        attempt += 1
      ) {
        await Future<void>.delayed(_workerCycleWaitStep);
      }
      if (!evidence.c2cHintObserved) {
        evidence.lane('tencent.c2c.http-authority', 'BLOCKED');
        return;
      }
      final List<ChatMessage> refreshed = await dependencies.messageRepository
          .fetchPrivateMessages(selected);
      evidence.route(
        capability: 'tencent.c2c.hint.http-refresh',
        method: 'GET',
        route: routes.privateChatHistory,
        status: 200,
        state: 'authoritative',
      );
      if (refreshed.length < history.length) {
        evidence.lane('tencent.c2c.http-authority', 'FAIL');
        return;
      }
      final bool senderMessageObserved = refreshed.any(
        (ChatMessage item) =>
            item.senderUserId == selected.targetUserId &&
            item.content == _c2cMessageContent,
      );
      if (!senderMessageObserved) {
        evidence.lane('tencent.c2c.http-authority', 'BLOCKED');
        return;
      }
      final ChatMessage senderMessage = refreshed.firstWhere(
        (ChatMessage item) =>
            item.senderUserId == selected.targetUserId &&
            item.content == _c2cMessageContent,
      );
      if (!evidence.hasC2cHintForMessage(senderMessage.id)) {
        evidence.lane('tencent.c2c.http-authority', 'BLOCKED');
        return;
      }
      await _postRelaySignal(config, '/m5/c2c/receiver-pass');
      evidence.invariant('tencent_c2c_receiver_sdk_hint_http_refresh');
      evidence.lane('tencent.c2c.http-authority', 'PASS');
      return;
    }
    bool receiverReady = false;
    for (int attempt = 0; attempt < _workerCycleWaitAttempts; attempt += 1) {
      receiverReady = await _readRelaySignal(config, '/m5/c2c/receiver-ready');
      if (receiverReady) {
        break;
      }
      await Future<void>.delayed(_workerCycleWaitStep);
    }
    if (!receiverReady) {
      evidence.lane('tencent.c2c.http-authority', 'BLOCKED');
      return;
    }
    final ChatMessage sent = await dependencies.messageRepository
        .sendPrivateMessage(
          conversation: selected,
          content: _c2cMessageContent,
          requestId: _m5C2cRequestId(avd),
        );
    evidence.route(
      capability: 'tencent.c2c.send',
      method: 'POST',
      route: routes.sendPrivateMessage,
      status: 200,
      state: 'success',
    );
    if (sent.id.trim().isEmpty ||
        history.any((ChatMessage item) => item.id == sent.id)) {
      evidence.lane('tencent.c2c.http-authority', 'FAIL');
      return;
    }
    if (!selected.isDraft && sent.conversationId != selected.id) {
      evidence.lane('tencent.c2c.http-authority', 'FAIL');
      return;
    }
    // The HTTP send is only a first-party intent. It is not a vendor
    // callback and cannot pass this lane until the receiver proves the
    // Tencent custom hint -> SDK event -> HTTP history refresh chain.
    await _postRelaySignal(config, '/m5/c2c/sender-sent');
    bool receiverPass = false;
    for (int attempt = 0; attempt < _workerCycleWaitAttempts; attempt += 1) {
      receiverPass = await _readRelaySignal(config, '/m5/c2c/receiver-pass');
      if (receiverPass) {
        break;
      }
      await Future<void>.delayed(_workerCycleWaitStep);
    }
    if (!receiverPass) {
      evidence.lane('tencent.c2c.http-authority', 'BLOCKED');
      return;
    }
    evidence.invariant(
      'tencent_c2c_sender_waited_for_receiver_sdk_http_refresh',
    );
    evidence.lane('tencent.c2c.http-authority', 'PASS');
  } on ApiException catch (error) {
    evidence.route(
      capability: 'tencent.c2c.http-authority',
      method: 'HTTP',
      route: routes.privateChatHistory,
      status: error.httpStatus ?? 0,
      state: _safeApiState(error),
    );
    evidence.lane('tencent.c2c.http-authority', 'FAIL');
  }
}

String _avchatRoomFixtureTitle() {
  final String runDigest = sha256.convert(utf8.encode(_runId)).toString();
  return 'M5 live ${_registrationNickname()} ${runDigest.substring(0, 13)}';
}

String _avchatRoomFixtureTopic() =>
    'M5 Tencent AVChatRoom ${_registrationNickname()}';

const String _avchatRoomReceiverLeftPath = '/m5/avchatroom/receiver-left';

class _AvChatRoomFixture {
  const _AvChatRoomFixture({required this.room, required this.created});

  final DiscoveryRoom room;
  final bool created;
}

Future<TencentImAvChatRoomSession?> _pollAvChatRoomReadiness(
  AppDependencies dependencies,
  _M5Evidence evidence,
  BackendRouteCatalog routes,
  String roomId, {
  int maxAttempts = 75,
}) async {
  final RoomRepository repository = dependencies.roomRepository;
  if (repository is! TencentImRoomReadinessSource) {
    return null;
  }
  TencentImAvChatRoomSession? latest;
  String? lastState;
  for (int attempt = 0; attempt < maxAttempts; attempt += 1) {
    try {
      latest = await (repository as TencentImRoomReadinessSource)
          .fetchTencentImRoomReadiness(roomId);
      final String state = latest?.isReady == true ? 'ready' : 'pending';
      if (state != lastState) {
        evidence.route(
          capability: 'tencent.avchatroom.readiness',
          method: 'GET',
          route: routes.queryRoomOtherInfo,
          status: 200,
          state: state,
        );
        lastState = state;
      }
      if (latest?.isReady == true) {
        return latest;
      }
    } on ApiException catch (error) {
      if (lastState != 'blocked') {
        evidence.route(
          capability: 'tencent.avchatroom.readiness',
          method: 'GET',
          route: routes.queryRoomOtherInfo,
          status: error.httpStatus ?? 0,
          state: _safeApiState(error),
        );
        lastState = 'blocked';
      }
    }
    if (attempt + 1 < maxAttempts) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  return latest;
}

Future<_AvChatRoomFixture?> _createAvChatRoomFixture(
  AppDependencies dependencies,
  _M5Evidence evidence,
  BackendRouteCatalog routes,
) async {
  final String title = _avchatRoomFixtureTitle();
  final String topic = _avchatRoomFixtureTopic();
  try {
    final RoomLifecycleSaveResult saved = await dependencies
        .roomLifecycleRepository
        .saveRoom(
          RoomConfiguration(
            title: title,
            topicTitle: 'M5 live acceptance',
            topicContent: topic,
            welcomeMessage: 'M5 provider-live acceptance room',
            accessMode: RoomAccessMode.publicRoom,
            password: '',
            showInHall: false,
            autoLockMic: false,
            availability: RoomAvailability.open,
          ),
        );
    evidence.route(
      capability: 'tencent.avchatroom.create',
      method: 'POST',
      route: routes.createRoom,
      status: 200,
      state: saved.created ? 'created' : 'idempotent_reused',
    );
    if (saved.roomId.trim().isEmpty) {
      evidence.violation('avchatroom_fixture_not_fresh');
      evidence.lane('tencent.avchatroom.hint', 'BLOCKED');
      evidence.lane('tencent.avchatroom.leave', 'BLOCKED');
      return null;
    }
    evidence.invariant(
      saved.created
          ? 'tencent_avchatroom_fixture_created'
          : 'tencent_avchatroom_fixture_idempotent_reused',
    );
    return _AvChatRoomFixture(
      created: saved.created,
      room: DiscoveryRoom(
        id: saved.roomId,
        code: saved.roomCode,
        title: title,
        topic: topic,
        occupiedSeats: 0,
        isSpeaking: false,
        isFavorite: false,
        ownerUserId: dependencies.authController.session?.userId,
      ),
    );
  } on ApiException catch (error) {
    evidence.route(
      capability: 'tencent.avchatroom.create',
      method: 'POST',
      route: routes.createRoom,
      status: error.httpStatus ?? 0,
      state: _safeApiState(error),
    );
    evidence.lane('tencent.avchatroom.hint', 'BLOCKED');
    evidence.lane('tencent.avchatroom.leave', 'BLOCKED');
    return null;
  }
}

Future<void> _runAvChatRoom(
  AppDependencies dependencies,
  _M5Evidence evidence,
  AuthSession session,
  _RuntimeConfig config,
) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  final TencentImAvChatRoomCoordinator coordinator =
      dependencies.tencentImAvChatRoomCoordinator;
  final RoomRepository repository = dependencies.roomRepository;
  DiscoveryRoom? room;
  TencentImAvChatRoomSession? roomSession;
  String? selectedRoomId;
  bool ownerFixtureCleanupEligible = false;
  bool receiverSdkLeaveConfirmed = config.role != 'receiver';
  bool receiverHttpExitConfirmed = config.role != 'receiver';
  try {
    if (config.role == 'sender') {
      final String fixtureTitle = _avchatRoomFixtureTitle();
      final RoomCollectionSnapshot collections = await dependencies
          .discoveryRepository
          .fetchRoomCollections(page: 1, pageSize: 30);
      evidence.route(
        capability: 'tencent.avchatroom.owned',
        method: 'GET',
        route: routes.ownedRooms,
        status: 200,
        state: 'success',
      );
      for (final DiscoveryRoom candidate in collections.ownedRooms) {
        if (candidate.ownerUserId == session.userId &&
            candidate.id.isNotEmpty &&
            candidate.title.trim() == fixtureTitle) {
          final TencentImAvChatRoomSession? ready =
              await _pollAvChatRoomReadiness(
                dependencies,
                evidence,
                routes,
                candidate.id,
                maxAttempts: 1,
              );
          room = candidate;
          // This exact, run-derived title is the only reused fixture that
          // this test may later close. Never close an arbitrary old M5 room.
          // Keep a pending exact fixture instead of creating another room;
          // the normal enter/readiness path will retry it and the owner
          // cleanup guard will close it after receiver departure.
          ownerFixtureCleanupEligible = true;
          if (ready?.isReady != true) {
            evidence.invariant('tencent_avchatroom_fixture_readiness_pending');
          }
          break;
        }
      }
      if (room == null) {
        final _AvChatRoomFixture? createdFixture =
            await _createAvChatRoomFixture(dependencies, evidence, routes);
        if (createdFixture != null) {
          room = createdFixture.room;
          // Idempotent create responses may report created=false. The
          // response still identifies the exact run-derived fixture; the
          // cleanup guard re-reads owner authority and the exact title before
          // it is ever allowed to close anything.
          ownerFixtureCleanupEligible = createdFixture.room.id
              .trim()
              .isNotEmpty;
        }
      }
      if (room == null) {
        return;
      }
      selectedRoomId = room.id;
      await _postRelayJson(config, '/m5/avchatroom/ready', <String, String>{
        'roomId': room.id,
      });
      evidence.invariant('tencent_avchatroom_sender_bound_shared_room');
    } else {
      String? roomId;
      for (
        int attempt = 0;
        attempt < _workerCycleWaitAttempts && roomId == null;
        attempt += 1
      ) {
        roomId = await _readRelayValue(
          config,
          '/m5/avchatroom/ready',
          'roomId',
        );
        if (roomId == null) {
          await Future<void>.delayed(_workerCycleWaitStep);
        }
      }
      if (roomId == null) {
        evidence.lane('tencent.avchatroom.hint', 'BLOCKED');
        evidence.lane('tencent.avchatroom.leave', 'BLOCKED');
        return;
      }
      room = DiscoveryRoom(
        id: roomId,
        code: roomId,
        title: _avchatRoomFixtureTitle(),
        topic: _avchatRoomFixtureTopic(),
        occupiedSeats: 0,
        isSpeaking: false,
        isFavorite: false,
      );
      selectedRoomId = roomId;
      evidence.invariant('tencent_avchatroom_receiver_bound_shared_room');
    }
    final DiscoveryRoom selectedRoom = room;
    // A non-owner participant cannot read the provider projection until the
    // first-party enter has established their active room membership. The
    // readiness endpoint is intentionally scoped to that membership, so the
    // order is HTTP enter first, then bounded readiness polling, then SDK
    // join. Owners may already have an active row from room creation, but
    // using the same order keeps both AVD roles on one authoritative path.
    final RoomSnapshot snapshot = await repository.enterRoom(
      roomId: selectedRoom.id,
      password: null,
      source: RoomEntrySource.home,
      currentUserId: session.userId,
    );
    evidence.route(
      capability: 'tencent.avchatroom.enter',
      method: 'POST',
      route: routes.enterRoom,
      status: 200,
      state: 'success',
    );
    if (snapshot.roomId != selectedRoom.id) {
      throw TestFailure('M5 room enter identity mismatch.');
    }
    if (repository is TencentImRoomSessionSource) {
      roomSession = (repository as TencentImRoomSessionSource)
          .takeTencentImRoomSession(selectedRoom.id);
    }
    if (roomSession == null || !roomSession.isReady) {
      roomSession = await _pollAvChatRoomReadiness(
        dependencies,
        evidence,
        routes,
        selectedRoom.id,
      );
    }
    final TencentImAvChatRoomSession? readySession = roomSession;
    if (readySession == null || !readySession.isReady) {
      evidence.lane('tencent.avchatroom.hint', 'BLOCKED');
      evidence.lane('tencent.avchatroom.leave', 'BLOCKED');
      receiverSdkLeaveConfirmed = config.role == 'receiver';
      try {
        await dependencies.roomRepository.exitRoom(selectedRoom.id);
        receiverHttpExitConfirmed = config.role == 'receiver';
        evidence.route(
          capability: 'tencent.avchatroom.http-exit',
          method: 'POST',
          route: routes.exitRoom,
          status: 200,
          state: 'success',
        );
      } on Object {
        evidence.lane('tencent.avchatroom.leave', 'FAIL');
      }
      return;
    }
    evidence.beginRoomHintAttempt();
    bool authoritativeRefreshCompleted = false;
    TencentImRoomRefreshRegistration? registration;
    StreamSubscription<ImRoomRefreshEvent>? roomEventSubscription;
    final ImRoomGroupCapability? roomCapability =
        dependencies.imSessionAdapter is ImRoomGroupCapability
        ? dependencies.imSessionAdapter as ImRoomGroupCapability
        : null;
    if (roomCapability != null) {
      roomEventSubscription = roomCapability.roomEvents.listen((
        ImRoomRefreshEvent event,
      ) {
        if (event.groupId == readySession.groupId) {
          evidence.roomHintFromSdk(event.hint);
        }
      });
    }
    registration = coordinator.registerRefreshHandler(
      roomId: selectedRoom.id,
      onRefresh: (String roomId) async {
        await repository.fetchPublicMessages(roomId);
        authoritativeRefreshCompleted = true;
        evidence.route(
          capability: 'tencent.avchatroom.hint.http-refresh',
          method: 'GET',
          route: routes.publicMessages,
          status: 200,
          state: 'authoritative',
        );
      },
    );
    try {
      final TencentImAvChatRoomJoinResult result = await coordinator.enter(
        readySession,
      );
      if (!result.providerJoined) {
        evidence.lane('tencent.avchatroom.hint', 'BLOCKED');
        return;
      }
      evidence.providerCallback('tencent-im', 'avchatroom_join');
      if (config.role == 'sender') {
        final String content =
            'M5 ${_registrationNickname()} AVChatRoom authority';
        final RoomMessage sent = await repository.sendPublicMessage(
          roomId: selectedRoom.id,
          content: content,
          requestId:
              'm5-avchat-${sha256.convert(utf8.encode(_runId)).toString().substring(0, 16)}',
        );
        evidence.route(
          capability: 'tencent.avchatroom.send',
          method: 'POST',
          route: routes.sendPublicMessage,
          status: 200,
          state: 'success',
        );
        final String? messageId = sent.messageId?.trim();
        if (messageId == null ||
            messageId.isEmpty ||
            sent.roomId != selectedRoom.id ||
            sent.senderId != session.userId ||
            sent.content != content) {
          evidence.lane('tencent.avchatroom.hint', 'FAIL');
          return;
        }
        evidence.invariant('tencent_avchatroom_http_send_message_id');
        await _postRelayJson(
          config,
          '/m5/avchatroom/message-sent',
          <String, String>{'messageId': messageId},
        );
        bool receiverPass = false;
        for (
          int attempt = 0;
          attempt < _workerCycleWaitAttempts;
          attempt += 1
        ) {
          receiverPass = await _readRelaySignal(config, '/m5/avchatroom/pass');
          if (receiverPass) {
            break;
          }
          await Future<void>.delayed(_workerCycleWaitStep);
        }
        evidence.lane(
          'tencent.avchatroom.hint',
          receiverPass ? 'PASS' : 'BLOCKED',
        );
      } else {
        String? messageId;
        for (
          int attempt = 0;
          attempt < _workerCycleWaitAttempts && messageId == null;
          attempt += 1
        ) {
          messageId = await _readRelayValue(
            config,
            '/m5/avchatroom/message-sent',
            'messageId',
          );
          if (messageId == null) {
            await Future<void>.delayed(_workerCycleWaitStep);
          }
        }
        for (
          int attempt = 0;
          attempt < _workerCycleWaitAttempts &&
              !(evidence.roomHintObserved && authoritativeRefreshCompleted);
          attempt += 1
        ) {
          await Future<void>.delayed(_workerCycleWaitStep);
        }
        if (messageId == null ||
            !evidence.roomHintObserved ||
            !authoritativeRefreshCompleted) {
          evidence.lane('tencent.avchatroom.hint', 'BLOCKED');
          return;
        }
        final String expectedMessageId = messageId;
        final List<RoomMessage> refreshed = await repository
            .fetchPublicMessages(selectedRoom.id);
        evidence.route(
          capability: 'tencent.avchatroom.hint.http-refresh',
          method: 'GET',
          route: routes.publicMessages,
          status: 200,
          state: 'authoritative',
        );
        final bool messageMatches = refreshed.any(
          (RoomMessage item) =>
              item.messageId == expectedMessageId &&
              item.content ==
                  'M5 ${_registrationNickname()} AVChatRoom authority',
        );
        if (!messageMatches ||
            !evidence.hasRoomHintForMessage(expectedMessageId)) {
          evidence.lane('tencent.avchatroom.hint', 'BLOCKED');
          return;
        }
        await _postRelaySignal(config, '/m5/avchatroom/pass');
        evidence.invariant('tencent_avchatroom_sdk_hint_http_refresh');
        evidence.lane('tencent.avchatroom.hint', 'PASS');
      }
    } finally {
      registration.cancel();
      await roomEventSubscription?.cancel();
      evidence.endRoomHintAttempt();
      bool left = false;
      try {
        await coordinator.leave();
        left = coordinator.activeGroupId == null;
      } on Object {
        left = false;
      }
      if (config.role == 'receiver') {
        receiverSdkLeaveConfirmed = left;
      }
      evidence.route(
        capability: 'tencent.avchatroom.leave',
        method: 'SDK',
        route: 'TencentIm.quitGroup',
        status: left ? 200 : 0,
        state: left ? 'success' : 'blocked',
      );
      evidence.lane('tencent.avchatroom.leave', left ? 'PASS' : 'FAIL');
      try {
        await dependencies.roomRepository.exitRoom(selectedRoom.id);
        if (config.role == 'receiver') {
          receiverHttpExitConfirmed = true;
        }
        evidence.route(
          capability: 'tencent.avchatroom.http-exit',
          method: 'POST',
          route: routes.exitRoom,
          status: 200,
          state: 'success',
        );
      } on Object {
        evidence.lane('tencent.avchatroom.leave', 'FAIL');
      }
    }
  } on ApiException catch (error) {
    evidence.route(
      capability: 'tencent.avchatroom',
      method: 'HTTP',
      route: routes.enterRoom,
      status: error.httpStatus ?? 0,
      state: _safeApiState(error),
    );
    evidence.lane('tencent.avchatroom.hint', 'FAIL');
    evidence.lane('tencent.avchatroom.leave', 'FAIL');
  } finally {
    final String? roomId = selectedRoomId;
    if (config.role == 'receiver' &&
        roomId != null &&
        receiverSdkLeaveConfirmed &&
        receiverHttpExitConfirmed) {
      // This signal is emitted only after the nested finally has completed
      // SDK quitGroup and first-party HTTP exitRoom. The sender must not use
      // the hint-pass signal as a proxy for receiver cleanup.
      try {
        await _postRelayJson(
          config,
          _avchatRoomReceiverLeftPath,
          <String, String>{'roomId': roomId},
        );
        evidence.invariant('tencent_avchatroom_receiver_left');
      } on Object {
        evidence.violation('tencent_avchatroom_receiver_left_signal_failed');
      }
    } else if (config.role == 'receiver' && roomId != null) {
      evidence.violation('tencent_avchatroom_receiver_left_not_confirmed');
    }
    if (config.role == 'sender' &&
        ownerFixtureCleanupEligible &&
        roomId != null) {
      bool receiverLeft = false;
      for (
        int attempt = 0;
        attempt < _workerCycleWaitAttempts && !receiverLeft;
        attempt += 1
      ) {
        receiverLeft =
            await _readRelayValue(
              config,
              _avchatRoomReceiverLeftPath,
              'roomId',
            ) ==
            roomId;
        if (!receiverLeft) {
          await Future<void>.delayed(_workerCycleWaitStep);
        }
      }
      if (!receiverLeft) {
        evidence.violation('tencent_avchatroom_receiver_left_not_confirmed');
        evidence.lane('tencent.avchatroom.fixture-cleanup', 'FAIL');
      } else {
        evidence.invariant('tencent_avchatroom_receiver_left_confirmed');
        try {
          final RoomConfiguration owned = await dependencies
              .roomLifecycleRepository
              .fetchRoom(roomId);
          final bool exactCurrentFixture =
              owned.roomId == roomId &&
              owned.title.trim() == _avchatRoomFixtureTitle() &&
              owned.accessMode == RoomAccessMode.publicRoom &&
              owned.isOpen &&
              owned.version != null;
          if (!exactCurrentFixture) {
            evidence.violation('tencent_avchatroom_cleanup_fixture_mismatch');
            evidence.lane('tencent.avchatroom.fixture-cleanup', 'FAIL');
          } else {
            await dependencies.roomLifecycleRepository.closeRoom(
              roomId,
              expectedVersion: owned.version,
            );
            evidence.route(
              capability: 'tencent.avchatroom.fixture-cleanup',
              method: 'POST',
              route: routes.closeRoom,
              status: 200,
              state: 'closed',
            );
            evidence.invariant('tencent_avchatroom_current_fixture_closed');
            evidence.lane('tencent.avchatroom.fixture-cleanup', 'PASS');
          }
        } on ApiException catch (error) {
          evidence.route(
            capability: 'tencent.avchatroom.fixture-cleanup',
            method: 'POST',
            route: routes.closeRoom,
            status: error.httpStatus ?? 0,
            state: _safeApiState(error),
          );
          evidence.violation('tencent_avchatroom_fixture_cleanup_failed');
          evidence.lane('tencent.avchatroom.fixture-cleanup', 'FAIL');
        } on Object {
          evidence.violation('tencent_avchatroom_fixture_cleanup_failed');
          evidence.lane('tencent.avchatroom.fixture-cleanup', 'FAIL');
        }
      }
    }
  }
}

Future<void> _runAlipaySandbox(
  AppDependencies dependencies,
  _M5Evidence evidence,
  AuthSession session, {
  required bool paymentOwner,
}) async {
  final BackendRouteCatalog routes = const BackendRouteCatalog();
  void markPaymentNotRun() {
    evidence.lane('alipay.order', 'NOT_RUN');
    evidence.lane('alipay.native.launch-cancel', 'NOT_RUN');
    evidence.lane('alipay.native.launch-success', 'NOT_RUN');
    evidence.lane('alipay.query-reconcile', 'NOT_RUN');
    evidence.lane('alipay.settlement', 'NOT_RUN');
    evidence.lane('alipay.reconcile-idempotency', 'NOT_RUN');
  }

  List<RechargeProduct> products;
  try {
    products = await dependencies.commerceCatalogRepository
        .fetchRechargeProducts(platform: ClientStorePlatform.android);
    evidence.route(
      capability: 'alipay.catalog',
      method: 'GET',
      route: routes.rechargeProducts,
      status: 200,
      state: 'success',
    );
  } on ApiException catch (error) {
    evidence.route(
      capability: 'alipay.catalog',
      method: 'GET',
      route: routes.rechargeProducts,
      status: error.httpStatus ?? 0,
      state: _safeApiState(error),
    );
    evidence.lane('alipay.catalog', 'FAIL');
    markPaymentNotRun();
    return;
  }
  if (products.isEmpty) {
    evidence.lane('alipay.catalog', 'FAIL');
    markPaymentNotRun();
    return;
  }
  if (!dependencies
      .commerceCatalogRepository
      .supportsPaymentChannelInvocation) {
    // VENDOR_BLOCKED is an explicit backend state, not a provider PASS.
    evidence.providerEvent('alipay', 'catalog', 'vendor_blocked');
    evidence.lane('alipay.catalog', 'BLOCKED');
    markPaymentNotRun();
    return;
  }
  evidence.lane('alipay.catalog', 'PASS');
  if (!paymentOwner) {
    // AVD-B is a receiver-only Tencent fixture. It may read the catalog, but
    // it must never create an order or invoke a payment SDK.
    markPaymentNotRun();
    return;
  }
  final bool optedIn =
      _allowExternalPayment &&
      _enableAlipayAppPay &&
      _paymentConfirmation == 'I_UNDERSTAND_SANDBOX_PAYMENT' &&
      (_paymentScenario == 'cancel' ||
          (_paymentScenario == 'success' &&
              _successConfirmation == 'I_UNDERSTAND_SANDBOX_SUCCESS_PAYMENT'));
  if (!optedIn) {
    // Catalog reads have no financial side effect. Creating an order, invoking
    // the native SDK, and reconciling are all withheld until explicit opt-in.
    evidence.lane('alipay.order', 'NOT_OPTED_IN');
    evidence.lane('alipay.native.launch-cancel', 'NOT_OPTED_IN');
    evidence.lane('alipay.native.launch-success', 'NOT_OPTED_IN');
    evidence.lane('alipay.query-reconcile', 'NOT_RUN');
    evidence.lane('alipay.settlement', 'NOT_RUN');
    evidence.lane('alipay.reconcile-idempotency', 'NOT_RUN');
    return;
  }
  final RechargeProduct product = products.firstWhere(
    (RechargeProduct item) => item.enabled,
    orElse: () => products.first,
  );
  RechargeOrder order;
  try {
    order = await dependencies.commerceCatalogRepository.createRechargeOrder(
      account: session.mobile,
      product: product,
      channel: PaymentChannelType.alipay,
      platform: ClientStorePlatform.android,
      youthModeEnabled: false,
    );
    evidence.route(
      capability: 'alipay.order',
      method: 'POST',
      route: routes.createAlipayRechargeOrder,
      status: 200,
      state: 'success',
    );
    evidence.lane('alipay.order', 'PASS');
  } on ApiException catch (error) {
    evidence.route(
      capability: 'alipay.order',
      method: 'POST',
      route: routes.createAlipayRechargeOrder,
      status: error.httpStatus ?? 0,
      state: _safeApiState(error),
    );
    evidence.lane('alipay.order', 'FAIL');
    evidence.lane('alipay.native.launch-cancel', 'BLOCKED');
    evidence.lane('alipay.query-reconcile', 'BLOCKED');
    return;
  }
  RechargeOrder result;
  try {
    result = await dependencies.commerceCatalogRepository.invokePayment(order);
    evidence.paymentNativeResult(result);
    if (_paymentScenario == 'cancel') {
      // The native result is only a provisional SDK outcome. The Flutter
      // repository sends the explicit cancel mutation only for trusted local
      // 6001/userCanceled evidence, then forces a DB-only status GET. The
      // final canceled state is accepted only after that first-party query.
      final bool nativeCanceled = result.hasTrustedNativeCancellationEvidence;
      if (nativeCanceled) {
        evidence.providerCallback('alipay', 'launch_cancel');
      }
      evidence.route(
        capability: 'alipay.native.launch-cancel',
        method: 'SDK',
        route: 'AlipaySDK.pay',
        status: 200,
        state: nativeCanceled ? 'provisional_cancel' : 'provisional_non_cancel',
      );
      final RechargeOrder reconciled = await dependencies
          .commerceCatalogRepository
          .queryRechargeOrder(result);
      evidence.route(
        capability: 'alipay.query-reconcile',
        method: 'POST+GET',
        route: nativeCanceled
            ? '${routes.cancelAlipayRechargeOrder}+${routes.alipayRechargeOrderStatus}'
            : '${routes.reconcileAlipayRechargeOrder}+${routes.alipayRechargeOrderStatus}',
        status: 200,
        state: 'authoritative',
      );
      final bool canceled = reconciled.state == RechargeOrderState.canceled;
      evidence.lane(
        'alipay.native.launch-cancel',
        nativeCanceled && canceled ? 'PASS' : 'FAIL',
      );
      evidence.lane(
        'alipay.query-reconcile',
        nativeCanceled && canceled ? 'PASS' : 'FAIL',
      );
      evidence.lane('alipay.native.launch-success', 'NOT_RUN');
      evidence.lane('alipay.settlement', 'NOT_RUN');
      evidence.lane('alipay.reconcile-idempotency', 'NOT_RUN');
      return;
    }

    // Only the exact native 9000 result is eligible for a success evidence
    // lane. A backend success after cancellation, processing, or timeout is
    // still authoritative order state, but it is never SDK success evidence.
    final bool nativeSdkSuccess =
        result.sdkCompleted == true && result.resultStatus == '9000';
    evidence.route(
      capability: 'alipay.native.launch-success',
      method: 'SDK',
      route: 'AlipaySDK.pay',
      status: 200,
      state: nativeSdkSuccess
          ? 'provisional_sdk_result_9000'
          : 'provisional_sdk_result_not_9000',
    );
    final bool firstSucceeded = result.state == RechargeOrderState.succeeded;
    evidence.route(
      capability: 'alipay.query-reconcile',
      method: 'POST+GET',
      route:
          '${routes.reconcileAlipayRechargeOrder}+${routes.alipayRechargeOrderStatus}',
      status: 200,
      state: firstSucceeded
          ? 'authoritative_succeeded'
          : 'authoritative_not_succeeded',
    );
    if (!nativeSdkSuccess || !firstSucceeded) {
      evidence.lane('alipay.native.launch-success', 'FAIL');
      evidence.lane('alipay.query-reconcile', 'FAIL');
      evidence.lane('alipay.settlement', 'BLOCKED');
      evidence.lane('alipay.reconcile-idempotency', 'BLOCKED');
      return;
    }
    final RechargeOrder repeated = await dependencies.commerceCatalogRepository
        .queryRechargeOrder(
          result.copyWith(state: RechargeOrderState.confirming),
        );
    final bool repeatedSucceeded =
        repeated.state == RechargeOrderState.succeeded &&
        repeated.orderNo == result.orderNo;
    evidence.route(
      capability: 'alipay.query-reconcile.repeat',
      method: 'POST+GET',
      route:
          '${routes.reconcileAlipayRechargeOrder}+${routes.alipayRechargeOrderStatus}',
      status: 200,
      state: repeatedSucceeded
          ? 'authoritative_repeated_succeeded'
          : 'authoritative_repeat_mismatch',
    );
    evidence.paymentSuccessFlowVerified(repeatedSucceeded);
    // Delay the provider success marker until both the exact native status
    // and the repeated authoritative backend success are proven. The marker
    // is therefore never synthesized from a client callback alone.
    if (repeatedSucceeded) {
      evidence.providerCallback('alipay', 'launch_success');
    }
    evidence.lane(
      'alipay.native.launch-success',
      nativeSdkSuccess && repeatedSucceeded ? 'PASS' : 'FAIL',
    );
    evidence.lane(
      'alipay.query-reconcile',
      repeatedSucceeded ? 'PASS' : 'FAIL',
    );
    // These lanes are closed only after DB evidence proves the verified event,
    // one credit and one balanced two-posting journal. The integration marker
    // records that the HTTP authority was exercised twice.
    evidence.lane('alipay.settlement', repeatedSucceeded ? 'PASS' : 'FAIL');
    evidence.lane(
      'alipay.reconcile-idempotency',
      repeatedSucceeded ? 'PASS' : 'FAIL',
    );
  } on ApiException catch (error) {
    evidence.route(
      capability: 'alipay.query-reconcile',
      method: 'POST+GET',
      route: routes.alipayRechargeOrderStatus,
      status: error.httpStatus ?? 0,
      state: _safeApiState(error),
    );
    evidence.lane(
      _paymentScenario == 'success'
          ? 'alipay.native.launch-success'
          : 'alipay.native.launch-cancel',
      'FAIL',
    );
    evidence.lane('alipay.query-reconcile', 'FAIL');
    evidence.lane('alipay.settlement', 'BLOCKED');
    // finish() fills the success-only idempotency lane exactly once when the
    // exception path has not reached the repeated reconcile call.
  }
}

Future<_RuntimeConfig> _fetchRuntimeConfig() async {
  if (_runtimeConfigPort < 1) {
    throw TestFailure('M5 runtime config relay is not configured.');
  }
  final String token = await _readRuntimeToken();
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 5);
  try {
    final HttpClientRequest request = await client
        .get('10.0.2.2', _runtimeConfigPort, _runtimeConfigPath)
        .timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 5),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw TestFailure('M5 runtime config relay rejected the request.');
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw TestFailure('M5 runtime config relay returned an invalid object.');
    }
    final String phone = decoded['phone']?.toString().trim() ?? '';
    final String oauthClientId =
        decoded['oauthClientId']?.toString().trim() ?? '';
    final String role = decoded['role']?.toString().trim() ?? '';
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone) ||
        oauthClientId.isEmpty ||
        (role != 'sender' && role != 'receiver')) {
      throw TestFailure('M5 runtime config relay omitted required values.');
    }
    return _RuntimeConfig(
      phone: phone,
      oauthClientId: oauthClientId,
      relayToken: token,
      role: role,
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _postRelaySignal(_RuntimeConfig config, String path) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 3);
  try {
    final HttpClientRequest request = await client
        .post('10.0.2.2', _runtimeConfigPort, path)
        .timeout(const Duration(seconds: 3));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${config.relayToken}',
    );
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 3),
    );
    await response.drain<void>();
    if (response.statusCode != HttpStatus.ok) {
      throw TestFailure('M5 relay coordination request was rejected.');
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _postRelayJson(
  _RuntimeConfig config,
  String path,
  Map<String, Object?> payload,
) async {
  final List<int> encodedPayload = utf8.encode(jsonEncode(payload));
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 3);
  try {
    final HttpClientRequest request = await client
        .post('10.0.2.2', _runtimeConfigPort, path)
        .timeout(const Duration(seconds: 3));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${config.relayToken}')
      ..contentType = ContentType.json;
    request.contentLength = encodedPayload.length;
    request.add(encodedPayload);
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 3),
    );
    await response.drain<void>();
    if (response.statusCode != HttpStatus.ok) {
      throw TestFailure('M5 relay coordination request was rejected.');
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _registerRelayFirstPartyUserId(
  _RuntimeConfig config,
  int userId,
) async {
  if (userId <= 0) {
    throw TestFailure('M5 authenticated userId is invalid.');
  }
  await _postRelayJson(config, '/m5/c2c/identity', <String, Object?>{
    'firstPartyUserId': userId,
  });
}

Future<int?> _pollRelayPeerUserId(
  _RuntimeConfig config,
  int currentUserId,
) async {
  for (int attempt = 0; attempt < _workerCycleWaitAttempts; attempt += 1) {
    final int? targetUserId = await _readRelayIntValue(
      config,
      '/m5/c2c/peer',
      'targetUserId',
    );
    if (targetUserId != null &&
        targetUserId > 0 &&
        targetUserId != currentUserId) {
      return targetUserId;
    }
    await Future<void>.delayed(_workerCycleWaitStep);
  }
  return null;
}

Future<bool> _readRelaySignal(_RuntimeConfig config, String path) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 3);
  try {
    final HttpClientRequest request = await client
        .get('10.0.2.2', _runtimeConfigPort, path)
        .timeout(const Duration(seconds: 3));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${config.relayToken}',
    );
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 3),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      return false;
    }
    final Object? decoded = jsonDecode(body);
    return decoded is Map<String, Object?> && decoded['ready'] == true;
  } catch (_) {
    // Coordination is fail-closed: an unavailable relay cannot become a
    // provider PASS and the caller will record BLOCKED/PARTIAL.
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<String?> _readRelayValue(
  _RuntimeConfig config,
  String path,
  String key,
) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 3);
  try {
    final HttpClientRequest request = await client
        .get('10.0.2.2', _runtimeConfigPort, path)
        .timeout(const Duration(seconds: 3));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${config.relayToken}',
    );
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 3),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      return null;
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['ready'] != true) {
      return null;
    }
    final String value = decoded[key]?.toString().trim() ?? '';
    return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value)
        ? value
        : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<int?> _readRelayIntValue(
  _RuntimeConfig config,
  String path,
  String key,
) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 3);
  try {
    final HttpClientRequest request = await client
        .get('10.0.2.2', _runtimeConfigPort, path)
        .timeout(const Duration(seconds: 3));
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${config.relayToken}',
    );
    final HttpClientResponse response = await request.close().timeout(
      const Duration(seconds: 3),
    );
    final String body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      return null;
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['ready'] != true) {
      return null;
    }
    final Object? value = decoded[key];
    return value is int && value > 0 ? value : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<String> _readRuntimeToken() async {
  for (int attempt = 0; attempt < 80; attempt += 1) {
    for (final String path in <String>[
      _runtimeTokenPath,
      _runtimeTokenFallbackPath,
    ]) {
      final File file = File(path);
      try {
        if (!await file.exists()) {
          continue;
        }
        final String token = (await file.readAsString()).trim();
        try {
          await file.delete();
        } on FileSystemException {
          // The token is already in memory; a concurrent feeder may remove it.
        }
        if (RegExp(r'^[A-Za-z0-9_-]{64,256}$').hasMatch(token)) {
          return token;
        }
      } on FileSystemException {
        // Retry without logging the token or the filesystem exception.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 125));
  }
  throw TestFailure('M5 runtime config relay credential was unavailable.');
}

class _RuntimeConfig {
  const _RuntimeConfig({
    required this.phone,
    required this.oauthClientId,
    required this.relayToken,
    required this.role,
  });

  final String phone;
  final String oauthClientId;
  // Kept in memory only. It is never added to a marker, exception, or
  // screenshot; the relay uses it to bind sender/receiver coordination to
  // this single emulator run.
  final String relayToken;
  final String role;
}

class _M5Evidence {
  _M5Evidence({required this.avd, required this.binding});

  String avd;
  final IntegrationTestWidgetsFlutterBinding binding;
  final List<String> _routes = <String>[];
  final List<String> _events = <String>[];
  final Map<String, String> _lanes = <String, String>{};
  final Set<String> _invariants = <String>{};
  final Set<String> _violations = <String>{};
  int _tencentProviderCalls = 0;
  int _alipayProviderCalls = 0;
  bool _paymentOptedIn = false;
  bool _paymentOwner = false;
  bool _paymentSuccessFlowVerified = false;
  bool? _alipaySdkCompleted;
  String? _alipayResultStatus;
  bool c2cHintObserved = false;
  final Set<String> _c2cHintMessageIds = <String>{};
  bool roomHintObserved = false;
  final Set<String> _roomHintMessageIds = <String>{};
  bool _roomHintWindow = false;
  bool _sdkCallbackObserved = false;

  static const Set<String> coreLanes = <String>{
    'tencent.credential',
    'tencent.login',
    'tencent.c2c.http-authority',
    'tencent.avchatroom.hint',
    'tencent.avchatroom.leave',
    'alipay.catalog',
  };

  static const Set<String> cancelPaymentLanes = <String>{
    'alipay.order',
    'alipay.native.launch-cancel',
    'alipay.query-reconcile',
  };

  static const Set<String> successPaymentLanes = <String>{
    'alipay.order',
    'alipay.native.launch-success',
    'alipay.query-reconcile',
    'alipay.settlement',
    'alipay.reconcile-idempotency',
  };

  void viewport(WidgetTester tester, String role) {
    final ({double width, double height, double dpr}) expected =
        _viewportForRole(role);
    final double dpr = tester.view.devicePixelRatio;
    final Size size = Size(
      tester.view.physicalSize.width / dpr,
      tester.view.physicalSize.height / dpr,
    );
    if ((dpr - expected.dpr).abs() > 0.01 ||
        (size.width - expected.width).abs() > 0.1 ||
        (size.height - expected.height).abs() > 0.1) {
      violation('viewport_mismatch');
    }
    debugPrint(
      'M5_VIEWPORT::$avd::${size.width.toStringAsFixed(0)}x'
      '${size.height.toStringAsFixed(0)}::${dpr.toStringAsFixed(2)}',
    );
  }

  void route({
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
        'M5_ROUTE_STATUS::$safeCapability::$method::$route::$status::$safeState';
    _routes.add(marker);
    if (status < 200 || status >= 600 || status >= 500) {
      violation('$safeCapability:unsafe_route_status');
    }
    debugPrint(marker);
  }

  void providerEvent(String provider, String event, String state) {
    final String safeProvider = provider.replaceAll(
      RegExp(r'[^A-Za-z0-9_.-]'),
      '_',
    );
    final String safeEvent = event.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final String safeState = state.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final String marker =
        'M5_VENDOR_EVENT::$safeProvider::$safeEvent::$safeState';
    _events.add(marker);
    debugPrint(marker);
  }

  void providerCallback(String provider, String event) {
    if (provider == 'tencent-im') {
      _tencentProviderCalls += 1;
    } else if (provider == 'alipay') {
      _alipayProviderCalls += 1;
    } else {
      violation('unknown_provider_callback');
      return;
    }
    _sdkCallbackObserved = true;
    providerEvent(provider, event, 'sdk_callback');
  }

  void beginC2cHintAttempt() {
    c2cHintObserved = false;
    _c2cHintMessageIds.clear();
    roomHintObserved = false;
    _roomHintMessageIds.clear();
    _roomHintWindow = false;
  }

  bool hasC2cHintForMessage(String messageId) =>
      _c2cHintMessageIds.contains(messageId);

  void beginRoomHintAttempt() {
    roomHintObserved = false;
    _roomHintMessageIds.clear();
    _roomHintWindow = true;
  }

  void endRoomHintAttempt() {
    _roomHintWindow = false;
  }

  bool hasRoomHintForMessage(String messageId) =>
      _roomHintMessageIds.contains(messageId);

  void roomHintFromSdk(ImRefreshHint hint) {
    if (!_roomHintWindow) {
      return;
    }
    roomHintObserved = true;
    _roomHintMessageIds.add(hint.messageId);
    providerCallback('tencent-im', 'avchatroom_refresh_hint');
  }

  void providerEventFromSdk(ImSessionEvent event) {
    switch (event.kind) {
      case ImSessionEventKind.networkOffline:
        providerEvent('tencent-im', 'network_offline', 'observed');
        lane('tencent.outage.fallback', 'PASS');
      case ImSessionEventKind.networkOnline:
        providerEvent('tencent-im', 'network_online', 'observed');
      case ImSessionEventKind.userSigExpired:
        providerEvent('tencent-im', 'usersig_expired', 'observed');
      case ImSessionEventKind.refreshHint:
        final ImRefreshHint? hint = event.refreshHint;
        if (hint != null) {
          if (_roomHintWindow) {
            // Group custom elements arrive on the separate roomEvents stream;
            // this branch only admits private hints. Keeping the distinction
            // explicit prevents a C2C callback from satisfying AVChatRoom.
            return;
          }
          c2cHintObserved = true;
          _c2cHintMessageIds.add(hint.messageId);
          providerCallback('tencent-im', 'refresh_hint');
        }
    }
  }

  void paymentOptIn(bool value, {required bool owner}) {
    _paymentOptedIn = value;
    _paymentOwner = owner;
    debugPrint('M5_PAYMENT_OPT_IN::${value ? 1 : 0}');
  }

  void paymentSuccessFlowVerified(bool value) {
    _paymentSuccessFlowVerified = value;
    debugPrint('M5_PAYMENT_SUCCESS_FLOW_VERIFIED::${value ? 1 : 0}');
  }

  void paymentNativeResult(RechargeOrder order) {
    _alipaySdkCompleted = order.sdkCompleted;
    _alipayResultStatus = order.resultStatus;
    debugPrint(
      'M5_ALIPAY_NATIVE_RESULT::sdkCompleted='
      '${order.sdkCompleted == true ? 1 : 0}::resultStatus='
      '${order.resultStatus ?? 'none'}',
    );
  }

  void lane(String name, String state) {
    final String safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final String safeState = state.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    _lanes[safeName] = safeState;
    debugPrint('M5_LANE::$safeName::$safeState');
  }

  void invariant(String value) {
    final String safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    _invariants.add(safe);
    debugPrint('M5_AUTHORITY_INVARIANT::$safe');
  }

  void violation(String value) {
    final String safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    _violations.add(safe);
  }

  bool finish() {
    // Outage fallback is an independent resilience observation. The runner
    // does not manufacture an outage, so NOT_RUN is never mixed into the
    // provider core verdict.
    _lanes.putIfAbsent('tencent.outage.fallback', () => 'NOT_RUN');
    final Set<String> requiredPaymentLanes = _paymentScenario == 'success'
        ? successPaymentLanes
        : cancelPaymentLanes;
    final Set<String> requiredLanes = <String>{
      ...coreLanes,
      if (_paymentOptedIn && _paymentOwner) ...requiredPaymentLanes,
    };
    final Set<String> missing = requiredLanes.difference(_lanes.keys.toSet());
    for (final String laneName in missing) {
      _lanes[laneName] = 'BLOCKED';
    }
    final bool lanesPass = requiredLanes.every(
      (String name) => _lanes[name] == 'PASS',
    );
    if (_tencentProviderCalls <= 0) {
      violation('tencent_sdk_callback_missing');
    }
    if (_paymentOptedIn && _paymentOwner && _alipayProviderCalls <= 0) {
      violation('alipay_sdk_callback_missing');
    }
    if (!_sdkCallbackObserved) {
      violation('provider_sdk_callback_missing');
    }
    if (_routes.isEmpty || _events.isEmpty || _invariants.length < 2) {
      violation('evidence_schema_incomplete');
    }
    final bool corePass = coreLanes.every(
      (String name) => _lanes[name] == 'PASS',
    );
    final bool paymentPass =
        !_paymentOwner ||
        requiredPaymentLanes.every((String name) => _lanes[name] == 'PASS');
    final bool cancelOnlyPayment =
        _paymentOptedIn && _paymentScenario == 'cancel';
    final bool successPayment =
        _paymentOptedIn && _paymentOwner && _paymentScenario == 'success';
    final bool fullyPass =
        _violations.isEmpty && lanesPass && corePass && paymentPass;
    final String verdict;
    if (_paymentOptedIn) {
      verdict = cancelOnlyPayment
          ? (fullyPass ? 'PARTIAL' : 'FAIL')
          : (fullyPass ? 'PASS' : 'FAIL');
    } else {
      // A no-payment run is useful evidence and deliberately does not claim a
      // full commerce PASS. Missing live credentials remain explicit PARTIAL.
      verdict = _violations.isEmpty && corePass ? 'NO_PAY' : 'PARTIAL';
    }
    final Map<String, Object?> report = <String, Object?>{
      'avd': avd,
      'tested_git_sha': _expectedFlutterSha,
      'backend_sha': _expectedBackendSha,
      'backend_source_digest': _expectedBackendDigest,
      'providerCalls': <String, int>{
        'tencentIm': _tencentProviderCalls,
        'alipay': _alipayProviderCalls,
      },
      'providerCallEvidence': _sdkCallbackObserved
          ? 'real_sdk_callbacks'
          : 'none',
      'secretsInClient': false,
      'paymentOptIn': _paymentOptedIn,
      'paymentMode': cancelOnlyPayment
          ? 'cancel_only'
          : (successPayment ? 'success' : 'none'),
      'paymentSuccessProven':
          successPayment && _paymentSuccessFlowVerified && fullyPass,
      'paymentFlowVerified': successPayment && _paymentSuccessFlowVerified,
      'alipayNativeResult': <String, Object?>{
        'sdkCompleted': _alipaySdkCompleted,
        'resultStatus': _alipayResultStatus,
      },
      'reconcileRepeat': successPayment && _paymentSuccessFlowVerified
          ? 'PASS'
          : 'NOT_RUN',
      'paymentInvoked': _alipayProviderCalls > 0,
      'resilienceVerdict': _lanes['tencent.outage.fallback'],
      'lanes': _lanes,
      'routeMarkerCount': _routes.toSet().length,
      'vendorEventCount': _events.toSet().length,
      'authorityInvariantCount': _invariants.length,
      'violations': _violations.toList()..sort(),
      'acceptance': verdict,
      'result': verdict,
    };
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['m5VendorLiveAcceptance'] = report;
    debugPrint(
      'M5_PROVIDER_CALLS::$_tencentProviderCalls::$_alipayProviderCalls',
    );
    debugPrint('M5_VENDOR_EVENTS::${_events.toSet().length}');
    debugPrint('M5_ROUTE_MARKERS::${_routes.toSet().length}');
    debugPrint('M5_SECRETS_IN_CLIENT::0');
    debugPrint('M5_RESILIENCE::${_lanes['tencent.outage.fallback']}');
    debugPrint('M5_ACCEPTANCE::$verdict');
    // Default zero-payment runs complete with an explicit NO_PAY/PARTIAL
    // verdict so the shell harness can report safety state without treating
    // it as a product/provider PASS. Cancel-only opt-in intentionally remains
    // PARTIAL/nonzero. Success is PASS only after two authoritative
    // reconciles; the aggregate additionally requires database settlement
    // evidence.
    if (cancelOnlyPayment) {
      // The shell runner translates a complete cancel-only evidence report to
      // PARTIAL. Returning true here keeps the process-level integration
      // result green enough to preserve the truthful non-success verdict and
      // lets the aggregate enforce its required nonzero conclusion.
      return fullyPass;
    }
    return !_paymentOptedIn || verdict == 'PASS';
  }
}

String _safeApiState(ApiException error) => switch (error.kind) {
  ApiFailureKind.unauthorized || ApiFailureKind.forbidden => 'blocked',
  ApiFailureKind.business ||
  ApiFailureKind.validation ||
  ApiFailureKind.conflict => 'domain_blocked',
  ApiFailureKind.server => 'backend_blocked',
  ApiFailureKind.network || ApiFailureKind.timeout => 'unavailable',
  ApiFailureKind.protocol => 'contract_failure',
  ApiFailureKind.configuration => 'configuration_failure',
};

bool _isSha40(String value) => RegExp(r'^[0-9a-f]{40}$').hasMatch(value);

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

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

Future<void> _waitForAuthenticatedHome(
  WidgetTester tester,
  AuthController controller, {
  required String description,
}) async {
  await _waitFor(
    tester,
    () =>
        find.byKey(const Key('live-home-ready')).evaluate().isNotEmpty ||
        controller.errorMessage != null ||
        find
            .byKey(const Key('account-access-gate-error'))
            .evaluate()
            .isNotEmpty ||
        find
            .byKey(const Key('account-restricted-status'))
            .evaluate()
            .isNotEmpty ||
        find
            .byKey(const Key('account-unusable-status'))
            .evaluate()
            .isNotEmpty ||
        find.byKey(const Key('live-version-policy')).evaluate().isNotEmpty,
    description: description,
  );
  if (find.byKey(const Key('live-home-ready')).evaluate().isEmpty) {
    throw TestFailure('M5 authentication did not reach the live home.');
  }
}
