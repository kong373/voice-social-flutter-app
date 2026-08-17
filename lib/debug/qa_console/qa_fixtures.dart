import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/features/account/domain/auth_models.dart';
import 'package:voice_social_app/features/commerce/catalog/data/mock_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/pk/data/mock_room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';

Future<AppDependencies> createQaDependencies() async {
  final AppDependencies dependencies = AppDependencies.mock();
  await dependencies.sessionManager.acceptConsent();
  await dependencies.sessionManager.save(
    AuthSession(
      accessToken: 'qa-access-token',
      tokenType: 'Bearer',
      expiresAt: DateTime.now().add(const Duration(days: 365)),
      userId: 10001,
      mobile: '13800138000',
      roles: 'ROLE_USER',
      boundRoomId: '952700',
    ),
  );
  await dependencies.accountComplianceRepository.fetchSnapshot(
    account: '13800138000',
    currentVersion: 5,
    platformType: 1,
  );
  return dependencies;
}

const SocialProfile qaSocialProfile = SocialProfile(
  user: SocialUser(
    userId: 10001,
    name: 'QA 用户',
    signature: 'M2.4 Android Emulator 验收账号',
    avatarUrl: '',
    isFollowing: false,
    isFollower: false,
    isFriend: false,
    isBlocked: false,
    isOnline: true,
  ),
  account: '13800138000',
  sex: 1,
  birthday: '2000-01-01',
  city: '测试城市',
  coverUrl: '',
  followingCount: 12,
  followerCount: 18,
  friendCount: 6,
  postCount: 4,
  level: 3,
);

const List<MicSeat> qaEightSeats = <MicSeat>[
  MicSeat(
    number: 1,
    backendIndex: 1,
    state: MicSeatState.occupied,
    userId: 20001,
    userName: '房主 · 鹿屿',
    userRole: RoomRole.owner,
  ),
  MicSeat(
    number: 2,
    backendIndex: 2,
    state: MicSeatState.occupiedMuted,
    userId: 20002,
    userName: '南风',
    userRole: RoomRole.speaker,
  ),
  MicSeat(number: 3, backendIndex: 3, state: MicSeatState.available),
  MicSeat(number: 4, backendIndex: 4, state: MicSeatState.available),
  MicSeat(number: 5, backendIndex: 5, state: MicSeatState.locked),
  MicSeat(number: 6, backendIndex: 6, state: MicSeatState.available),
  MicSeat(number: 7, backendIndex: 7, state: MicSeatState.mutedAvailable),
  MicSeat(number: 8, backendIndex: 8, state: MicSeatState.available),
];

ConversationSummary qaConversation() => ConversationSummary(
  id: 'conversation-20001',
  kind: ConversationKind.privateChat,
  title: '晚星',
  lastMessage: '今晚房间的话题很温柔。',
  updatedAt: DateTime.now().subtract(const Duration(minutes: 8)),
  unreadCount: 2,
  targetUserId: 20001,
);

SupportTicket qaSupportTicket(AppDependencies dependencies) {
  final SupportTicket ticket = SupportTicket(
    id: 'ticket-qa-001',
    subject: 'Android 模拟器验收反馈',
    content: '用于检查工单详情与处理进度页面。',
    status: SupportTicketStatus.processing,
    statusText: '处理中',
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    progressAvailable: true,
  );
  (dependencies.socialRepository as MockSocialRepository)
      .seedSupportTicketForQa(ticket);
  return ticket;
}

const RechargeProduct qaRechargeProduct = RechargeProduct(
  id: 'qa-product-300',
  giftCoins: 300,
  priceCny: 30,
  label: 'QA 推荐',
  recommended: true,
);

RechargeOrder qaRechargeOrder(
  AppDependencies dependencies, {
  required bool succeeded,
}) {
  final RechargeOrder order = RechargeOrder(
    orderNo: 'QA-RECHARGE-001',
    account: '13800138000',
    product: qaRechargeProduct,
    channel: PaymentChannelType.wechat,
    state: succeeded
        ? RechargeOrderState.succeeded
        : RechargeOrderState.confirming,
    createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
    message: succeeded ? '服务端已确认到账' : '等待服务端确认',
  );
  (dependencies.commerceCatalogRepository as MockCommerceCatalogRepository)
      .seedRechargeOrderForQa(order);
  return order;
}

PaymentOrder qaPaymentOrder(AppDependencies dependencies) {
  final PaymentOrder order = PaymentOrder(
    orderNo: 'QA-ORDER-001',
    amount: 30,
    giftCoinAmount: 300,
    channelName: '微信支付',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    status: PaymentOrderStatus.confirming,
  );
  (dependencies.commerceRepository as MockCommerceRepository)
      .seedPaymentOrderForQa(order);
  return order;
}

RefundApplication qaRefundApplication(AppDependencies dependencies) {
  final RefundApplication application = RefundApplication(
    id: 'QA-REFUND-001',
    account: '13800138000',
    amount: 30,
    status: RefundStatus.reviewing,
    statusText: '审核中',
    rejectedReason: '',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
  );
  (dependencies.commerceRepository as MockCommerceRepository)
      .seedRefundApplicationForQa(application);
  return application;
}

RoomPkBattle qaRoomPkBattle(
  AppDependencies dependencies, {
  required bool completed,
}) {
  final RoomPkBattle battle = RoomPkBattle(
    id: 'qa-pk-battle',
    currentRoomId: '880217',
    sender: const RoomPkSide(
      roomId: '880217',
      roomCode: '880217',
      roomName: '深夜温柔陪伴',
      score: 3680,
    ),
    receiver: const RoomPkSide(
      roomId: '660318',
      roomCode: '660318',
      roomName: '下班后的松弛时刻',
      score: 2940,
    ),
    remainingSeconds: completed ? 0 : 95,
    punishmentTheme: '分享今天最开心的事',
    stage: completed ? RoomPkBattleStage.completed : RoomPkBattleStage.fighting,
    result: completed ? RoomPkResult.win : null,
    updatedAt: DateTime.now(),
  );
  (dependencies.roomPkRepository as MockRoomPkRepository).seedBattleForQa(
    battle,
  );
  return battle;
}

void seedQaRoomEntryRole(AppDependencies dependencies, RoomRole role) {
  (dependencies.roomRepository as MockRoomRepository).seedEntryRoleForQa(role);
}
