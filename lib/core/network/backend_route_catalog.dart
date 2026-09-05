class BackendRouteCatalog {
  const BackendRouteCatalog({
    this.sendSmsCode = '/app-register-api/util/v1/sendSmsCode',
    this.loginBySms =
        '/app-register-api/userAccount/v1/loginByMobileAndSmsCode',
    this.registerByMobile = '/app-register-api/userAccount/v1/registerByMobile',
    this.enterRoom = '/app-room-api/room/com/v1/enterRoom',
    this.createRoom = '/app-mini-api/mini/v1/rooms',
    this.closeRoom = '/app-mini-api/mini/v1/rooms/close',
    this.reopenRoom = '/app-mini-api/mini/v1/rooms/reopen',
    this.queryRoomInfo = '/app-room-api/room/com/v1/queryRoomInfo',
    this.reconnectRoom = '/app-room-api/room/com/v1/reConnectRoomInfo',
    this.queryRoomOtherInfo = '/app-room-api/room/com/v1/queryRoomOtherInfo',
    this.exitRoom = '/app-room-api/room/com/v1/exitRoom',
    this.buildRtcToken = '/app-room-api/room/com/v1/buildAgoraToken',
    this.sendGift = '/app-room-api/room/com/v1/sendGift',
    this.giftReceipt = '/app-room-api/room/com/v1/giftReceipt',
    this.sendPublicMessage = '/app-room-api/room/com/v1/roomScreenChat',
    this.publicMessages = '/app-mini-api/mini/v1/rooms/public-messages',
    this.userUpMic = '/app-api/micUserBase/userInitiativeUpMic',
    this.userLeaveMic = '/app-api/micUserBase/leaveMic',
    this.closeMic = '/app-api/micBase/closedMike',
    this.openMic = '/app-api/micBase/openMike',
    this.roomOnlineMembers = '/app-api/rooms/getRoomOnlinePersonnel',
    this.roomOffMicMembers = '/app-api/rooms/getRoomMicDownOnlinePersonnel',
    this.roomManagers = '/app-api/roomUsers/getRoomManagers',
    this.roomMutedUsers = '/app-api/roomUsers/getRoomMuteds',
    this.roomJoinRequests = '/app-mini-api/mini/v1/rooms/join-requests',
    this.resolveRoomJoinRequest =
        '/app-mini-api/mini/v1/rooms/join-requests/resolve',
    this.roomJoinRequestStatus =
        '/app-mini-api/mini/v1/rooms/join-requests/status',
    this.cancelRoomJoinRequest =
        '/app-mini-api/mini/v1/rooms/join-requests/cancel',
    this.roomMicRequests = '/app-mini-api/mini/v1/rooms/mic-requests',
    this.cancelRoomMicRequest =
        '/app-mini-api/mini/v1/rooms/mic-requests/cancel',
    this.resolveRoomMicRequest =
        '/app-mini-api/mini/v1/rooms/mic-requests/resolve',
    this.inviteRoomMicRequest =
        '/app-mini-api/mini/v1/rooms/mic-requests/invite',
    this.roomBannedUsers = '/app-mini-api/mini/v1/rooms/banned-users',
    this.unbanRoomUser = '/app-mini-api/mini/v1/rooms/unban',
    this.setRoomUserMuted = '/app-api/roomUsers/setMuted',
    this.setRoomUserRole = '/app-api/roomUsers/setRole',
    this.kickRoomUser = '/app-api/room/com/kickout',
    this.takeUserOffMic = '/app-api/micUserBase/hugUserDownMic',
    this.lockMic = '/app-api/micBase/lockMike',
    this.unlockMic = '/app-api/micBase/unlockMike',
    this.roomTopic = '/app-api/rooms/getRoomTopics',
    this.updateRoomTopic = '/app-api/rooms/setRoomTopics',
    this.homeRecommendedRooms = '/app-api/rooms/v1/getRecommendRooms',
    this.globalSearch = '/app-api/es/getSearchESResult',
    this.searchSuggestions = '/app-api/es/getSearchSuggestions',
    this.favoriteRooms = '/app-api/user/favorite/getFvoriteRooms',
    this.starRoom = '/app-api/user/favorite/starRoom',
    this.ownedRooms = '/app-api/rooms/getRoomSelectByUserId',
    this.roomById = '/app-api/rooms/getRoomById',
    this.updateRoomInformation = '/app-api/rooms/updateRoomInformation',
    this.personalData = '/app-api/user/getPersonalData',
    this.youthModeStatus = '/app-api/user/other/getMatchButtonAndYouthMode',
    this.queryAccountCancellation = '/app-api/user/queryUserLogout',
    this.deleteAccount = '/app-register-api/userAccount/v1/delete',
    this.cancelAccountDeletion =
        '/app-mini-api/mini/v1/account/deletion/cancel',
    this.queryAppealInfo = '/app-api/accappeal/queryAppealInfo',
    this.submitAppeal = '/app-api/accappeal/commitAppeal',
    this.queryAppealProgress = '/app-api/accappeal/queryAppealProcess',
    this.versionInformation = '/app-api/appBase/getVersionInformation',
    this.accountRealName = '/app-mini-api/mini/v1/account/real-name',
    this.accountSessions = '/app-mini-api/mini/v1/account/sessions',
    this.accountRestrictions = '/app-mini-api/mini/v1/account/restrictions',
    this.enableYouthMode = '/app-api/user/openYouthMode',
    this.disableYouthMode = '/app-api/user/turnOffYouthMode',
    this.updateUserProfile = '/app-api/user/updateUserByUserId',
    this.personalHomepage = '/app-api/user/personalHomepage',
    this.followingList = '/app-api/user/relation/queryUserFollowList',
    this.followersList = '/app-api/user/relation/queryUserFansList',
    this.friendsList = '/app-api/user/relation/queryUserPlaymateList',
    this.setFollowing = '/app-api/user/relation/buildFriendRelation',
    this.setBlocked = '/app-api/user/relation/blackUserRelation',
    this.blacklist = '/app-api/user/relation/queryUserBlackList',
    this.visitorRecords = '/app-api/user/personalHomepage/visitedRecords',
    this.onlyFollowedCanFollow = '/app-api/user/onlyFollowedCanFollow/set',
    this.reportUserOrRoom = '/app-api/util/tipOffUserOrRoom',
    this.customerService = '/app-api/user/getCustomerServiceDetail',
    this.submitFeedback = '/app-api/suggestion/saveSugggestion',
    this.socialPrivacy = '/app-mini-api/mini/v1/social/privacy',
    this.friendRequestList = '/app-mini-api/mini/v1/social/friend-request/list',
    this.friendRequestSend = '/app-mini-api/mini/v1/social/friend-request/send',
    this.friendRequestResolve =
        '/app-mini-api/mini/v1/social/friend-request/resolve',
    this.supportTicket = '/app-mini-api/mini/v1/support/ticket',
    this.ncoinBalance = '/app-economy-api/ncoin',
    this.paymentOrders = '/app-economy-api/pay/getOrders',
    this.paymentOrderResult = '/app-economy-api/pay/isOrderSuccess',
    this.refundCheck = '/app-api/refund/check',
    this.refundApplication = '/app-api/refund/application',
    this.refundResult = '/app-api/refund/result',
    this.refundHistory = '/app-api/refund/history',
    this.refundRepeat = '/app-api/refund/repeat',
    this.walletOverview = '/app-mini-api/mini/v1/wallet/overview',
    this.walletAccountDetails = '/app-mini-api/mini/v1/wallet/account-details',
    this.withdrawalFeeRate = '/app-mini-api/mini/v1/withdrawal/fee-rate',
    this.withdrawalApply = '/app-mini-api/mini/v1/withdrawal/apply',
    this.withdrawalRecords = '/app-mini-api/mini/v1/withdrawal/records',
    this.payoutAccounts = '/app-mini-api/mini/v1/withdrawal/accounts',
    this.dynamicPublish = '/app-mini-api/mini/v1/dynamic/publish',
    this.dynamicList = '/app-mini-api/mini/v1/dynamic/list',
    this.dynamicDetail = '/app-mini-api/mini/v1/dynamic/detail',
    this.dynamicMyList = '/app-mini-api/mini/v1/dynamic/list/my',
    this.dynamicUserList = '/app-mini-api/mini/v1/dynamic/list/user',
    this.dynamicDelete = '/app-mini-api/mini/v1/dynamic/delete',
    this.dynamicLike = '/app-mini-api/mini/v1/dynamic/like',
    this.dynamicComment = '/app-mini-api/mini/v1/dynamic/comment',
    this.dynamicComments = '/app-mini-api/mini/v1/dynamic/comment/list',
    this.charmRanking = '/app-api/rankinglist/charmrank',
    this.wealthRanking = '/app-api/rankinglist/wealthrank',
    this.contributionRanking = '/app-api/rankinglist/contribuitonrank',
    this.roomRanking = '/app-api/dfrank/queryRoomDfRank',
    this.recommendedGuilds = '/app-api/guild/getRecommendGuildPage',
    this.createGuild = '/app-mini-api/mini/v1/guild/create',
    this.searchGuilds = '/app-api/guild/searchGuild',
    this.guildHomepage = '/app-api/guild/getGuildHomepageDetails',
    this.currentGuild = '/app-api/guild/getCurrentGuild',
    this.guildMembers = '/app-api/guild/getGuildMembers',
    this.guildApplications = '/app-api/guild/getMembershipApplications',
    this.guildSign = '/app-api/guild/sign',
    this.guildSignStatus = '/app-api/guild/sign/status',
    this.applyGuildMembership = '/app-api/guildManagement/applyForMembership',
    this.quitGuild = '/app-api/guildManagement/quitGuild',
    this.resolveGuildApplication =
        '/app-api/guildManagement/approvalMembershipApplication',
    this.guildMemberMute = '/app-api/guildManagement/memberBanOrUnseal',
    this.removeGuildMember = '/app-api/guildManagement/kickOutMember',
    this.cpRelations = '/app-mini-api/mini/v1/cp/my-list',
    this.cpPendingInvitations = '/app-mini-api/mini/v1/cp/pending-requests',
    this.cpRequest = '/app-mini-api/mini/v1/cp/request',
    this.cpAccept = '/app-mini-api/mini/v1/cp/accept',
    this.cpReject = '/app-mini-api/mini/v1/cp/reject',
    this.cpEnd = '/app-mini-api/mini/v1/cp/end',
    this.cpEligibility =
        '/app-mini-api/mini/v1/cp/check-invitation-eligibility',
    this.guardianLevels = '/app-api/room/radio/v1/queryGuardianLevels',
    this.guardianInfo = '/app-api/room/radio/v1/queryOenGuardianInfo',
    this.currentGuardianLevel =
        '/app-api/room/radio/v1/queryCurrentGuardianLevel',
    this.becomeGuardian = '/app-api/room/radio/v1/becomeGuard',
    this.joinFansTeam = '/app-api/room/radio/v1/joinFansTeam',
    this.fansTeamPage = '/app-api/room/radio/v1/queryFansTeamPage',
    this.fansTeamBaseInfo = '/app-api/room/radio/v1/queryFansTeamBaseInfo',
    this.fansTeamTasks = '/app-api/room/radio/v1/queryFansTeamTaskPage',
    this.fansTeamRelation = '/app-api/room/radio/v1/queryFansTeamRelation',
    this.taskRecords = '/app-api/taskSystem/queryTaskRecords',
    this.claimTaskReward = '/app-api/taskSystem/receiveTaskReward',
    this.signRewards = '/app-api/taskSystem/querySignReward',
    this.completeSignIn = '/app-api/taskSystem/completeDailySignIn',
    this.todaySignStatus = '/app-api/taskSystem/queryTodaySignStatus',
    this.inviteAttribution = '/app-mini-api/mini/v1/invite/attribution',
    this.activityCatalog = '/app-mini-api/mini/v1/activity/list',
    this.roomPkInvite = '/app-api/activityPk/inviteRoomPk',
    this.roomPkAccept = '/app-api/activityPk/acceptRoomPkInvitation',
    this.roomPkReject = '/app-api/activityPk/rejectRoomPkInvitation',
    this.roomPkProgress = '/app-api/activityPk/queryRoomPkProcess',
    this.roomPkHistory = '/app-api/activityPk/queryRoomPkHistory',
    this.roomPkHotRooms = '/app-api/activityPk/getRoomPkHotRoomList',
    this.roomPkSearch = '/app-api/activityPk/searchRoomPk',
    this.rechargePrecheck = '/app-economy-api/pay/check',
    this.rechargeProducts = '/app-mini-api/mini/v1/recharge/products',
    this.createWechatRechargeOrder = '/app-economy-api/pay/v1/wechat/order',
    this.createAlipayRechargeOrder = '/app-economy-api/pay/ali/order',
    this.createAppleRechargeOrder = '/app-economy-api/pay/apple/order',
    this.deliverAppleTransaction = '/app-economy-api/pay/apple/transaction',
    this.appleRechargeOrderStatus = '/app-economy-api/pay/apple/order/status',
    this.cancelAlipayRechargeOrder = '/app-economy-api/pay/ali/order/cancel',
    this.reconcileAlipayRechargeOrder =
        '/app-economy-api/pay/ali/order/reconcile',
    this.alipayRechargeOrderStatus = '/app-economy-api/pay/ali/order/status',
    this.rechargeOrderStatus = '/app-economy-api/pay/isOrderSuccess',
    this.normalGiftCatalog = '/app-mini-api/mini/v1/gift/list',
    this.userDecorations = '/app-api/user/userDecorations/getList',
    this.equipUserDecoration = '/app-api/user/userDecorations/putOn',
    this.mallIndex = '/app-api/mall/index',
    this.purchaseMallGoods = '/app-api/mall/userBuyOrGiveGoods',
    this.privateChatHistory = '/app-api/user/imMessage/queryChat',
    this.chatUserStatus = '/app-api/user/imMessage/queryUserStatus',
    this.chatUserInfo = '/app-api/user/imMessage/getUserInfoInChat',
    this.imCredential = '/app-mini-api/mini/v1/im/credential',
    this.dynamicNotifications = '/app-api/dynamic/queryUserDynamicNotify',
    this.clearDynamicNotifications = '/app-api/dynamic/emptyUserDynamicNotify',
    this.dynamicNotificationBadge = '/app-api/dynamic/queryDynamicNotifyRedHot',
    this.pushNotificationDetail = '/app-api/nolg/getPushMsg',
    this.messagePermission = '/app-mini-api/mini/v1/message/permission',
    this.sendPrivateMessage = '/app-mini-api/mini/v1/message/send',
    this.messageConversations = '/app-mini-api/mini/v1/message/conversations',
    this.markPrivateMessageRead = '/app-mini-api/mini/v1/message/read',
    this.systemNotifications = '/app-mini-api/mini/v1/notifications',
    this.syncNotifications = '/app-mini-api/mini/v1/notifications/sync',
    this.markSystemNotificationRead =
        '/app-mini-api/mini/v1/notifications/read',
  });

  final String sendSmsCode;
  final String loginBySms;
  final String registerByMobile;
  final String enterRoom;
  final String createRoom;
  final String closeRoom;
  final String reopenRoom;
  final String queryRoomInfo;
  final String reconnectRoom;
  final String queryRoomOtherInfo;
  final String exitRoom;
  final String buildRtcToken;
  final String sendGift;
  final String giftReceipt;
  final String sendPublicMessage;
  final String publicMessages;
  final String userUpMic;
  final String userLeaveMic;
  final String closeMic;
  final String openMic;
  final String roomOnlineMembers;
  final String roomOffMicMembers;
  final String roomManagers;
  final String roomMutedUsers;
  final String roomJoinRequests;
  final String resolveRoomJoinRequest;
  final String roomJoinRequestStatus;
  final String cancelRoomJoinRequest;

  /// First-party approval-mode microphone queue. GET and submit POST share
  /// this canonical resource; mutations use the explicit child routes below.
  final String roomMicRequests;
  final String cancelRoomMicRequest;
  final String resolveRoomMicRequest;
  final String inviteRoomMicRequest;

  // Readable aliases for callers that describe the operation rather than the
  // room resource. They intentionally point to the same canonical paths.
  String get micRequests => roomMicRequests;
  String get submitRoomMicRequest => roomMicRequests;
  String get cancelMicRequest => cancelRoomMicRequest;
  String get resolveMicRequest => resolveRoomMicRequest;
  String get inviteMicRequest => inviteRoomMicRequest;
  final String roomBannedUsers;
  final String unbanRoomUser;
  final String setRoomUserMuted;
  final String setRoomUserRole;
  final String kickRoomUser;
  final String takeUserOffMic;
  final String lockMic;
  final String unlockMic;
  final String roomTopic;
  final String updateRoomTopic;
  final String homeRecommendedRooms;
  final String globalSearch;
  final String searchSuggestions;
  final String favoriteRooms;
  final String starRoom;
  final String ownedRooms;
  final String roomById;
  final String updateRoomInformation;
  final String personalData;
  final String youthModeStatus;
  final String queryAccountCancellation;
  final String deleteAccount;
  final String cancelAccountDeletion;
  final String queryAppealInfo;
  final String submitAppeal;
  final String queryAppealProgress;
  final String versionInformation;
  final String accountRealName;
  final String accountSessions;
  final String accountRestrictions;
  final String enableYouthMode;
  final String disableYouthMode;
  final String updateUserProfile;
  final String personalHomepage;
  final String followingList;
  final String followersList;
  final String friendsList;
  final String setFollowing;
  final String setBlocked;
  final String blacklist;
  final String visitorRecords;
  final String onlyFollowedCanFollow;
  final String reportUserOrRoom;
  final String customerService;
  final String submitFeedback;
  final String socialPrivacy;
  final String friendRequestList;
  final String friendRequestSend;
  final String friendRequestResolve;
  final String supportTicket;
  final String ncoinBalance;
  final String paymentOrders;
  final String paymentOrderResult;
  final String refundCheck;
  final String refundApplication;
  final String refundResult;
  final String refundHistory;
  final String refundRepeat;
  final String walletOverview;
  final String walletAccountDetails;
  final String withdrawalFeeRate;
  final String withdrawalApply;
  final String withdrawalRecords;
  final String payoutAccounts;
  final String dynamicPublish;
  final String dynamicList;
  final String dynamicDetail;
  final String dynamicMyList;
  final String dynamicUserList;
  final String dynamicDelete;
  final String dynamicLike;
  final String dynamicComment;
  final String dynamicComments;
  final String charmRanking;
  final String wealthRanking;
  final String contributionRanking;
  final String roomRanking;
  final String recommendedGuilds;
  final String createGuild;
  final String searchGuilds;
  final String guildHomepage;
  final String currentGuild;
  final String guildMembers;
  final String guildApplications;
  final String guildSign;
  final String guildSignStatus;
  final String applyGuildMembership;
  final String quitGuild;
  final String resolveGuildApplication;
  final String guildMemberMute;
  final String removeGuildMember;
  final String cpRelations;
  final String cpPendingInvitations;
  final String cpRequest;
  final String cpAccept;
  final String cpReject;
  final String cpEnd;
  final String cpEligibility;
  final String guardianLevels;
  final String guardianInfo;
  final String currentGuardianLevel;
  final String becomeGuardian;
  final String joinFansTeam;
  final String fansTeamPage;
  final String fansTeamBaseInfo;
  final String fansTeamTasks;
  final String fansTeamRelation;
  final String taskRecords;
  final String claimTaskReward;
  final String signRewards;
  final String completeSignIn;
  final String todaySignStatus;
  final String inviteAttribution;
  final String activityCatalog;
  final String roomPkInvite;
  final String roomPkAccept;
  final String roomPkReject;
  final String roomPkProgress;
  final String roomPkHistory;
  final String roomPkHotRooms;
  final String roomPkSearch;
  final String rechargePrecheck;
  final String rechargeProducts;
  final String createWechatRechargeOrder;
  final String createAlipayRechargeOrder;
  final String createAppleRechargeOrder;
  final String deliverAppleTransaction;
  final String appleRechargeOrderStatus;
  final String cancelAlipayRechargeOrder;
  final String reconcileAlipayRechargeOrder;
  final String alipayRechargeOrderStatus;
  final String rechargeOrderStatus;
  final String normalGiftCatalog;
  final String userDecorations;
  final String equipUserDecoration;
  final String mallIndex;
  final String purchaseMallGoods;
  final String privateChatHistory;
  final String chatUserStatus;
  final String chatUserInfo;
  final String imCredential;
  final String dynamicNotifications;
  final String clearDynamicNotifications;
  final String dynamicNotificationBadge;
  final String pushNotificationDetail;
  final String messagePermission;
  final String sendPrivateMessage;
  final String messageConversations;
  final String markPrivateMessageRead;
  final String systemNotifications;
  final String syncNotifications;
  final String markSystemNotificationRead;
}
