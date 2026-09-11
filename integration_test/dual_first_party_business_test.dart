import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

import 'dual_first_party_business_support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'dual first-party UI business with automatic sync and separate recovery',
    (tester) async {
      validateDualEnvironment(AppEnvironment.fromDefines());
      if (const String.fromEnvironment('OAUTH_CLIENT_ID') != '') {
        throw TestFailure('Client configuration must come from private relay.');
      }
      final role = await readDualRuntimeRole();
      const port = int.fromEnvironment('DUAL_RELAY_PORT');
      final relay = DualRelay(port, role);
      addTearDown(relay.close);
      final config = DualConfig(await relay.request('/dual/config'), role);
      final dependencies = AppDependencies.forTestEnvironment(
        environment: config.environment,
        initialStorage: {
          'auth.session.v2': config.session.encode(),
          AuthSessionManager.consentStorageKey:
              AuthSessionManager.consentStorageValue,
        },
      );
      addTearDown(() async {
        // On a failed phase the chat route may still own timers/listeners.
        // Unmount it before disposing the services those callbacks access.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        dependencies.dispose();
      });
      await dependencies.authController.initialize();
      expect(
        dependencies.sessionManager.session?.userId == config.session.userId,
        isTrue,
      );
      var sequence = 0;
      String? giftRequestId;
      // Production controller, repositories and page; the sole seam assigns
      // correlation IDs, never invokes a business operation or returns a result.
      RoomController createController() => RoomController(
        roomId: config.roomId,
        title: 'Dual first-party',
        currentUserId: config.session.userId,
        accessToken: config.session.accessToken,
        repository: dependencies.roomRepository,
        roomOperationsRepository: dependencies.roomOperationsRepository,
        rtcAdapter: dependencies.rtcAdapter,
        realtimeGateway: dependencies.realtimeGateway,
        tencentImAvChatRoomCoordinator:
            dependencies.tencentImAvChatRoomCoordinator,
        sessionChanges: dependencies.sessionManager,
        identityGeneration: () =>
            dependencies.sessionManager.identityGeneration,
        activeUserId: () => dependencies.sessionManager.session?.userId,
        lifecycleBinding: binding,
        allowSyntheticPublicMessages: false,
        requestIdGenerator: (prefix) {
          if (prefix == 'room-gift') {
            return giftRequestId = 'dual-${config.runId}-$role-gift';
          }
          final id = 'dual-${config.runId}-$role-${sequence++}';
          return id;
        },
      );
      var controller = createController();
      addTearDown(() => controller.dispose());
      final navigation = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        AppDependencyScope(
          dependencies: dependencies,
          child: MaterialApp(
            navigatorKey: navigation,
            theme: AppTheme.dark(),
            // A route underneath the production room lets its real exit
            // callback pop and unmount it, rather than strand a root route.
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      void openRoom() {
        final nextController = controller;
        navigation.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => VideoRuntimeRoomPage(
              controller: nextController,
              allowMinimize: false,
            ),
          ),
        );
      }

      openRoom();
      await _until(
        tester,
        () => controller.status == RoomSessionStatus.joined,
        'room entry',
      );
      expect(controller.isSnapshotOnly, isTrue);
      final firstLease = controller.snapshot!.sessionId;
      expect(firstLease, isNotNull);
      expect(firstLease, isNotEmpty);
      await _barrier(tester, relay, config, 'joined');
      final members = await dependencies.roomOperationsRepository
          .fetchOnlineMembers(roomId: config.roomId, page: 1);
      expect(
        members.items.any((m) => m.userId == config.session.userId),
        isTrue,
      );
      expect(members.items.any((m) => m.userId == config.peerUserId), isTrue);
      final firstApproval = await _seatPairThroughApproval(
        tester,
        dependencies,
        controller,
        config,
      );
      await _barrier(tester, relay, config, 'seated');
      await _until(
        tester,
        () => controller.seats.any(
          (seat) => seat.userId == config.peerUserId && seat.isOccupied,
        ),
        'automatic peer mic entry',
        timeout: const Duration(seconds: 5),
      );
      final seated = await dependencies.roomOperationsRepository
          .fetchOnlineMembers(roomId: config.roomId, page: 1);
      expect(
        seated.items
            .where(
              (m) =>
                  m.isOnMic &&
                  {config.session.userId, config.peerUserId}.contains(m.userId),
            )
            .length,
        2,
      );

      final publicText = config.message(role, 'public');
      final publicActionWatch = Stopwatch()..start();
      void tracePublic(String step) {
        // Fixed QA facts only, never request bodies, credentials or errors.
        debugPrint(
          'DUAL_PUBLIC_TRACE::$role::$step::'
          'elapsedMs=${publicActionWatch.elapsedMilliseconds}::'
          'joined=${controller.status == RoomSessionStatus.joined}::'
          'canSend=${controller.canSendPublicMessage}::'
          'errorPresent=${controller.errorMessage != null}::'
          'ownVisible=${controller.messages.any((m) => m.content == publicText)}',
        );
      }

      tracePublic('before_focus');
      // Focusing changes the room dock into the composer. Wait for that
      // replacement before typing, then use its visible send callback.
      await _tap(tester, find.byKey(const Key('video-room-composer')));
      tracePublic('after_focus');
      await _until(
        tester,
        () => find.byTooltip('发送').hitTestable().evaluate().length == 1,
        'public send button',
      );
      await tester.enterText(
        find.byKey(const Key('video-room-composer')),
        publicText,
      );
      tracePublic('after_input');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('video-room-composer')))
            .controller!
            .text,
        publicText,
      );
      expect(
        tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) => widget is IconButton && widget.tooltip == '发送',
                  ),
                )
                .onPressed !=
            null,
        isTrue,
        reason: 'Public send must be enabled before the real UI tap.',
      );
      tracePublic('before_send');
      await _tap(tester, find.byTooltip('发送'));
      tracePublic('after_send');
      FocusManager.instance.primaryFocus?.unfocus();
      // Unfocus unregisters the test input connection on a live device.
      // Do not call TestTextInput.hide() after that connection has closed.
      await tester.pump(const Duration(milliseconds: 300));
      await _until(tester, () {
        if (controller.errorMessage != null ||
            controller.status != RoomSessionStatus.joined) {
          tracePublic('send_rejected');
          throw TestFailure('Public send rejected; see fixed QA facts.');
        }
        return controller.messages.any((m) => m.content == publicText);
      }, 'own public send');
      tracePublic('send_committed');
      await _barrier(tester, relay, config, 'public-sent');
      final peerPublic = config.message(config.peerRole, 'public');
      // Both users have committed a message and stay in the same room. This
      // gate proves automatic first-party recovery, not vendor IM delivery.
      final publicReceiveWatch = Stopwatch()..start();
      await _until(
        tester,
        () => find.textContaining(peerPublic).evaluate().isNotEmpty,
        'automatic peer public receive',
        timeout: const Duration(seconds: 5),
      );
      publicReceiveWatch.stop();
      final visibleBeforeReentry = true;
      await _tap(tester, find.text('更多'));
      await _tap(tester, find.text('工具'));
      await _tap(tester, find.text('主动下麦'));
      await _until(
        tester,
        () => !controller.isOnMic,
        'pre-reentry self mic leave',
      );
      await _barrier(tester, relay, config, 'reentry-off-mic');
      await _until(
        tester,
        () => !controller.seats.any(
          (seat) => seat.userId == config.peerUserId && seat.isOccupied,
        ),
        'automatic peer mic leave',
        timeout: const Duration(seconds: 5),
      );
      await _expectPairAuthority(dependencies, config, seated: false);
      await _tap(tester, find.text('更多'));
      await _tap(tester, find.text('工具'));
      await _tap(tester, find.text('离开房间'));
      await _tap(tester, find.text('确认离开'));
      await _until(
        tester,
        () => controller.status == RoomSessionStatus.left,
        'confirmed UI room exit',
      );
      // Wait for the pop transition and page listeners to be disposed before
      // disposing the old controller. UI leave has awaited transport cleanup.
      await _until(
        tester,
        () => find
            .byType(VideoRuntimeRoomPage, skipOffstage: false)
            .evaluate()
            .isEmpty,
        'old room page unmounted',
      );
      controller.dispose();
      await _barrier(tester, relay, config, 'reentry-left');
      controller = createController();
      expect(controller.status, RoomSessionStatus.idle);
      openRoom();
      await _until(
        tester,
        () => controller.status == RoomSessionStatus.joined,
        'new room lease joined',
      );
      expect(controller.snapshot!.sessionId, isNotNull);
      expect(controller.snapshot!.sessionId, isNotEmpty);
      expect(controller.snapshot!.sessionId, isNot(firstLease));
      await _until(
        tester,
        () => find.textContaining(peerPublic).evaluate().isNotEmpty,
        'peer public after manual_room_reentry',
      );
      final history = await dependencies.roomRepository.fetchPublicMessages(
        config.roomId,
      );
      expect(
        history.any(
          (m) => m.senderId == config.peerUserId && m.content == peerPublic,
        ),
        isTrue,
      );
      await _expectPairAuthority(dependencies, config, seated: false);
      await _barrier(tester, relay, config, 'manual_room_reentry');
      final secondApproval = await _seatPairThroughApproval(
        tester,
        dependencies,
        controller,
        config,
      );
      expect(secondApproval, isNot(firstApproval));
      // Both wallets are sampled BEFORE the existing barrier releases either
      // gift sender. No extra host phase or cross-device clock is required.
      final giftStart = await dependencies.commerceRepository
          .fetchWalletSummary();
      expect(giftStart.coinPrecision, isNotNull);
      expect(
        giftStart.incomeCapability.role,
        role == 'A' ? IncomeRole.guildChair : IncomeRole.ordinary,
      );
      await _barrier(tester, relay, config, 'gift-seated');
      await _until(
        tester,
        () => controller.seats.any(
          (seat) => seat.userId == config.peerUserId && seat.isOccupied,
        ),
        'automatic peer gift seat',
        timeout: const Duration(seconds: 5),
      );

      final star =
          (await dependencies.commerceCatalogRepository.fetchGiftCatalog())
              .singleWhere(
                (g) =>
                    g.enabled && g.id == '00000000-0000-0000-0000-000000002001',
              );
      // Serialize the two gift transfers while both devices remain in the room,
      // so each sender's exact wallet delta cannot race the reciprocal transfer.
      String? sentTransferId;
      for (final sender in ['A', 'B']) {
        if (role == sender) {
          final before = await dependencies.commerceRepository
              .fetchWalletSummary();
          expect(
            before.coinPrecision != null &&
                before.giftCoins!.coversWholeCoins(star.price),
            isTrue,
          );
          await _tap(tester, find.text('礼物'));
          await _until(
            tester,
            () => find.byType(GiftSheet).evaluate().isNotEmpty,
            'gift sheet',
          );
          final sheet = tester.widget<GiftSheet>(find.byType(GiftSheet));
          expect(sheet.targets.length, 1);
          expect(sheet.targets.single.userId == config.peerUserId, isTrue);
          await _tap(tester, find.text(star.category.label));
          await _tap(tester, find.text(star.name));
          await _tap(tester, find.textContaining(RegExp(r'^赠送(?: ·)? \d+$')));
          await _until(
            tester,
            () => find.byType(GiftSheet).evaluate().isEmpty,
            'UI gift completion',
          );
          expect(giftRequestId != null, isTrue);
          final receipt = await dependencies.roomRepository.fetchGiftReceipt(
            requestId: giftRequestId,
            currentUserId: config.session.userId,
            senderUserId: config.session.userId,
            receiverUserId: config.peerUserId,
          );
          expect(receipt.success, isTrue);
          expect(
            receipt.roomId == config.roomId &&
                receipt.giftId == star.id.toString(),
            isTrue,
          );
          expect(
            receipt.senderUserId == config.session.userId &&
                receipt.receiverUserId == config.peerUserId,
            isTrue,
          );
          expect(receipt.quantity, 1);
          expect(receipt.requestId, giftRequestId);
          expectDualGiftIncome(
            receipt,
            price: star.price,
            cashEligible: role == 'B',
          );
          expect(receipt.transferId?.isNotEmpty, isTrue);
          sentTransferId = receipt.transferId;
          expect(receipt.providerInvocation, isFalse);
          final after = await dependencies.commerceRepository
              .fetchWalletSummary();
          expect(after.coinPrecision, isNotNull);
          expect(
            after.giftCoins!.tenths,
            before.giftCoins!.tenths -
                BigInt.from(star.price) * BigInt.from(10),
          );
          // Historical GET receipts attest immutable transfer fields, not a
          // current balance. The wallet delta above and host per-transfer
          // ledger checks remain mandatory; do not invent a GET balance field.
        }
        await _barrier(tester, relay, config, 'gift-$sender');
      }
      final incoming = await dependencies.roomRepository.fetchGiftReceipt(
        requestId: 'dual-${config.runId}-${config.peerRole}-gift',
        currentUserId: config.session.userId,
        senderUserId: config.peerUserId,
        receiverUserId: config.session.userId,
      );
      expect(incoming.success && incoming.quantity == 1, isTrue);
      expect(
        incoming.roomId == config.roomId &&
            incoming.giftId == star.id.toString(),
        isTrue,
      );
      expect(
        incoming.senderUserId == config.peerUserId &&
            incoming.receiverUserId == config.session.userId,
        isTrue,
      );
      expect(incoming.providerInvocation, isFalse);
      expect(sentTransferId, isNotNull);
      expect(incoming.transferId, isNotNull);
      expect(incoming.transferId, isNotEmpty);
      expect(incoming.transferId, isNot(sentTransferId));
      expect(
        incoming.requestId,
        'dual-${config.runId}-${config.peerRole}-gift',
      );
      expectDualGiftIncome(
        incoming,
        price: star.price,
        cashEligible: role == 'A',
      );
      final giftEnd = await dependencies.commerceRepository
          .fetchWalletSummary();
      expectDualGiftSettlement(
        before: giftStart,
        after: giftEnd,
        price: star.price,
        chair: role == 'A',
      );
      await _tap(tester, find.text('更多'));
      await _tap(tester, find.text('工具'));
      await _tap(tester, find.text('主动下麦'));
      await _until(tester, () => !controller.isOnMic, 'self mic leave');
      final offMic = await dependencies.roomOperationsRepository
          .fetchOnlineMembers(roomId: config.roomId, page: 1);
      expect(
        offMic.items.any(
          (m) => m.userId == config.session.userId && !m.isOnMic,
        ),
        isTrue,
      );
      await _barrier(tester, relay, config, 'off-mic');
      await _until(
        tester,
        () => !controller.seats.any(
          (seat) => seat.userId == config.peerUserId && seat.isOccupied,
        ),
        'automatic final peer mic leave',
        timeout: const Duration(seconds: 5),
      );
      await _expectPairAuthority(dependencies, config, seated: false);

      // Route directly to the existing profile page; all relation/chat writes
      // still require its visible controls and production callbacks.
      final profile = await dependencies.socialRepository.fetchPublicProfile(
        config.peerUserId,
      );
      expect(profile.user.isFollowing, isFalse);
      navigation.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => PublicProfilePage(userId: config.peerUserId),
        ),
      );
      await _tap(tester, find.widgetWithText(FilledButton, '关注'));
      await _until(
        tester,
        () => find.text('取消关注').evaluate().isNotEmpty,
        'follow UI',
      );
      expect(
        (await dependencies.socialRepository.fetchPublicProfile(
          config.peerUserId,
        )).user.isFollowing,
        isTrue,
      );
      await _tap(tester, find.text('私聊'));
      await _until(
        tester,
        () => find.byType(TextField).hitTestable().evaluate().isNotEmpty,
        'private composer',
      );
      // Both users stay on the exact chat route for ten reciprocal messages.
      // The host releases each ready barrier before either UI send and records
      // each receive acknowledgement after the peer text is visible, providing
      // twenty conservative timing bounds on one monotonic clock.
      final Set<String> ownPrivateTexts = <String>{};
      final Set<String> peerPrivateTexts = <String>{};
      for (int index = 0; index < 10; index++) {
        final privateText = config.message(role, 'private-$index');
        final peerPrivate = config.message(config.peerRole, 'private-$index');
        ownPrivateTexts.add(privateText);
        peerPrivateTexts.add(peerPrivate);
        final composer = find.byType(TextField).hitTestable();
        final sendButton = find
            .byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '发送消息',
            )
            .hitTestable();
        final privateWatch = Stopwatch()..start();
        void tracePrivate(String marker) {
          // Only fixed markers and allowlisted facts; diagnostics must never
          // replace the original failure, including during route disposal.
          try {
            final fields = composer.evaluate().toList();
            final buttons = sendButton.evaluate().toList();
            final field = fields.length == 1
                ? fields.single.widget as TextField
                : null;
            final button = buttons.length == 1
                ? buttons.single.widget as IconButton
                : null;
            debugPrint(
              'DUAL_PRIVATE_TRACE::$role::$marker::index=$index::'
              'elapsedMs=${privateWatch.elapsedMilliseconds}::'
              'lifecycle=${binding.lifecycleState?.name}::'
              'routeCurrent=${fields.length == 1 && ModalRoute.of(fields.single)?.isCurrent == true}::'
              'identityMatches=${dependencies.sessionManager.session?.userId == config.session.userId}::'
              'composerEnabled=${field != null && field.enabled != false}::'
              'inputMatchesExpected=${field?.controller?.text == privateText}::'
              'inputEmpty=${field?.controller?.text.isEmpty == true}::'
              'sendEnabled=${button?.onPressed != null}::'
              'ownVisible=${find.text(privateText, findRichText: false).hitTestable().evaluate().any((element) => element.widget is Text)}::'
              'peerVisible=${find.text(peerPrivate).hitTestable().evaluate().length == 1}',
            );
          } catch (_) {
            // Never print exception text or sensitive UI values.
          }
        }

        final observer = _PrivateLifecycleObserver(
          () => tracePrivate('lifecycle_changed'),
        );
        binding.addObserver(observer);
        var roundCompleted = false;
        try {
          await _until(
            tester,
            () =>
                composer.evaluate().length == 1 &&
                tester.widget<TextField>(composer).enabled != false &&
                tester.widget<TextField>(composer).controller!.text.isEmpty &&
                sendButton.evaluate().length == 1 &&
                tester.widget<IconButton>(sendButton).onPressed != null,
            'private composer ready $index',
          );
          // Sending temporarily disables the field and closes its native input
          // connection. A real user taps it again; enterText alone may retain
          // the test binding's cached EditableText and never reconnect it.
          await _tap(tester, composer);
          await _until(
            tester,
            () => tester
                .widget<EditableText>(
                  find.descendant(
                    of: composer,
                    matching: find.byType(EditableText),
                  ),
                )
                .focusNode
                .hasFocus,
            'private input focus $index',
          );
          await tester.enterText(composer, privateText);
          expect(
            tester.widget<TextField>(composer).controller!.text,
            privateText,
          );
          await _barrier(tester, relay, config, 'private-ready-$index');
          tracePrivate('ready_barrier_return');
          expect(
            tester.widget<TextField>(composer).controller!.text,
            privateText,
          );
          expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
          tracePrivate('send_tap_wait');
          await _tap(
            tester,
            sendButton,
            diagnostic: (before) =>
                tracePrivate(before ? 'before_send_tap' : 'after_send_tap'),
          );
          tracePrivate('send_wait');
          await _until(
            tester,
            () =>
                find
                    .text(privateText, findRichText: false)
                    .hitTestable()
                    .evaluate()
                    .any((element) => element.widget is Text) &&
                tester.widget<TextField>(composer).controller!.text.isEmpty &&
                tester.widget<IconButton>(sendButton).onPressed != null,
            'private UI send $index',
            onTimeout: () => tracePrivate('send_timeout'),
          );
          tracePrivate('send_success');
          tracePrivate('receive_wait');
          await _until(
            tester,
            () => find.text(peerPrivate).hitTestable().evaluate().length == 1,
            'private automatic receive without navigation $index',
            timeout: const Duration(seconds: 5),
            onTimeout: () => tracePrivate('receive_timeout'),
          );
          tracePrivate('receive_success');
          expect(find.text(peerPrivate).hitTestable(), findsOneWidget);
          await _barrier(tester, relay, config, 'private-received-$index');
          tracePrivate('received_barrier_return');
          roundCompleted = true;
        } finally {
          if (!roundCompleted) tracePrivate('private_failed');
          binding.removeObserver(observer);
          privateWatch.stop();
        }
      }
      final conversation =
          (await dependencies.messageRepository.fetchConversations())
              .singleWhere((c) => c.targetUserId == config.peerUserId);
      final privateHistory = await dependencies.messageRepository
          .fetchPrivateMessages(conversation);
      for (final (sender, texts) in <(int, Set<String>)>[
        (config.session.userId, ownPrivateTexts),
        (config.peerUserId, peerPrivateTexts),
      ]) {
        for (final text in texts) {
          expect(
            privateHistory.where(
              (ChatMessage message) =>
                  message.senderUserId == sender && message.content == text,
            ),
            hasLength(1),
          );
        }
      }

      final post = await dependencies.dynamicRepository.fetchPost(
        config.peerPostId,
      );
      expect(post.author.userId == config.peerUserId && !post.isLiked, isTrue);
      navigation.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => DynamicDetailPage(postId: config.peerPostId),
        ),
      );
      await _tap(tester, find.byIcon(Icons.favorite_border_rounded));
      await _until(
        tester,
        () => find.byIcon(Icons.favorite_rounded).evaluate().isNotEmpty,
        'dynamic UI like',
      );
      final liked = await dependencies.dynamicRepository.fetchPost(
        config.peerPostId,
      );
      expect(liked.isLiked && liked.likeCount == post.likeCount + 1, isTrue);
      await _barrier(tester, relay, config, 'complete');
      binding.reportData = <String, dynamic>{
        'role': role,
        'runId': config.runId,
        'flutterSha': config.flutterSha,
        'backendSha': config.backendSha,
        'firstPartyUi': 'PASS',
        'publicReceive': 'automatic_first_party_within_5s_after_both_sends',
        'publicReceiveObservedAfterBarrierMs':
            publicReceiveWatch.elapsedMilliseconds,
        'roomReentry': 'separate_persistence_recovery',
        'ordinaryMicApprovalRounds': 2,
        'ordinaryMemberPromoted': false,
        'giftSettlement':
            'ORDINARY_TENTHS_CHAIR_CASH_AND_TWO_15_PERCENT_SHARES',
        'giftLedgerEvidence': 'host_exact_per_transfer_and_carry_required',
        'publicVisibleBeforeReentry': visibleBeforeReentry,
        'privateReceive': 'automatic_http_sync_no_navigation',
        'privateSentCount': ownPrivateTexts.length,
        'privateReceivedCount': peerPrivateTexts.length,
        'privateLatencyEvidence': 'host_monotonic_upper_bounds_required',
        'releaseAcceptance': 'PARTIAL_FIRST_PARTY_ONLY',
        'rtcAudio': 'DISABLED_NOT_TESTED',
        'imRealtime': 'DISABLED_NOT_TESTED',
      };
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _until(
  WidgetTester tester,
  bool Function() condition,
  String stage, {
  Duration timeout = const Duration(seconds: 30),
  VoidCallback? onTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      onTimeout?.call();
      throw TestFailure('Timed out: $stage');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Checks the exact ordinary-member REQUEST, never a manager INVITE or a
/// legacy accepted projection. Kept testable without a device or backend.
void expectDualApprovedRequest(
  MicAccessRequest request, {
  required String roomId,
  required int applicant,
  required int owner,
  required int seat,
}) {
  expect(seat, inInclusiveRange(2, 9));
  expect(request.id, isNotEmpty);
  expect(request.roomId, roomId);
  expect(request.type, MicRequestType.request);
  expect(request.member.userId, applicant);
  expect(request.member.role, RoomRole.listener);
  expect(request.requestedByUserId, applicant);
  expect(request.subjectUserId, applicant);
  expect(request.seatNumber, seat);
  expect(request.status, MicRequestStatus.approved);
  expect(request.resolvedByUserId, owner);
  expect(request.assignedSeatNumber, seat);
  expect(request.resolvedAt, isNotNull);
}

Future<T> _authorityUntil<T>(
  WidgetTester tester,
  Future<T> Function() read,
  bool Function(T) ready,
  String description,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  do {
    final value = await read();
    if (ready(value)) return value;
    await tester.pump(const Duration(milliseconds: 250));
  } while (DateTime.now().isBefore(deadline));
  throw TestFailure('Authority timeout: $description');
}

Future<void> _expectPairAuthority(
  AppDependencies dependencies,
  DualConfig config, {
  required bool seated,
}) async {
  final projection =
      await (dependencies.roomRepository as RoomAuthorityRepository)
          .fetchRoomAuthority(
            roomId: config.roomId,
            currentUserId: config.session.userId,
          );
  expect(projection.viewerUserId, config.session.userId);
  expect(projection.memberActive, isTrue);
  expect(projection.snapshot.roomId, config.roomId);
  expect(
    projection.snapshot.ownerId,
    config.role == 'A' ? config.session.userId : config.peerUserId,
  );
  expect(
    projection.snapshot.role,
    config.role == 'A' ? RoomRole.owner : RoomRole.listener,
  );
  final pair = {config.session.userId, config.peerUserId};
  final occupied = projection.snapshot.seats
      .where((seat) => pair.contains(seat.userId) && seat.isOccupied)
      .toList();
  expect(occupied, hasLength(seated ? 2 : 0));
  if (seated) {
    final owner = config.role == 'A'
        ? config.session.userId
        : config.peerUserId;
    expect(occupied.singleWhere((seat) => seat.userId == owner).number, 1);
    expect(occupied.singleWhere((seat) => seat.userId != owner).number, 2);
  }
}

Future<String> _seatPairThroughApproval(
  WidgetTester tester,
  AppDependencies dependencies,
  RoomController controller,
  DualConfig config,
) async {
  final owner = config.role == 'A' ? config.session.userId : config.peerUserId;
  final applicant = config.role == 'B'
      ? config.session.userId
      : config.peerUserId;
  const seat = 2; // Normal seat, never the reserved owner/manager seat 1.
  expect(controller.isOnMic, isFalse);
  expect(
    controller.role,
    config.role == 'A' ? RoomRole.owner : RoomRole.listener,
  );
  expect(
    controller.micCoordinationMode,
    config.role == 'A'
        ? MicCoordinationMode.direct
        : MicCoordinationMode.approval,
  );
  Future<List<MicAccessRequest>> queue() =>
      dependencies.roomOperationsRepository.fetchMicRequests(config.roomId);
  final previous = config.role == 'B'
      ? (await queue()).map((r) => r.id).toSet()
      : <String>{};
  await _tap(tester, find.text('上麦'));
  if (config.role == 'B') {
    expect(find.byKey(const Key('approval-mic-seat-1')), findsNothing);
    await _tap(tester, find.byKey(const Key('approval-mic-seat-$seat')));
  } else {
    await _tap(tester, find.text('1 号麦'));
    await _until(tester, () => controller.isOnMic, 'owner seat');
  }
  bool ownRequest(MicAccessRequest r) =>
      r.roomId == config.roomId &&
      r.type == MicRequestType.request &&
      r.subjectUserId == applicant &&
      r.requestedByUserId == applicant &&
      r.seatNumber == seat &&
      (config.role == 'A' ? r.isPending : !previous.contains(r.id));
  final requests = await _authorityUntil(
    tester,
    queue,
    (rows) => rows.any(ownRequest),
    'new ordinary request',
  );
  final request = requests.where(ownRequest).single;
  expect(request.member.role, RoomRole.listener);
  if (config.role == 'A') {
    expect(request.status, MicRequestStatus.pending);
    await _tap(tester, find.text('更多'));
    await _tap(tester, find.text('互动玩法'));
    await _tap(tester, find.text('房管'));
    await _until(
      tester,
      () => find.byType(RoomManagementPage).evaluate().isNotEmpty,
      'owner management page',
    );
    await _tap(tester, find.textContaining('上麦申请'));
    final row = find.ancestor(
      of: find.text(request.member.name),
      matching: find.byType(ListTile),
    );
    await _tap(tester, find.descendant(of: row, matching: find.text('同意')));
  }
  final approved = await _authorityUntil(
    tester,
    queue,
    (rows) => rows.any(
      (r) => r.id == request.id && r.status == MicRequestStatus.approved,
    ),
    'owner-approved exact request',
  );
  expectDualApprovedRequest(
    approved.singleWhere((r) => r.id == request.id),
    roomId: config.roomId,
    applicant: applicant,
    owner: owner,
    seat: seat,
  );
  if (config.role == 'A') {
    await _tap(tester, find.byTooltip('返回房间'));
    await _until(
      tester,
      () => find.byType(RoomManagementPage).evaluate().isEmpty,
      'return from management',
    );
  }
  await _until(
    tester,
    () =>
        controller.isOnMic &&
        controller.seats.any(
          (s) =>
              s.number == (config.role == 'A' ? 1 : seat) &&
              s.userId == config.session.userId,
        ),
    'authoritative approved mic placement',
    timeout: const Duration(seconds: 5),
    onTimeout: () => debugPrint(
      'DUAL_MIC_STATE::${config.role}::placement_timeout::'
      'lifecycle=${WidgetsBinding.instance.lifecycleState?.name ?? 'unknown'}::'
      'status=${controller.status.name}::role=${controller.role.name}::'
      'identityCurrent=${controller.isEntryIdentityCurrent}::'
      'requestPending=${controller.micRequestPending}::'
      'queueLoading=${controller.micQueueLoading}::'
      'snapshotOnly=${controller.isSnapshotOnly}::'
      'syncDegraded=${controller.realtimeDegraded}::'
      'onMic=${controller.isOnMic}::'
      'ownOccupiedSeatCount=${controller.seats.where((s) => s.userId == config.session.userId && s.isOccupied).length}',
    ),
  );
  await _expectPairAuthority(dependencies, config, seated: true);
  return request.id;
}

// Prices are whole platform coins, 1 coin = 10 fen. Aggregate quantity before
// flooring each beneficiary. No double arithmetic for platform-coin amounts.
void expectDualGiftIncome(
  GiftReceipt receipt, {
  required int price,
  int quantity = 1,
  required bool cashEligible,
}) {
  expect(price, greaterThan(0));
  expect(quantity, inInclusiveRange(1, 999));
  final valueFen = BigInt.from(price) * BigInt.from(quantity) * BigInt.from(10);
  expect(receipt.quantity, quantity);
  expect(receipt.creatorIncomeMinor, isNotNull);
  expect(BigInt.from(receipt.creatorIncomeMinor!), valueFen ~/ BigInt.two);
  expect(
    receipt.creatorIncomeCurrency,
    cashEligible ? 'CASH_CNY' : 'GIFT_COIN_TENTH',
  );
}

BigInt _cashFen(double value) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(value.toString());
  if (match == null) throw TestFailure('Cash projection is not exact cents');
  return BigInt.parse(match.group(1)!) * BigInt.from(100) +
      BigInt.parse((match.group(2) ?? '').padRight(2, '0'));
}

void expectDualGiftSettlement({
  required WalletSummary before,
  required WalletSummary after,
  required int price,
  required bool chair,
}) {
  expect(price, greaterThan(0));
  expect(before.coinPrecision, isNotNull);
  expect(after.coinPrecision, isNotNull);
  expect(
    before.incomeCapability.role,
    chair ? IncomeRole.guildChair : IncomeRole.ordinary,
  );
  expect(after.incomeCapability.role, before.incomeCapability.role);
  final valueFen = BigInt.from(price) * BigInt.from(10);
  final receiverFen = valueFen ~/ BigInt.two;
  final chairFen = valueFen * BigInt.from(15) ~/ BigInt.from(100);
  expect(
    after.giftCoins!.tenths - before.giftCoins!.tenths,
    -valueFen + (chair ? BigInt.zero : receiverFen),
  );
  expect(
    _cashFen(after.cashBalance) - _cashFen(before.cashBalance),
    chair ? receiverFen + chairFen * BigInt.two : BigInt.zero,
  );
  expect(
    after.coinPrecision!.frozen.tenths,
    before.coinPrecision!.frozen.tenths,
  );
  expect(_cashFen(after.frozenBalance), _cashFen(before.frozenBalance));
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  void Function(bool before)? diagnostic,
}) async {
  await _until(tester, () => finder.evaluate().isNotEmpty, 'UI control');
  // A modal seat picker repeats the labels on the room underneath it. Only
  // the unobscured target is actionable; never scroll/click a covered match.
  if (finder.hitTestable().evaluate().isEmpty &&
      finder.evaluate().length == 1) {
    await tester.ensureVisible(finder);
  }
  await tester.pump(const Duration(milliseconds: 300));
  await _until(
    tester,
    () => finder.hitTestable().evaluate().length == 1,
    'one unobscured UI control',
  );
  diagnostic?.call(true);
  await tester.tap(finder.hitTestable());
  diagnostic?.call(false);
  await tester.pump(const Duration(milliseconds: 300));
}

class _PrivateLifecycleObserver with WidgetsBindingObserver {
  _PrivateLifecycleObserver(this.onChange);

  final VoidCallback onChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChange();
}

Future<void> _barrier(
  WidgetTester tester,
  DualRelay relay,
  DualConfig config,
  String phase,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final reply = await relay.request('/dual/barrier', {
      'runId': config.runId,
      'role': config.role,
      'phase': phase,
    });
    if (relay.released(reply, config, phase)) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  throw TestFailure('Dual barrier timeout: $phase');
}
