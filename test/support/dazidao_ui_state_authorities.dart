import 'dart:async';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/mock_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/social/data/mock_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/community/data/mock_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/commerce/data/mock_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/catalog/data/mock_commerce_catalog_repository.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/data/mock_room_repository.dart';
import 'package:voice_social_app/features/room/data/mock_room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/infrastructure/room_realtime_gateway.dart';
import 'package:voice_social_app/features/room/infrastructure/rtc_adapter.dart';

// Test-only read projections; production repositories, authentication and routes are not changed.
enum UiReadMode { normal, loading, error, empty }

const uiReadFailure = '加载失败，请重试。';

class UiReadProbe {
  UiReadProbe(
    this.target,
    this.mode, {
    this.variant = 'normal',
    this.role = 'ordinary',
  });
  final String target;
  final UiReadMode mode;
  final String variant;
  final String role;
  final reads = <String>[];
  final writes = <String>[];
  final _waiting = Completer<Never>();
  int intercepted = 0;
  Future<T> read<T>(
    String name,
    Future<T> Function() original, {
    T Function()? empty,
  }) {
    reads.add(name);
    if (name != target) return original();
    intercepted++;
    return switch (mode) {
      UiReadMode.loading => _waiting.future,
      UiReadMode.error => Future<T>.error(
        const ApiException(
          kind: ApiFailureKind.network,
          message: uiReadFailure,
        ),
      ),
      UiReadMode.empty when empty != null => Future<T>.value(empty()),
      _ => original(),
    };
  }

  Never forbidWrite(String name) {
    writes.add(name);
    throw StateError('Visual-only scenario attempted a write: $name');
  }
}

class UiScenarioScope implements AppDependencies {
  UiScenarioScope(this.base, this.probe);
  final AppDependencies base;
  final UiReadProbe probe;
  @override
  late final UiAccountRepository accountComplianceRepository =
      UiAccountRepository(probe);
  @override
  late final discoveryRepository = UiDiscoveryRepository(probe);
  @override
  late final dynamicRepository = UiDynamicRepository(probe);
  @override
  late final socialRepository = UiSocialRepository(probe);
  @override
  late final communityRepository = UiCommunityRepository(probe);
  @override
  late final messageRepository = UiMessageRepository(probe);
  @override
  late final commerceRepository = UiCommerceRepository(probe);
  @override
  late final commerceCatalogRepository = UiCatalogRepository(probe);
  final _controllers = <RoomController>[];
  Future<void> initialize() => accountComplianceRepository.initialize();
  @override
  RoomController createRoomController({
    required String roomId,
    required String title,
  }) {
    final controller = RoomController(
      roomId: roomId,
      title: title,
      currentUserId: sessionManager.session?.userId ?? 10001,
      accessToken: 'synthetic-ui-only',
      repository: roomRepository,
      roomOperationsRepository: roomOperationsRepository,
      rtcAdapter: const SnapshotOnlyRtcAdapter(),
      realtimeGateway: const SnapshotOnlyRoomRealtimeGateway(),
    );
    _controllers.add(controller);
    return controller;
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    base.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Missing test-only dependency delegation: ${invocation.memberName}',
  );
  @override
  late final environment = base.environment;
  @override
  late final imageMediaHost = base.imageMediaHost;
  @override
  late final privateMediaHost = base.privateMediaHost;
  @override
  late final sessionManager = base.sessionManager;
  @override
  late final authController = base.authController;
  @override
  late final imSessionAdapter = base.imSessionAdapter;
  @override
  late final imSessionCredentialRepository = base.imSessionCredentialRepository;
  @override
  late final imSessionCoordinator = base.imSessionCoordinator;
  @override
  late final imAuthoritativeRefreshBus = base.imAuthoritativeRefreshBus;
  @override
  late final tencentImAvChatRoomCoordinator =
      base.tencentImAvChatRoomCoordinator;
  @override
  late final currentTime = base.currentTime;
  @override
  late final liveReadOnlyRepository = base.liveReadOnlyRepository;
  @override
  late final alipayAppPayAdapter = base.alipayAppPayAdapter;
  @override
  late final appleIapStoreKit2Adapter = base.appleIapStoreKit2Adapter;
  @override
  late final appleIapPurchaseCoordinator = base.appleIapPurchaseCoordinator;
  @override
  late final roomRepository = UiRoomRepository(probe);
  @override
  late final giftSendCoordinator = base.giftSendCoordinator;
  @override
  late final roomOperationsRepository = UiRoomOperationsRepository(probe);
  @override
  late final roomLifecycleRepository = UiRoomLifecycleRepository(probe);
  @override
  late final platformRoomRepository = base.platformRoomRepository;
  @override
  late final roomPkRepository = base.roomPkRepository;
  @override
  late final rtcAdapter = base.rtcAdapter;
  @override
  late final realtimeGateway = base.realtimeGateway;
  @override
  late final roomAudioService = base.roomAudioService;
  @override
  late final externalUrlOpener = base.externalUrlOpener;
  @override
  late final complianceRevision = base.complianceRevision;
  @override
  bool? get youthModeResult => base.youthModeResult;
  @override
  void setProtectedAccessBlocked(bool blocked) =>
      base.setProtectedAccessBlocked(blocked);
  @override
  Future<bool> recoverAppleIapAfterAuthentication() =>
      base.recoverAppleIapAfterAuthentication();
  @override
  Future<void> changeYouthMode({required bool enabled, required String pin}) =>
      base.changeYouthMode(enabled: enabled, pin: pin);
}

class UiAccountRepository extends MockAccountComplianceRepository {
  UiAccountRepository(this.probe);
  final UiReadProbe probe;
  Future<void> initialize() async {
    await super.fetchSnapshot(
      account: '13800138000',
      expectedUserId: 10001,
      currentVersion: 6,
      platformType: 1,
    );
  }

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    int? expectedUserId,
    required int currentVersion,
    required int platformType,
  }) => probe.read('account.snapshot', () async {
    var value = await super.fetchSnapshot(
      account: account,
      expectedUserId: expectedUserId,
      currentVersion: currentVersion,
      platformType: platformType,
    );
    for (final state in VerificationState.values) {
      if (probe.variant == 'verification-${state.name}')
        value = value.copyWith(verificationState: state);
    }
    for (final state in PermissionState.values) {
      if (probe.variant == 'permission-${state.name}')
        value = value.copyWith(
          permissions: [
            for (final permission in value.permissions)
              PermissionSetting(
                kind: permission.kind,
                state: state,
                title: permission.title,
                purpose: permission.purpose,
                managedByPlatform: state == PermissionState.unavailable
                    ? null
                    : true,
              ),
          ],
        );
    }
    if (probe.variant == 'youth-locked')
      value = value.copyWith(youthModeEnabled: true);
    if (probe.variant == 'restricted')
      value = value.copyWith(
        restriction: const AccountRestriction(
          kind: RestrictionKind.account,
          reason: '账号访问受限，请查看处罚说明。',
        ),
      );
    if (probe.target == 'account.snapshot' && probe.mode == UiReadMode.empty)
      value = value.copyWith(sessions: const []);
    return value;
  });
  @override
  Future<AppealCase> queryAppeal({
    required String account,
    required String reasonType,
  }) => probe.read('account.appeal', () async {
    final original = await super.queryAppeal(
      account: account,
      reasonType: reasonType,
    );
    final state = AppealState.values
        .where((s) => probe.variant == 'appeal-${s.name}')
        .firstOrNull;
    if (state == null && probe.mode != UiReadMode.empty) return original;
    return AppealCase(
      account: account,
      nickname: original.nickname,
      reason: original.reason,
      reasonType: reasonType,
      state: state ?? AppealState.none,
      processText: state == null ? '暂无申诉记录' : '平台处理进度',
      resultText: state == null ? '' : '请以平台处理结果为准。',
      appealId: state == null || state == AppealState.none
          ? ''
          : 'synthetic-appeal',
    );
  });
  @override
  Future<CancellationEligibility> queryCancellationEligibility() =>
      probe.read('account.cancel', () async {
        if (probe.variant == 'cancel-blocked')
          return const CancellationEligibility(
            allowed: false,
            message: '暂不符合注销条件，请先处理未完成事项。',
            mobile: '138****8000',
            requiresSmsCode: false,
            status: 'BLOCKED',
          );
        if (probe.variant.startsWith('cancel-cooling'))
          return CancellationEligibility(
            allowed: false,
            message: '注销申请处理中',
            mobile: '138****8000',
            requiresSmsCode: false,
            status: 'COOLING_OFF',
            canCancel: probe.variant == 'cancel-cooling-open',
            coolingEndsAt: DateTime.now()
                .add(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
          );
        return super.queryCancellationEligibility();
      });
  @override
  Future<VersionUpdateInfo> checkVersion({
    required int currentVersion,
    required int platformType,
  }) => probe.read(
    'account.version',
    () async => VersionUpdateInfo(
      hasUpdate: probe.variant != 'version-current',
      forceUpdate: probe.variant == 'version-mandatory',
      versionName: '0.6.0',
      releaseNotes: '优化房间和消息体验。',
      packageUrl: '',
    ),
  );
  @override
  Future<void> setPermissionState({
    required PermissionKind kind,
    required PermissionState state,
  }) async => probe.forbidWrite('permission-request');
  @override
  Future<void> submitRealName({
    required String realName,
    required String idNumber,
  }) async => probe.forbidWrite('real-name');
  @override
  Future<void> revokeDeviceSession(String sessionId) async =>
      probe.forbidWrite('revoke-session');
  @override
  Future<void> requestCancellation({required String smsCode}) async =>
      probe.forbidWrite('cancel-account');
  @override
  Future<CancellationEligibility> cancelDeletion() async =>
      probe.forbidWrite('revoke-cancellation');
}

class UiDiscoveryRepository extends MockDiscoveryRepository {
  UiDiscoveryRepository(this.probe);
  final UiReadProbe probe;
  @override
  Future<List<DiscoveryRoom>> fetchHomeRooms({
    int page = 1,
    int pageSize = 20,
  }) => probe.read(
    'discovery.home',
    () => super.fetchHomeRooms(page: page, pageSize: pageSize),
    empty: () => [],
  );
  @override
  Future<DiscoverySearchResult> search({
    required String keyword,
    required SearchEntityType type,
    int page = 1,
    int pageSize = 20,
  }) => probe.read(
    'discovery.search',
    () => super.search(
      keyword: keyword,
      type: type,
      page: page,
      pageSize: pageSize,
    ),
    empty: () => DiscoverySearchResult(
      rooms: [],
      users: [],
      page: page,
      pageSize: pageSize,
      hasMore: false,
    ),
  );
  @override
  Future<List<DiscoverySearchSuggestion>> fetchSearchSuggestions({
    int limit = 10,
  }) => probe.read(
    'discovery.suggestions',
    () => super.fetchSearchSuggestions(limit: limit),
    empty: () => [],
  );
  @override
  Future<RoomCollectionSnapshot> fetchRoomCollections({
    int page = 1,
    int pageSize = 30,
  }) => probe.read(
    'discovery.collections',
    () => super.fetchRoomCollections(page: page, pageSize: pageSize),
    empty: () => const RoomCollectionSnapshot(favorites: [], ownedRooms: []),
  );
  @override
  Future<bool> setFavorite({
    required String roomId,
    required bool favorite,
  }) async => probe.forbidWrite('favorite');
}

class UiDynamicRepository extends MockDynamicRepository {
  UiDynamicRepository(this.probe);
  final UiReadProbe probe;
  @override
  Future<PagedResult<DynamicPost>> fetchFeed({
    DynamicCategory category = DynamicCategory.all,
    int page = 1,
    int pageSize = 20,
  }) => probe.read(
    'dynamic.feed',
    () => super.fetchFeed(category: category, page: page, pageSize: pageSize),
    empty: () => PagedResult(items: [], page: page, hasMore: false),
  );
  @override
  Future<DynamicPost> fetchPost(String dynamicId) =>
      probe.read('dynamic.post', () => super.fetchPost(dynamicId));
  @override
  Future<PagedResult<DynamicComment>> fetchComments({
    required String dynamicId,
    int page = 1,
    int pageSize = 30,
  }) => probe.read(
    'dynamic.comments',
    () => super.fetchComments(
      dynamicId: dynamicId,
      page: page,
      pageSize: pageSize,
    ),
    empty: () => PagedResult(items: [], page: page, hasMore: false),
  );
  @override
  Future<RankingSnapshot> fetchRanking({
    required RankingBoard board,
    required RankingPeriod period,
    int page = 1,
    int pageSize = 20,
  }) => probe.read(
    'dynamic.ranking',
    () => super.fetchRanking(
      board: board,
      period: period,
      page: page,
      pageSize: pageSize,
    ),
    empty: () => RankingSnapshot(
      board: board,
      period: period,
      entries: [],
      page: page,
      pageSize: pageSize,
    ),
  );
  @override
  Future<DynamicPost> toggleLike(
    String dynamicId, {
    required bool liked,
    String? requestId,
  }) async => probe.forbidWrite('like');
  @override
  Future<DynamicPost> publish(
    PublishDynamicRequest request, {
    String? requestId,
  }) async => probe.forbidWrite('publish');
}

class UiMessageRepository extends MockMessageRepository {
  UiMessageRepository(this.probe);
  final UiReadProbe probe;
  @override
  Future<List<ConversationSummary>> fetchConversations() => probe.read(
    'message.conversations',
    () => super.fetchConversations(),
    empty: () => [],
  );
  @override
  Future<List<ChatMessage>> fetchPrivateMessages(
    ConversationSummary conversation,
  ) => probe.read('message.private', () async {
    final original = await super.fetchPrivateMessages(conversation);
    final delivery = MessageDeliveryStatus.values
        .where((value) => probe.variant == 'delivery-${value.name}')
        .firstOrNull;
    if (delivery == null) return original;
    return [
      for (final message in original)
        message.isMine ? message.copyWith(deliveryStatus: delivery) : message,
    ];
  }, empty: () => []);
  @override
  Future<List<AppNotification>> fetchNotifications(
    NotificationCategory category,
  ) => probe.read(
    'message.notifications',
    () => super.fetchNotifications(category),
    empty: () => [],
  );
  @override
  Future<AppNotification> fetchNotification(String notificationId) =>
      probe.read('message.notification', () async {
        final original = await super.fetchNotification(notificationId);
        return probe.variant == 'target-unavailable'
            ? original.copyWith(
                targetAvailable: false,
                unavailableReason: '内容已删除或暂不可见',
              )
            : original;
      });
  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
    String? requestId,
  }) async => probe.forbidWrite('private-message');
  @override
  Future<MessageRecoverySnapshot> fetchRecoverySnapshot() =>
      probe.read('message.recovery', () async {
        final original = await super.fetchRecoverySnapshot();
        final permission = NativeNotificationPermissionState.values
            .where((value) => probe.variant == 'notification-${value.name}')
            .firstOrNull;
        return permission == null
            ? original
            : MessageRecoverySnapshot(
                privateRealtimeAvailable: false,
                notificationPermission: permission,
                lastNotificationSyncAt: null,
                message: '消息状态以服务端和系统权限为准。',
              );
      });
  @override
  Future<MessageRecoverySnapshot> requestNotificationPermission() async =>
      probe.forbidWrite('notification-permission');
  @override
  Future<void> clearInteractionNotifications() async =>
      probe.forbidWrite('clear-notifications');
}

class UiSocialRepository extends MockSocialRepository {
  UiSocialRepository(this.probe);
  final UiReadProbe probe;
  @override
  Future<SocialProfile> fetchMyProfile() =>
      probe.read('social.profile', () => super.fetchMyProfile());
  @override
  Future<SocialProfile> fetchPublicProfile(int userId) =>
      probe.read('social.public', () => super.fetchPublicProfile(userId));
  @override
  Future<SocialPage<SocialUser>> fetchRelations({
    required SocialRelationList type,
    required int page,
    required int pageSize,
  }) => probe.read(
    'social.relations',
    () => super.fetchRelations(type: type, page: page, pageSize: pageSize),
    empty: () => SocialPage(
      items: [],
      page: page,
      pageSize: pageSize,
      total: 0,
      hasMore: false,
    ),
  );
  @override
  Future<SocialPage<SocialUser>> fetchVisitors({
    required VisitorRecordType type,
    required int page,
    required int pageSize,
  }) => probe.read(
    'social.visitors',
    () => super.fetchVisitors(type: type, page: page, pageSize: pageSize),
    empty: () => SocialPage(
      items: [],
      page: page,
      pageSize: pageSize,
      total: 0,
      hasMore: false,
    ),
  );
  @override
  Future<PrivacySettings> fetchPrivacySettings() =>
      probe.read('social.privacy', () => super.fetchPrivacySettings());
  @override
  Future<SocialPage<SocialUser>> fetchBlacklist({
    required int page,
    required int pageSize,
  }) => probe.read(
    'social.blacklist',
    () => super.fetchBlacklist(page: page, pageSize: pageSize),
    empty: () => SocialPage(
      items: [],
      page: page,
      pageSize: pageSize,
      total: 0,
      hasMore: false,
    ),
  );
  @override
  Future<SupportChannel> fetchCustomerService() =>
      probe.read('social.service', () => super.fetchCustomerService());
  @override
  Future<SocialPage<SupportTicket>> fetchSupportTickets({
    required int page,
    required int pageSize,
  }) => probe.read(
    'social.tickets',
    () => super.fetchSupportTickets(page: page, pageSize: pageSize),
    empty: () => SocialPage(
      items: [],
      page: page,
      pageSize: pageSize,
      total: 0,
      hasMore: false,
    ),
  );
  @override
  Future<SupportTicket> fetchSupportTicket(String ticketId) =>
      probe.read('social.ticket', () async {
        final value = await super.fetchSupportTicket(ticketId);
        final status = SupportTicketStatus.values
            .where((value) => probe.variant == 'ticket-${value.name}')
            .firstOrNull;
        return status == null
            ? value
            : SupportTicket(
                id: value.id,
                subject: value.subject,
                content: value.content,
                status: status,
                statusText: status == SupportTicketStatus.closed
                    ? '已关闭'
                    : status == SupportTicketStatus.resolved
                    ? '已解决'
                    : '处理中',
                createdAt: value.createdAt,
                progressAvailable: status != SupportTicketStatus.unavailable,
                events: value.events,
                version: value.version,
              );
      });
  @override
  Future<void> setFollowing({
    required int userId,
    required bool following,
  }) async => probe.forbidWrite('follow');
  @override
  Future<void> setBlocked({required int userId, required bool blocked}) async =>
      probe.forbidWrite('block');
  @override
  Future<PrivacySettings> updatePrivacySettings({
    required bool onlyFollowedCanFollow,
  }) async => probe.forbidWrite('privacy');
  @override
  Future<String> submitReport({
    required ReportTargetType targetType,
    required String targetId,
    required int reasonCode,
    required String description,
    required bool alsoBlock,
  }) async => probe.forbidWrite('report');
}

class UiCommunityRepository extends MockCommunityRepository {
  UiCommunityRepository(this.probe)
    : super(
        viewerRole: probe.role == 'chair'
            ? GuildRole.owner
            : probe.role == 'anchor'
            ? GuildRole.member
            : GuildRole.visitor,
      );
  final UiReadProbe probe;
  @override
  Future<GuildHomeSnapshot> fetchGuildHome() => probe.read(
    'community.home',
    () async {
      final value = await super.fetchGuildHome();
      if (probe.variant == 'guild-authority-unknown')
        return const GuildHomeSnapshot();
      return GuildHomeSnapshot(
        currentGuild: probe.role == 'ordinary' ? null : value.currentGuild,
        currentGuildAuthority: GuildCurrentAuthority.authoritative,
        recommended: value.recommended,
      );
    },
    empty: () => const GuildHomeSnapshot(
      currentGuildAuthority: GuildCurrentAuthority.authoritative,
    ),
  );
  @override
  Future<List<GuildSummary>> searchGuilds(String keyword) => probe.read(
    'community.search',
    () => super.searchGuilds(keyword),
    empty: () => [],
  );
  @override
  Future<GuildSummary> fetchGuild(String guildId) =>
      probe.read('community.guild', () async {
        final guild = await super.fetchGuild(guildId);
        return guild.copyWith(
          status: probe.variant == 'guild-closed'
              ? GuildStatus.closed
              : guild.status,
          role: probe.role == 'chair'
              ? GuildRole.owner
              : probe.role == 'anchor'
              ? GuildRole.member
              : GuildRole.visitor,
          joined: probe.role != 'ordinary',
          applicationPending: probe.variant == 'guild-pending',
        );
      });
  @override
  Future<List<GuildMember>> fetchGuildMembers(String guildId) => probe.read(
    'community.members',
    () => super.fetchGuildMembers(guildId),
    empty: () => [],
  );
  @override
  Future<List<GuildApplication>> fetchGuildApplications(String guildId) =>
      probe.read(
        'community.applications',
        () => super.fetchGuildApplications(guildId),
        empty: () => [],
      );
  @override
  Future<InviteAttribution> fetchInviteAttribution() => probe.read(
    'community.invite',
    () => super.fetchInviteAttribution(),
    empty: () => const InviteAttribution(available: false, message: '暂未形成邀请归属'),
  );
  @override
  Future<void> applyToJoinGuild(String guildId) async =>
      probe.forbidWrite('guild-join');
  @override
  Future<void> quitGuild(String guildId) async =>
      probe.forbidWrite('guild-quit');
  @override
  Future<void> resolveGuildApplication({
    required String applicationId,
    required bool accepted,
  }) async => probe.forbidWrite('guild-review');
  @override
  Future<void> setGuildMemberMuted({
    required String guildId,
    required int userId,
    required bool muted,
  }) async => probe.forbidWrite('guild-mute');
  @override
  Future<void> removeGuildMember({
    required String guildId,
    required int userId,
  }) async => probe.forbidWrite('guild-remove');
}

class UiCommerceRepository extends MockCommerceRepository {
  UiCommerceRepository(this.probe) {
    incomeRole = probe.role == 'chair'
        ? IncomeRole.guildChair
        : probe.role == 'anchor'
        ? IncomeRole.anchor
        : IncomeRole.ordinary;
  }
  final UiReadProbe probe;
  @override
  Future<WalletSummary> fetchWalletSummary() =>
      probe.read('commerce.wallet', () => super.fetchWalletSummary());
  @override
  Future<CommercePage<LedgerEntry>> fetchLedger({
    required LedgerCurrency currency,
    required LedgerDirection direction,
    required int page,
    required int pageSize,
  }) => probe.read(
    'commerce.ledger',
    () => super.fetchLedger(
      currency: currency,
      direction: direction,
      page: page,
      pageSize: pageSize,
    ),
    empty: () => CommercePage(
      items: [],
      page: page,
      pageSize: pageSize,
      total: 0,
      hasMore: false,
    ),
  );
  @override
  Future<CommercePage<PaymentOrder>> fetchOrders({
    required int page,
    required int pageSize,
  }) => probe.read(
    'commerce.orders',
    () => super.fetchOrders(page: page, pageSize: pageSize),
    empty: () => CommercePage(
      items: [],
      page: page,
      pageSize: pageSize,
      total: 0,
      hasMore: false,
    ),
  );
  @override
  Future<PaymentOrder> queryOrderStatus(
    PaymentOrder order, {
    bool reconcile = false,
  }) => probe.read('commerce.order', () async => order);
  @override
  Future<WithdrawalRecord> applyWithdrawal({
    required double amount,
    required WithdrawalQuote confirmedQuote,
    String? payoutAccountId,
  }) async => probe.forbidWrite('withdrawal');
}

class UiCatalogRepository extends MockCommerceCatalogRepository {
  UiCatalogRepository(this.probe);
  final UiReadProbe probe;
  @override
  Future<List<RechargeProduct>> fetchRechargeProducts({
    required ClientStorePlatform platform,
  }) => probe.read(
    'catalog.products',
    () => super.fetchRechargeProducts(platform: platform),
    empty: () => [],
  );
  @override
  Future<List<GiftCatalogItem>> fetchGiftCatalog() => probe.read(
    'catalog.gifts',
    () => super.fetchGiftCatalog(),
    empty: () => [],
  );
  @override
  Future<List<DecorationItem>> fetchDecorations() =>
      probe.read('catalog.decorations', () async {
        final items = await super.fetchDecorations();
        if (probe.variant == 'decoration-expired')
          return [
            for (final item in items)
              item.copyWith(
                owned: false,
                equipped: false,
                expiresAt: DateTime.utc(2020),
              ),
          ];
        if (probe.variant == 'decoration-retired')
          return [for (final item in items) item.copyWith(forSale: false)];
        return items;
      }, empty: () => []);
  @override
  Future<RechargeOrder> queryRechargeOrder(RechargeOrder order) =>
      probe.read('catalog.result', () async => order);
  @override
  Future<RechargeOrder> createRechargeOrder({
    required String account,
    required RechargeProduct product,
    required PaymentChannelType channel,
    required ClientStorePlatform platform,
    required bool youthModeEnabled,
  }) async => probe.forbidWrite('recharge');
  @override
  Future<RechargeOrder> invokePayment(RechargeOrder order) async =>
      probe.forbidWrite('payment');
  @override
  Future<DecorationItem> purchaseDecoration(String decorationId) async =>
      probe.forbidWrite('decoration-purchase');
  @override
  Future<DecorationItem> setDecorationEquipped({
    required String decorationId,
    required bool equipped,
  }) async => probe.forbidWrite('decoration-equip');
}

class UiRoomRepository extends MockRoomRepository {
  UiRoomRepository(this.probe) {
    seedEntryRoleForQa(
      probe.role == 'roomOwner'
          ? RoomRole.owner
          : probe.role == 'roomModerator'
          ? RoomRole.moderator
          : RoomRole.listener,
    );
  }
  final UiReadProbe probe;
  @override
  Future<RoomSnapshot> enterRoom({
    required String roomId,
    required String? password,
    required RoomEntrySource source,
    required int currentUserId,
  }) => probe.read(
    'room.enter',
    () async => (await super.enterRoom(
      roomId: roomId,
      password: password,
      source: source,
      currentUserId: currentUserId,
    )).copyWith(transportMode: RoomTransportMode.snapshotOnly),
  );
}

class UiRoomOperationsRepository extends MockRoomOperationsRepository {
  UiRoomOperationsRepository(this.probe);
  final UiReadProbe probe;
  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    required int page,
    int pageSize = 20,
  }) => probe.read(
    'room.members',
    () => super.fetchOnlineMembers(
      roomId: roomId,
      page: page,
      pageSize: pageSize,
    ),
    empty: () => RoomMemberPage(items: [], page: page, total: 0, pages: 0),
  );
  @override
  Future<List<RoomMember>> fetchOffMicListeners(String roomId) => probe.read(
    'room.listeners',
    () => super.fetchOffMicListeners(roomId),
    empty: () => [],
  );
  @override
  Future<List<RoomMember>> fetchManagers(String roomId) => probe.read(
    'room.managers',
    () => super.fetchManagers(roomId),
    empty: () => [],
  );
  @override
  Future<List<RoomMember>> fetchMutedUsers(String roomId) => probe.read(
    'room.muted',
    () => super.fetchMutedUsers(roomId),
    empty: () => [],
  );
  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) => probe.read(
    'room.mic-queue',
    () => super.fetchMicRequests(roomId),
    empty: () => [],
  );
  @override
  Future<RoomTopic> fetchTopic(String roomId) => probe.read(
    'room.topic',
    () => super.fetchTopic(roomId),
    empty: () => const RoomTopic(title: '', content: '', version: 1),
  );
  @override
  Future<void> updateTopic({
    required String roomId,
    required RoomTopic topic,
  }) async => probe.forbidWrite('room-topic');
  @override
  Future<void> kickUser({required String roomId, required int userId}) async =>
      probe.forbidWrite('room-kick');
  @override
  Future<void> setUserMuted({
    required String roomId,
    required int userId,
    required bool muted,
  }) async => probe.forbidWrite('room-mute');
}

class UiRoomLifecycleRepository extends MockRoomLifecycleRepository {
  UiRoomLifecycleRepository(this.probe);
  final UiReadProbe probe;
  @override
  Future<List<OwnedRoomSummary>> fetchOwnedRooms() =>
      probe.read('room.owned', () => super.fetchOwnedRooms(), empty: () => []);
  @override
  Future<RoomConfiguration> fetchRoom(String roomId) =>
      probe.read('room.configuration', () => super.fetchRoom(roomId));
  @override
  Future<RoomLinkResolution> resolveRoomLink(String input) =>
      probe.read('room.link', () => super.resolveRoomLink(input));
  @override
  Future<RoomLifecycleSaveResult> saveRoom(
    RoomConfiguration configuration,
  ) async => probe.forbidWrite('room-save');
  @override
  Future<void> closeRoom(String roomId, {int? expectedVersion}) async =>
      probe.forbidWrite('room-close');
}
