class BackendRouteCatalog {
  const BackendRouteCatalog({
    this.sendSmsCode = '/app-register-api/util/v1/sendSmsCode',
    this.loginBySms =
        '/app-register-api/userAccount/v1/loginByMobileAndSmsCode',
    this.registerByMobile =
        '/app-register-api/userAccount/v1/registerByMobile',
    this.enterRoom = '/app-room-api/room/com/v1/enterRoom',
    this.queryRoomInfo = '/app-room-api/room/com/v1/queryRoomInfo',
    this.reconnectRoom = '/app-room-api/room/com/v1/reConnectRoomInfo',
    this.queryRoomOtherInfo =
        '/app-room-api/room/com/v1/queryRoomOtherInfo',
    this.exitRoom = '/app-room-api/room/com/v1/exitRoom',
    this.buildRtcToken = '/app-room-api/room/com/v1/buildAgoraToken',
    this.sendGift = '/app-room-api/room/com/v1/sendGift',
    this.sendPublicMessage = '/app-room-api/room/com/v1/roomScreenChat',
    this.userUpMic = '/app-api/micUserBase/userInitiativeUpMic',
    this.userLeaveMic = '/app-api/micUserBase/leaveMic',
    this.closeMic = '/app-api/micBase/closedMike',
    this.openMic = '/app-api/micBase/openMike',
    this.roomOnlineMembers = '/app-api/rooms/getRoomOnlinePersonnel',
    this.roomOffMicMembers = '/app-api/rooms/getRoomMicDownOnlinePersonnel',
    this.roomManagers = '/app-api/roomUsers/getRoomManagers',
    this.roomMutedUsers = '/app-api/roomUsers/getRoomMuteds',
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
    this.favoriteRooms = '/app-api/user/favorite/getFvoriteRooms',
    this.starRoom = '/app-api/user/favorite/starRoom',
    this.ownedRooms = '/app-api/rooms/getRoomSelectByUserId',
    this.roomById = '/app-api/rooms/getRoomById',
    this.updateRoomInformation = '/app-api/rooms/updateRoomInformation',
    this.personalData = '/app-api/user/getPersonalData',
    this.youthModeStatus =
        '/app-api/user/other/getMatchButtonAndYouthMode',
    this.queryAccountCancellation = '/app-api/user/queryUserLogout',
    this.deleteAccount = '/app-register-api/userAccount/v1/delete',
    this.queryAppealInfo = '/app-api/accappeal/queryAppealInfo',
    this.submitAppeal = '/app-api/accappeal/commitAppeal',
    this.queryAppealProgress = '/app-api/accappeal/queryAppealProcess',
    this.versionInformation = '/app-api/appBase/getVersionInformation',
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
    this.ncoinBalance = '/app-economy-api/ncoin',
    this.paymentOrders = '/app-economy-api/pay/getOrders',
    this.paymentOrderResult = '/app-economy-api/pay/isOrderSuccess',
    this.refundCheck = '/app-api/refund/check',
    this.refundApplication = '/app-api/refund/application',
    this.refundResult = '/app-api/refund/result',
    this.refundRepeat = '/app-api/refund/repeat',
    this.walletOverview = '/app-mini-api/mini/v1/wallet/overview',
    this.walletAccountDetails =
        '/app-mini-api/mini/v1/wallet/account-details',
    this.withdrawalFeeRate = '/app-mini-api/mini/v1/withdrawal/fee-rate',
    this.withdrawalApply = '/app-mini-api/mini/v1/withdrawal/apply',
    this.withdrawalRecords = '/app-mini-api/mini/v1/withdrawal/records',
  });

  final String sendSmsCode;
  final String loginBySms;
  final String registerByMobile;
  final String enterRoom;
  final String queryRoomInfo;
  final String reconnectRoom;
  final String queryRoomOtherInfo;
  final String exitRoom;
  final String buildRtcToken;
  final String sendGift;
  final String sendPublicMessage;
  final String userUpMic;
  final String userLeaveMic;
  final String closeMic;
  final String openMic;
  final String roomOnlineMembers;
  final String roomOffMicMembers;
  final String roomManagers;
  final String roomMutedUsers;
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
  final String favoriteRooms;
  final String starRoom;
  final String ownedRooms;
  final String roomById;
  final String updateRoomInformation;
  final String personalData;
  final String youthModeStatus;
  final String queryAccountCancellation;
  final String deleteAccount;
  final String queryAppealInfo;
  final String submitAppeal;
  final String queryAppealProgress;
  final String versionInformation;
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
  final String ncoinBalance;
  final String paymentOrders;
  final String paymentOrderResult;
  final String refundCheck;
  final String refundApplication;
  final String refundResult;
  final String refundRepeat;
  final String walletOverview;
  final String walletAccountDetails;
  final String withdrawalFeeRate;
  final String withdrawalApply;
  final String withdrawalRecords;
}
