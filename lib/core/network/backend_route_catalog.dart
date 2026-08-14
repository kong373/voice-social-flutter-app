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
}
