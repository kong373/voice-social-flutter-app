import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_repository.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
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
      addTearDown(dependencies.dispose);
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
      expect(controller.micCoordinationMode, MicCoordinationMode.direct);
      await _barrier(tester, relay, config, 'joined');
      final members = await dependencies.roomOperationsRepository
          .fetchOnlineMembers(roomId: config.roomId, page: 1);
      expect(
        members.items.any((m) => m.userId == config.session.userId),
        isTrue,
      );
      expect(members.items.any((m) => m.userId == config.peerUserId), isTrue);
      await _tap(tester, find.text('上麦'));
      await _tap(tester, find.text(role == 'A' ? '1 号麦' : '2 号麦'));
      await _until(tester, () => controller.isOnMic, 'self mic entry');
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
      await tester.enterText(
        find.byKey(const Key('video-room-composer')),
        publicText,
      );
      // Focusing changes the room dock into the composer. Wait for that
      // visible control and use its real callback, rather than submitting
      // through a test IME connection that may have just been replaced.
      await _until(
        tester,
        () => find.byTooltip('发送').hitTestable().evaluate().length == 1,
        'public send button',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('video-room-composer')))
            .controller!
            .text,
        publicText,
      );
      await _tap(tester, find.byTooltip('发送'));
      FocusManager.instance.primaryFocus?.unfocus();
      // Unfocus unregisters the test input connection on a live device.
      // Do not call TestTextInput.hide() after that connection has closed.
      await tester.pump(const Duration(milliseconds: 300));
      await _until(
        tester,
        () => controller.messages.any((m) => m.content == publicText),
        'own public send',
      );
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
      await _barrier(tester, relay, config, 'manual_room_reentry');
      await _tap(tester, find.text('上麦'));
      await _tap(tester, find.text(role == 'A' ? '1 号麦' : '2 号麦'));
      await _until(tester, () => controller.isOnMic, 'gift self mic reentry');
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
              .singleWhere((g) => g.enabled && g.name == 'Star');
      // Serialize the two gift transfers while both devices remain in the room,
      // so each sender's exact wallet delta cannot race the reciprocal transfer.
      for (final sender in ['A', 'B']) {
        if (role == sender) {
          final before = await dependencies.commerceRepository
              .fetchWalletSummary();
          expect(
            before.giftCoinBalance != null &&
                before.giftCoinBalance! >= star.price,
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
          await _tap(tester, find.text('Star'));
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
          expect(receipt.transferId?.isNotEmpty, isTrue);
          expect(receipt.providerInvocation, isFalse);
          final after = await dependencies.commerceRepository
              .fetchWalletSummary();
          expect(after.giftCoinBalance, before.giftCoinBalance! - star.price);
          expect(receipt.remainingBalance, after.giftCoinBalance);
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
      final privateText = config.message(role, 'private');
      await tester.enterText(find.byType(TextField).hitTestable(), privateText);
      await _tap(tester, find.byTooltip('发送消息'));
      await _until(
        tester,
        () => find.text(privateText).evaluate().isNotEmpty,
        'private UI send',
      );
      await _barrier(tester, relay, config, 'private-sent');
      // Both users remain on this exact route. Navigation/manual refresh
      // cannot substitute for automatic first-party receive recovery.
      final peerPrivate = config.message(config.peerRole, 'private');
      await _until(
        tester,
        () => find.text(peerPrivate).evaluate().isNotEmpty,
        'private automatic receive without navigation',
        timeout: const Duration(seconds: 5),
      );
      final conversation =
          (await dependencies.messageRepository.fetchConversations())
              .singleWhere((c) => c.targetUserId == config.peerUserId);
      final privateHistory = await dependencies.messageRepository
          .fetchPrivateMessages(conversation);
      expect(
        privateHistory.any(
          (ChatMessage m) =>
              m.senderUserId == config.peerUserId && m.content == peerPrivate,
        ),
        isTrue,
      );

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
        'publicVisibleBeforeReentry': visibleBeforeReentry,
        'privateReceive': 'automatic_http_sync_no_navigation',
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
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline))
      throw TestFailure('Timed out: $stage');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
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
  await tester.tap(finder.hitTestable());
  await tester.pump(const Duration(milliseconds: 300));
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
