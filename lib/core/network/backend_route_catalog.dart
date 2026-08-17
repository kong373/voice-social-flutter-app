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
}
