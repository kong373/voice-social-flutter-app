import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/app/page_manifest.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/debug/qa_console/qa_page_catalog.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/features/commerce/data/backend_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/community/data/backend_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/message/data/backend_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/data/backend_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/pk/data/backend_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_audio_service.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

const String _roomId = '11111111-1111-4111-8111-111111111111';
const String _targetRoomId = '22222222-2222-4222-8222-222222222222';
const String _invitationId = '33333333-3333-4333-8333-333333333333';
const String _battleId = '44444444-4444-4444-8444-444444444444';
const String _giftId = '55555555-5555-4555-8555-555555555555';
const String _transferId = '66666666-6666-4666-8666-666666666666';

void main() {
  test(
    'live dependency graph wires first-party adapters and closes vendors',
    () async {
      final _TestServer server = await _TestServer.start(
        (_Request request) => _Reply.ok(<String, Object?>{}),
      );
      addTearDown(server.close);

      final AppEnvironment environment = AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: server.baseUrl,
        clientType: 'Android',
        clientInnerVersion: '6',
        oauthClientId: 'public-client',
        realtimeEndpoint: '',
        deploymentEnvironment: DeploymentEnvironment.development,
        allowInsecureHttp: true,
      );
      final AppDependencies dependencies = AppDependencies.forTestEnvironment(
        environment: environment,
      );

      expect(
        dependencies.discoveryRepository.runtimeType.toString(),
        contains('BackendDiscoveryRepository'),
      );
      expect(
        dependencies.communityRepository.runtimeType.toString(),
        contains('BackendCommunityRepository'),
      );
      expect(dependencies.commerceRepository, isA<BackendCommerceRepository>());
      expect(dependencies.messageRepository, isA<BackendMessageRepository>());
      expect(dependencies.roomRepository, isA<BackendRoomRepository>());
      expect(
        dependencies.roomOperationsRepository,
        isA<BackendRoomOperationsRepository>(),
      );
      expect(dependencies.roomPkRepository, isA<BackendRoomPkRepository>());
      expect(dependencies.environment.oauthClientSecret, isEmpty);
      expect(dependencies.environment.canReadDevelopmentSmsOutbox, isFalse);
      expect(
        dependencies.commerceRepository.supportsPaymentChannelInvocation,
        isFalse,
      );
      expect(
        dependencies.roomPkRepository.supportsRealtimeInvitations,
        isFalse,
      );
      expect(dependencies.rtcAdapter, isA<SnapshotOnlyRtcAdapter>());
      expect(
        dependencies.realtimeGateway,
        isA<SnapshotOnlyRoomRealtimeGateway>(),
      );
      expect(dependencies.roomAudioService, isA<UnavailableRoomAudioService>());
      expect(
        (await dependencies.roomAudioService.inspect()).configured,
        isFalse,
      );
      await expectLater(
        dependencies.rtcAdapter.setLocalAudioEnabled(true),
        throwsStateError,
      );
      final RechargeOrder order = RechargeOrder(
        orderNo: 'order-vendor-blocked',
        account: 'account',
        product: const RechargeProduct(
          id: 'product-1',
          giftCoins: 10,
          priceCny: 1,
          label: '商品',
        ),
        channel: PaymentChannelType.wechat,
        state: RechargeOrderState.confirming,
        createdAt: DateTime.utc(2030, 8, 25),
        message: '',
      );
      await expectLater(
        dependencies.commerceCatalogRepository.invokePayment(order),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
    },
  );

  test(
    'withdrawal, refund submit/result/retry preserve first-party authority',
    () async {
      int refundApplyCalls = 0;
      int refundRepeatCalls = 0;
      final _TestServer server = await _TestServer.start((_Request request) {
        switch (request.path) {
          case '/app-mini-api/mini/v1/withdrawal/accounts':
            return _Reply.ok(<String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'payoutAccountId': 'payout-1',
                  'accountType': 'BANK_CARD',
                  'accountMasked': '****1234',
                  'holderNameMasked': '晚*',
                  'status': 'VERIFIED',
                  'selectable': true,
                },
              ],
              'total': 1,
              'selectedPayoutAccountId': 'payout-1',
              'selectionRequired': false,
              'providerInvocation': false,
            });
          case '/app-mini-api/mini/v1/withdrawal/apply':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'amountMinor': 1234,
              'payoutAccountId': 'payout-1',
            });
            expect(request.requestId, isNotEmpty);
            return _Reply.ok(<String, Object?>{
              'withdrawalId': 'withdrawal-1',
              'payoutAccountId': 'payout-1',
              'amountMinor': 1234,
              'feeMinor': 25,
              'netAmountMinor': 1209,
              'status': 'SUBMITTED',
              'payoutStatus': 'MANUAL_REVIEW_PENDING',
              'providerInvocation': false,
              'holderNameMasked': '晚*',
              'accountMasked': '****1234',
              'submittedAt': '2030-08-25T00:00:00Z',
              'resultMessage': '',
            });
          case '/app-api/refund/check':
            return _Reply.ok(<String, Object?>{
              'orderNo': 'order-1',
              'eligible': true,
              'reason': 'ELIGIBLE',
              'amountMinor': 100,
              'giftCoinAmount': 10,
              'providerStatus': 'VENDOR_BLOCKED',
            });
          case '/app-api/refund/application':
            refundApplyCalls += 1;
            if (refundApplyCalls == 1) {
              return const _Reply(
                statusCode: 503,
                code: 503,
                message: 'lost',
                data: null,
              );
            }
            return _Reply.ok(_refundMap(status: 'SUBMITTED'));
          case '/app-api/refund/result':
            return _Reply.ok(
              _refundMap(
                status: refundRepeatCalls == 0 ? 'REJECTED' : 'RESUBMITTED',
              ),
            );
          case '/app-api/refund/repeat':
            refundRepeatCalls += 1;
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'refundId': 'refund-1',
              'reason': '重复充值',
            });
            return _Reply.ok(_refundMap(status: 'RESUBMITTED'));
          default:
            return _Reply.ok(<String, Object?>{});
        }
      });
      addTearDown(server.close);
      final BackendCommerceRepository repository = BackendCommerceRepository(
        apiClient: server.client,
      );

      final PayoutAccountSelection accounts = await repository
          .fetchPayoutAccounts();
      expect(accounts.selectedPayoutAccountId, 'payout-1');
      final WithdrawalRecord withdrawal = await repository.applyWithdrawal(
        amount: 12.34,
        payoutAccountId: 'payout-1',
      );
      expect(withdrawal.id, 'withdrawal-1');
      expect(withdrawal.receivedAmount, 12.09);

      final RefundRequest refundRequest = const RefundRequest(
        account: 'order-1',
        realName: '晚星',
        age: 25,
        amount: 1,
        reason: '重复充值',
        receivingAccount: 'masked',
        receivingName: '晚*',
        guardianName: '',
        guardianPhone: '',
      );
      await expectLater(
        repository.submitRefund(refundRequest),
        throwsA(isA<ApiException>()),
      );
      final RefundApplication submitted = await repository.submitRefund(
        refundRequest,
      );
      expect(submitted.id, 'refund-1');
      expect(submitted.status, RefundStatus.reviewing);
      final RefundApplication rejected = await repository.fetchRefundResult(
        'refund-1',
      );
      expect(rejected.status, RefundStatus.rejected);
      final RefundApplication retried = await repository.resubmitRefund(
        'refund-1',
      );
      expect(retried.status, RefundStatus.resubmitted);
      expect(refundApplyCalls, 2);
      expect(refundRepeatCalls, 1);
      final List<_Request> refundWrites = server.requests
          .where((_Request item) => item.path == '/app-api/refund/application')
          .toList();
      expect(refundWrites, hasLength(2));
      expect(refundWrites[0].requestId, refundWrites[1].requestId);
    },
  );

  test(
    'room gift send and receipt recovery retain request authority',
    () async {
      int sendCalls = 0;
      final _TestServer server = await _TestServer.start((_Request request) {
        if (request.path == '/app-room-api/room/com/v1/sendGift') {
          sendCalls += 1;
          if (sendCalls == 1) {
            return const _Reply(
              statusCode: 503,
              code: 503,
              message: 'lost',
              data: null,
            );
          }
          return _Reply.ok(_giftMap(requestId: request.requestId));
        }
        if (request.path == '/app-room-api/room/com/v1/giftReceipt') {
          expect(request.method, 'GET');
          expect(request.query['transferId'], _transferId);
          return _Reply.ok(_giftMap(requestId: request.query['requestId']));
        }
        return _Reply.ok(<String, Object?>{});
      });
      addTearDown(server.close);
      final BackendRoomRepository repository = BackendRoomRepository(
        apiClient: server.client,
      );
      final Future<GiftReceipt> first = repository.sendGift(
        roomId: _roomId,
        giftId: _giftId,
        receiverUserIds: const <int>[20002],
        quantity: 1,
        giftFrom: 0,
        requestId: 'gift-retry-1',
      );
      await expectLater(first, throwsA(isA<ApiException>()));
      final GiftReceipt recovered = await repository.sendGift(
        roomId: _roomId,
        giftId: _giftId,
        receiverUserIds: const <int>[20002],
        quantity: 1,
        giftFrom: 0,
        requestId: 'gift-retry-1',
      );
      expect(recovered.success, isTrue);
      expect(recovered.transferId, _transferId);
      expect(sendCalls, 2);
      expect(server.requests[0].requestId, server.requests[1].requestId);
      final GiftReceipt receipt = await repository.fetchGiftReceipt(
        transferId: _transferId,
        participantUserId: 10001,
        senderUserId: 10001,
        receiverUserId: 20002,
        currentUserId: 10001,
      );
      expect(receipt.receiverUserId, 20002);
      expect(
        server.requests.last.path,
        '/app-room-api/room/com/v1/giftReceipt',
      );
      await expectLater(
        repository.fetchGiftReceipt(transferId: _transferId),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
    },
  );

  test(
    'room moderation and seats write exact authority with idempotency',
    () async {
      final _TestServer server = await _TestServer.start((_Request request) {
        switch (request.path) {
          case '/app-api/rooms/getRoomOnlinePersonnel':
            return _Reply.ok(<String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'userId': 20002,
                  'nickName': '听众',
                  'seatNumber': 2,
                  'userRoomRole': 2,
                  'presence': 'ON_MIC',
                },
              ],
              'records': <Object?>[
                <String, Object?>{
                  'userId': 20002,
                  'nickName': '听众',
                  'seatNumber': 2,
                  'userRoomRole': 2,
                  'presence': 'ON_MIC',
                },
              ],
              'current': 1,
              'pageNum': 1,
              'pageSize': 50,
              'size': 50,
              'total': 1,
              'pages': 1,
            });
          case '/app-api/roomUsers/setMuted':
            expect(request.body, <String, Object?>{
              'roomId': 'room-1',
              'targetUserId': 20002,
              'muted': true,
            });
            return _Reply.ok(<String, Object?>{
              'roomId': 'room-1',
              'userId': 20002,
              'muted': true,
            });
          case '/app-api/roomUsers/setRole':
            expect(request.body, <String, Object?>{
              'roomId': 'room-1',
              'targetUserId': 20002,
              'role': 'MANAGER',
            });
            return _Reply.ok(<String, Object?>{
              'roomId': 'room-1',
              'userId': 20002,
              'role': 'MANAGER',
            });
          case '/app-api/room/com/kickout':
            expect(request.body, <String, Object?>{
              'roomId': 'room-1',
              'targetUserId': 20002,
              'ban': true,
            });
            return _Reply.ok(<String, Object?>{
              'roomId': 'room-1',
              'userId': 20002,
              'kicked': true,
            });
          case '/app-api/micBase/closedMike':
            expect(request.body, <String, Object?>{
              'roomId': 'room-1',
              'userId': 20002,
              'seatNumber': 2,
              'muted': true,
            });
            return _Reply.ok(<String, Object?>{
              'roomId': 'room-1',
              'userId': 20002,
              'seatNumber': 2,
              'muted': true,
            });
          case '/app-api/micBase/openMike':
            expect(request.body, <String, Object?>{
              'roomId': 'room-1',
              'userId': 20002,
              'seatNumber': 2,
              'muted': false,
            });
            return _Reply.ok(<String, Object?>{
              'roomId': 'room-1',
              'userId': 20002,
              'seatNumber': 2,
              'muted': false,
            });
          case '/app-api/micBase/lockMike':
            return _Reply.ok(<String, Object?>{
              'roomId': 'room-1',
              'seatNumber': 3,
              'locked': true,
            });
          case '/app-api/micBase/unlockMike':
            return _Reply.ok(<String, Object?>{
              'roomId': 'room-1',
              'seatNumber': 3,
              'locked': false,
            });
          default:
            return _Reply.ok(<String, Object?>{});
        }
      });
      addTearDown(server.close);
      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);
      expect(repository.micCoordinationMode, MicCoordinationMode.direct);
      await repository.fetchOnlineMembers(
        roomId: 'room-1',
        page: 1,
        pageSize: 50,
      );
      await repository.setUserMuted(
        roomId: 'room-1',
        userId: 20002,
        muted: true,
      );
      await repository.setUserRole(
        roomId: 'room-1',
        userId: 20002,
        manager: true,
      );
      await repository.kickUser(roomId: 'room-1', userId: 20002);
      await repository.setSeatMuted(
        roomId: 'room-1',
        backendMicIndex: 2,
        muted: true,
      );
      await repository.setSeatMuted(
        roomId: 'room-1',
        backendMicIndex: 2,
        muted: false,
      );
      await repository.setSeatLocked(
        roomId: 'room-1',
        backendMicIndex: 3,
        locked: true,
      );
      await repository.setSeatLocked(
        roomId: 'room-1',
        backendMicIndex: 3,
        locked: false,
      );
      for (final _Request write in server.requests.where(
        (_Request item) =>
            item.method == 'POST' &&
            item.path != '/app-api/rooms/getRoomOnlinePersonnel',
      )) {
        expect(write.requestId, isNotEmpty, reason: write.path);
      }
      await expectLater(
        repository.submitMicRequest(
          roomId: 'room-1',
          userId: 20002,
          seatNumber: 2,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.configuration,
          ),
        ),
      );
    },
  );

  test(
    'PK invite, accept, refresh, end and recovery use authoritative projections',
    () async {
      final _TestServer server = await _TestServer.start((_Request request) {
        switch (request.path) {
          case '/app-api/activityPk/inviteRoomPk':
            expect(request.body, <String, Object?>{
              'roomId': _roomId,
              'targetRoomId': _targetRoomId,
              'punishmentTheme': '主题',
              'durationMinutes': 5,
            });
            return _Reply.ok(_invitationMap());
          case '/app-api/activityPk/acceptRoomPkInvitation':
            return _Reply.ok(_battleMap());
          case '/app-api/activityPk/queryRoomPkProcess':
            return _Reply.ok(_battleMap());
          case '/app-api/activityPk/endRoomPk':
            expect(request.body, <String, Object?>{'battleId': _battleId});
            return _Reply.ok(_battleMap(status: 'COMPLETED'));
          default:
            return _Reply.ok(<String, Object?>{});
        }
      });
      addTearDown(server.close);
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );
      const RoomPkOpponent opponent = RoomPkOpponent(
        roomId: _targetRoomId,
        roomCode: 'R222',
        roomName: '目标房',
      );
      final RoomPkInvitation invitation = await repository.sendInvitation(
        roomId: _roomId,
        inviterUserId: 10001,
        opponent: opponent,
        punishmentTheme: '主题',
        durationMinutes: 5,
      );
      expect(invitation.status, RoomPkInvitationStatus.pending);
      final RoomPkBattle battle = await repository.acceptInvitation(invitation);
      expect(battle.id, _battleId);
      expect(
        (await repository.refreshInvitation(invitation)).id,
        _invitationId,
      );
      expect(
        (await repository.refreshBattle(
          roomId: _roomId,
          battleId: _battleId,
        )).id,
        _battleId,
      );
      final RoomPkBattle ended = await repository.end(
        roomId: _roomId,
        battleId: _battleId,
      );
      expect(ended.stage, RoomPkBattleStage.completed);
      expect(repository.supportsRealtimeInvitations, isFalse);
      expect(
        server.requests
            .where((_Request request) => request.method == 'POST')
            .every((_Request request) => request.requestId.isNotEmpty),
        isTrue,
      );
    },
  );

  test(
    'private message and notification mutations sync first-party state only',
    () async {
      final _TestServer server = await _TestServer.start((_Request request) {
        switch (request.path) {
          case '/app-api/user/imMessage/queryChat':
            return _Reply.ok(<String, Object?>{
              'conversationId': 'conversation-20002',
              'targetUserId': 20002,
              'imStatus': 'VENDOR_BLOCKED',
              'providerInvocation': false,
              'list': <Object?>[
                <String, Object?>{
                  'id': 'message-1',
                  'senderUserId': 10001,
                  'direction': 'OUTGOING',
                  'content': '你好',
                  'createTime': '2030-08-25T00:00:00Z',
                  'storageStatus': 'FIRST_PARTY_STORED',
                  'deliveryStatus': 'VENDOR_BLOCKED',
                  'conversationId': 'conversation-20002',
                },
              ],
              'hasMore': false,
              'nextCursor': '',
              'unreadCount': 0,
            });
          case '/app-mini-api/mini/v1/message/read':
            return _Reply.ok(<String, Object?>{
              'targetUserId': 20002,
              'markedRead': 1,
              'unreadCount': 0,
              'conversationId': 'conversation-20002',
            });
          case '/app-mini-api/mini/v1/message/send':
            expect(request.body, <String, Object?>{
              'targetUserId': 20002,
              'content': '你好',
              'messageType': 'TEXT',
            });
            return _Reply.ok(<String, Object?>{
              'message': <String, Object?>{
                'id': 'message-2',
                'conversationId': 'conversation-20002',
                'receiverUserId': 20002,
                'senderUserId': 10001,
                'direction': 'OUTGOING',
                'content': '你好',
                'messageType': 'TEXT',
                'createTime': '2030-08-25T00:01:00Z',
                'storageStatus': 'FIRST_PARTY_STORED',
                'deliveryStatus': 'VENDOR_BLOCKED',
                'providerInvocation': false,
              },
            });
          case '/app-mini-api/mini/v1/notifications/sync':
            return _Reply.ok(_notificationSyncMap());
          case '/app-mini-api/mini/v1/notifications':
            return _Reply.ok(<String, Object?>{
              'list': <Object?>[
                <String, Object?>{
                  'notificationId': 'notification-1',
                  'category': request.query['category'],
                  'title': '系统通知',
                  'body': '系统内容',
                  'createdAt': '2030-08-25T00:00:00Z',
                  'read': false,
                  'subjectType': 'USER',
                  'subjectId': '20002',
                },
              ],
              'hasMore': false,
              'nextCursor': '',
              'unreadCount': 1,
            });
          case '/app-mini-api/mini/v1/notifications/read':
            expect(request.body, <String, Object?>{
              'notificationId': 'notification-1',
            });
            return _Reply.ok(<String, Object?>{
              'notificationId': 'notification-1',
              'category': 'SYSTEM',
              'title': '系统通知',
              'body': '系统内容',
              'createdAt': '2030-08-25T00:00:00Z',
              'read': true,
              'subjectType': 'USER',
              'subjectId': '20002',
              'pushStatus': 'VENDOR_BLOCKED',
              'providerInvocation': false,
            });
          case '/app-api/dynamic/emptyUserDynamicNotify':
            return _Reply.ok(<String, Object?>{
              'dynamicUnread': 0,
              'notificationUnread': 0,
              'messageUnread': 0,
              'totalUnread': 0,
              'pushStatus': 'VENDOR_BLOCKED',
              'imStatus': 'VENDOR_BLOCKED',
              'providerInvocation': false,
            });
          default:
            return _Reply.ok(<String, Object?>{});
        }
      });
      addTearDown(server.close);
      final BackendMessageRepository repository = BackendMessageRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );
      final ConversationSummary conversation = ConversationSummary(
        id: 'conversation-20002',
        kind: ConversationKind.privateChat,
        title: '目标用户',
        lastMessage: '',
        updatedAt: DateTime.utc(2030, 8, 25),
        unreadCount: 1,
        targetUserId: 20002,
      );
      final ChatMessage sent = await repository.sendPrivateMessage(
        conversation: conversation,
        content: '你好',
        requestId: 'message-request-1',
      );
      expect(sent.status, ChatMessageStatus.storedPendingDelivery);
      expect(
        (await repository.fetchPrivateMessages(conversation)).single.id,
        'message-1',
      );
      expect(
        (await repository.fetchNotifications(
          NotificationCategory.system,
        )).single.id,
        'notification-1',
      );
      await repository.markNotificationRead('notification-1');
      await repository.clearInteractionNotifications();
      final List<_Request> notificationWrites = server.requests
          .where(
            (_Request request) =>
                request.path.contains('notifications') ||
                request.path.contains('emptyUserDynamicNotify'),
          )
          .toList();
      expect(
        notificationWrites.where(
          (_Request request) => request.method == 'POST',
        ),
        isNotEmpty,
      );
      expect(
        notificationWrites
            .where((_Request request) => request.method == 'POST')
            .every((_Request request) => request.requestId.isNotEmpty),
        isTrue,
      );
    },
  );

  test(
    'task claim sends first-party idempotency and refreshes authoritative center',
    () async {
      final _TestServer server = await _TestServer.start((_Request request) {
        if (request.path == '/app-api/taskSystem/receiveTaskReward') {
          expect(request.body, <String, Object?>{'taskId': 7});
          return _Reply.ok(<String, Object?>{
            'taskId': 7,
            'claimed': true,
            'isReceive': true,
            'status': 2,
            'providerInvocation': false,
          });
        }
        if (request.path == '/app-api/taskSystem/queryTaskRecords') {
          final List<Object?> tasks = <Object?>[_taskMap(claimed: true)];
          return _Reply.ok(<String, Object?>{
            'type': 1,
            'providerInvocation': false,
            'list': tasks,
            'records': tasks,
            'total': 1,
          });
        }
        if (request.path == '/app-api/taskSystem/querySignReward') {
          return _Reply.ok(_signRewardsMap());
        }
        if (request.path == '/app-api/taskSystem/queryTodaySignStatus') {
          return _Reply.ok(<String, Object?>{
            'signedToday': false,
            'isSign': false,
            'continuousDays': 1,
            'consecutiveDays': 1,
            'businessDate': '2030-08-25',
            'providerInvocation': false,
          });
        }
        return _Reply.ok(<String, Object?>{});
      });
      addTearDown(server.close);
      final BackendCommunityRepository repository = BackendCommunityRepository(
        apiClient: server.client,
        routes: const BackendRouteCatalog(),
      );
      final TaskCenterSnapshot center = await repository.claimTask('7');
      expect(center.tasks.single.id, '7');
      expect(center.tasks.single.state, TaskState.claimed);
      final _Request claim = server.requests.firstWhere(
        (_Request request) =>
            request.path == '/app-api/taskSystem/receiveTaskReward',
      );
      expect(claim.requestId, isNotEmpty);
    },
  );

  test('all 69 manifest entries build through the QA wiring catalog', () {
    final AppDependencies dependencies = AppDependencies.mock();
    const QaScenario scenario = QaScenario(
      role: QaRole.registeredUser,
      state: QaPageState.normal,
      mockScenario: QaMockScenario.defaultData,
      network: QaNetworkScenario.normal,
    );
    expect(appPageManifest, hasLength(69));
    expect(qaPageCatalog, hasLength(69));
    expect(
      qaPageCatalog.map((QaPageEntry entry) => entry.id).toList(),
      appPageManifest.map((AppPageDefinition page) => page.id).toList(),
    );
    for (final QaPageEntry entry in qaPageCatalog) {
      expect(
        entry.widgetClass,
        isNot(contains('ScopedPlaceholderPage')),
        reason: entry.id,
      );
      expect(entry.sourcePath, startsWith('lib/'), reason: entry.id);
      expect(
        () => entry.builder(dependencies, scenario),
        returnsNormally,
        reason: entry.id,
      );
    }
  });
}

Map<String, Object?> _refundMap({required String status}) => <String, Object?>{
  'refundId': 'refund-1',
  'orderNo': 'order-1',
  'amountMinor': 100,
  'reason': '重复充值',
  'status': status,
  'resultMessage': status == 'REJECTED' ? '资料不足' : '',
  'submittedAt': '2030-08-25T00:00:00Z',
  'providerStatus': 'VENDOR_BLOCKED',
  'completed': status == 'COMPLETED',
};

Map<String, Object?> _giftMap({String? requestId}) => <String, Object?>{
  'success': true,
  'remainingBalance': 990,
  'transferId': _transferId,
  'requestId': requestId ?? 'gift-retry-1',
  'roomId': _roomId,
  'senderUserId': 10001,
  'receiverUserId': 20002,
  'giftId': _giftId,
  'giftName': '礼物',
  'quantity': 1,
  'source': 'WALLET',
  'status': 'SUCCEEDED',
  'deliveryMode': 'FIRST_PARTY_LEDGER_COMMITTED',
  'providerInvocation': false,
  'unitCostGiftCoin': 10,
  'totalCostGiftCoin': 10,
  'currency': 'GIFT_COIN',
  'creatorIncomeMinor': 10,
  'charmValue': 10,
  'reconciled': true,
  'createdAt': '2030-08-25T00:00:00Z',
};

Map<String, Object?> _invitationMap({String status = 'PENDING'}) =>
    <String, Object?>{
      'roomId': _roomId,
      'targetRoomId': _targetRoomId,
      'invitationId': _invitationId,
      'invitationStatus': status,
      'status': status,
      'createdAt': '2030-08-25T00:00:00Z',
      'expiresAt': '2030-08-25T00:05:00Z',
      'resolvedAt': status == 'PENDING' ? null : '2030-08-25T00:01:00Z',
      'punishmentTheme': '主题',
      'durationMinutes': 5,
      'providerInvocation': false,
      'rtcStatus': 'VENDOR_BLOCKED',
      'imStatus': 'VENDOR_BLOCKED',
      'realtimeProvisioned': false,
    };

Map<String, Object?> _battleMap({String status = 'IN_PROGRESS'}) =>
    <String, Object?>{
      ..._invitationMap(status: 'ACCEPTED'),
      'battleId': _battleId,
      'battleStatus': status,
      'resultCode': status == 'COMPLETED' ? 'DRAW' : 'UNDECIDED',
      'startedAt': '2030-08-25T00:00:00Z',
      'endsAt': '2030-08-25T00:05:00Z',
      'completedAt': status == 'IN_PROGRESS' ? null : '2030-08-25T00:05:01Z',
      'countdownSeconds': status == 'IN_PROGRESS' ? 120 : 0,
      'leftRoomId': _roomId,
      'rightRoomId': _targetRoomId,
      'leftRoom': <String, Object?>{
        'roomId': _roomId,
        'roomCode': 'R111',
        'roomName': '当前房',
        'score': 120,
        'supporters': <Object?>[],
      },
      'rightRoom': <String, Object?>{
        'roomId': _targetRoomId,
        'roomCode': 'R222',
        'roomName': '目标房',
        'score': 80,
        'supporters': <Object?>[],
      },
    };

Map<String, Object?> _notificationSyncMap() => <String, Object?>{
  'synced': true,
  'projectionStatus': 'FIRST_PARTY_MATERIALIZED',
  'pushStatus': 'VENDOR_BLOCKED',
  'imStatus': 'VENDOR_BLOCKED',
  'providerInvocation': false,
  'dynamicUnread': 0,
  'notificationUnread': 0,
  'messageUnread': 0,
  'totalUnread': 0,
};

Map<String, Object?> _taskMap({required bool claimed}) => <String, Object?>{
  'taskId': 7,
  'id': 7,
  'taskCode': 'LIVE_TASK',
  'taskName': '完成一次互动',
  'title': '完成一次互动',
  'description': '第一方任务',
  'taskDesc': '第一方任务',
  'progress': claimed ? 1 : 0,
  'currentValue': claimed ? 1 : 0,
  'target': 1,
  'targetValue': 1,
  'rewardDesc': '奖励',
  'reward': '奖励',
  'claimed': claimed,
  'isReceive': claimed,
  'status': claimed ? 2 : 1,
  'businessDate': '2030-08-25',
};

Map<String, Object?> _signRewardsMap() {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[
    for (int day = 1; day <= 7; day += 1)
      <String, Object?>{
        'day': day,
        'signDay': day,
        'date': '2030-08-${(24 + day).toString().padLeft(2, '0')}',
        'rewardDesc': '奖励$day',
        'reward': '奖励$day',
        'completed': day == 1,
        'isSign': day == 1,
        'today': day == 7,
        'isToday': day == 7,
      },
  ];
  return <String, Object?>{
    'cycleStart': '2030-08-25',
    'cycleEnd': '2030-08-31',
    'list': rows,
    'records': rows,
    'total': rows.length,
    'providerInvocation': false,
  };
}

class _Request {
  const _Request({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
    required this.requestId,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
  final String requestId;
}

class _Reply {
  const _Reply({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.data,
  });

  const _Reply.ok(Object? data)
    : statusCode = 200,
      code = 200,
      message = 'OK',
      data = data;

  final int statusCode;
  final int code;
  final String message;
  final Object? data;
}

class _TestServer {
  _TestServer._(this.server, this.requests, this.client);

  final HttpServer server;
  final List<_Request> requests;
  final ApiClient client;

  String get baseUrl => 'http://127.0.0.1:${server.port}/';

  static Future<_TestServer> start(
    FutureOr<_Reply> Function(_Request request) responder,
  ) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<_Request> requests = <_Request>[];
    final _TestServer holder = _TestServer._(
      server,
      requests,
      ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer contract-test',
      ),
    );
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? decoded = rawBody.trim().isEmpty
          ? null
          : jsonDecode(rawBody);
      final _Request captured = _Request(
        method: request.method,
        path: request.uri.path,
        query: request.uri.queryParameters,
        body: decoded is Map ? Map<String, Object?>.from(decoded) : decoded,
        requestId: request.headers.value('X-Request-Id') ?? '',
      );
      holder.requests.add(captured);
      final _Reply reply = await responder(captured);
      request.response
        ..statusCode = reply.statusCode
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': reply.code,
            'message': reply.message,
            'data': reply.data,
          }),
        );
      await request.response.close();
    });
    return holder;
  }

  Future<void> close() => server.close(force: true);
}
