import 'dart:async';

class RoomRealtimeEvent {
  const RoomRealtimeEvent({
    required this.code,
    required this.payload,
  });

  final int code;
  final Map<String, Object?> payload;
}

abstract interface class RoomRealtimeGateway {
  Stream<RoomRealtimeEvent> get events;

  Future<void> connect({
    required String roomId,
    required int userId,
    required String accessToken,
  });

  Future<void> reconnect();

  Future<void> disconnect();
}

class MockRoomRealtimeGateway implements RoomRealtimeGateway {
  final StreamController<RoomRealtimeEvent> _controller =
      StreamController<RoomRealtimeEvent>.broadcast(sync: true);

  bool _connected = false;

  @override
  Stream<RoomRealtimeEvent> get events => _controller.stream;

  @override
  Future<void> connect({
    required String roomId,
    required int userId,
    required String accessToken,
  }) {
    _connected = true;
    return Future<void>.value();
  }

  @override
  Future<void> reconnect() {
    _connected = true;
    return Future<void>.value();
  }

  @override
  Future<void> disconnect() {
    _connected = false;
    return Future<void>.value();
  }

  void emit(RoomRealtimeEvent event) {
    if (_connected && !_controller.isClosed) {
      _controller.add(event);
    }
  }

  Future<void> dispose() => _controller.close();
}

class UnavailableRoomRealtimeGateway implements RoomRealtimeGateway {
  const UnavailableRoomRealtimeGateway();

  @override
  Stream<RoomRealtimeEvent> get events => const Stream<RoomRealtimeEvent>.empty();

  @override
  Future<void> connect({
    required String roomId,
    required int userId,
    required String accessToken,
  }) async {
    throw StateError('实时消息传输适配器尚未配置');
  }

  @override
  Future<void> reconnect() async {
    throw StateError('实时消息传输适配器尚未配置');
  }

  @override
  Future<void> disconnect() async {}
}

class RoomRealtimeEventCodes {
  const RoomRealtimeEventCodes._();

  static const int putOnMic = 101001;
  static const int takeDownMic = 101002;
  static const int closeMic = 101003;
  static const int openMic = 101004;
  static const int mutedInRoom = 103001;
  static const int unmutedInRoom = 103002;
  static const int kickedOut = 103003;
  static const int roomTopic = 301001;
  static const int roomName = 301003;
  static const int roomAutoLock = 302004;
  static const int roomBanned = 303003;
  static const int publicChat = 303004;
  static const int gift = 304001;
  static const int micInfo = 306001;
  static const int pkInvited = 310001;
  static const int pkAccepted = 310002;
  static const int pkRejected = 310003;
  static const int pkProgress = 310004;
  static const int pkResult = 310005;

  static const Set<int> allowed = <int>{
    putOnMic,
    takeDownMic,
    closeMic,
    openMic,
    mutedInRoom,
    unmutedInRoom,
    kickedOut,
    roomTopic,
    roomName,
    roomAutoLock,
    roomBanned,
    publicChat,
    gift,
    micInfo,
    pkInvited,
    pkAccepted,
    pkRejected,
    pkProgress,
    pkResult,
  };
}
