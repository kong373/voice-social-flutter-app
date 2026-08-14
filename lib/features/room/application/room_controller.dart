import 'package:flutter/foundation.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

class RoomController extends ChangeNotifier {
  RoomController({
    this.roomId = '880217',
    this.title = '深夜温柔陪伴',
  }) : _seats = <MicSeat>[
          const MicSeat(
            number: 1,
            state: MicSeatState.occupied,
            userName: '房主 · 鹿屿',
            isSpeaking: true,
          ),
          const MicSeat(
            number: 2,
            state: MicSeatState.occupiedMuted,
            userName: '南风',
          ),
          const MicSeat(
            number: 3,
            state: MicSeatState.occupied,
            userName: '晚星',
          ),
          const MicSeat(number: 4, state: MicSeatState.available),
          const MicSeat(number: 5, state: MicSeatState.locked),
          const MicSeat(number: 6, state: MicSeatState.available),
          const MicSeat(number: 7, state: MicSeatState.mutedAvailable),
          const MicSeat(number: 8, state: MicSeatState.available),
        ],
        _messages = <RoomMessage>[
          const RoomMessage(
            sender: '系统',
            content: '欢迎进入房间，请友善交流。',
            isSystem: true,
          ),
          const RoomMessage(sender: '晚星', content: '今天也辛苦啦。'),
          const RoomMessage(sender: '南风', content: '想听大家聊聊最近的小确幸。'),
        ];

  final String roomId;
  final String title;

  List<MicSeat> _seats;
  final List<RoomMessage> _messages;
  RoomRole _role = RoomRole.listener;
  RoomSessionStatus _status = RoomSessionStatus.joined;
  int _giftBalance = 1200;
  bool _micMuted = false;
  bool _micRequestPending = false;

  List<MicSeat> get seats => List<MicSeat>.unmodifiable(_seats);
  List<RoomMessage> get messages => List<RoomMessage>.unmodifiable(_messages);
  RoomRole get role => _role;
  RoomSessionStatus get status => _status;
  int get giftBalance => _giftBalance;
  bool get micMuted => _micMuted;
  bool get micRequestPending => _micRequestPending;

  bool get isOnMic =>
      _role == RoomRole.speaker ||
      _role == RoomRole.moderator ||
      _role == RoomRole.owner;

  Future<bool> requestMic(int seatNumber) async {
    if (_micRequestPending ||
        isOnMic ||
        _status != RoomSessionStatus.joined) {
      return false;
    }

    final int index = _seats.indexWhere(
      (MicSeat seat) => seat.number == seatNumber && seat.isAvailable,
    );
    if (index < 0) {
      return false;
    }

    _micRequestPending = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    _seats = List<MicSeat>.of(_seats)
      ..[index] = _seats[index].copyWith(
        state: MicSeatState.occupied,
        userName: '我',
      );
    _role = RoomRole.speaker;
    _micRequestPending = false;
    _messages.add(
      RoomMessage(
        sender: '系统',
        content: '你已上 $seatNumber 号麦。',
        isSystem: true,
      ),
    );
    notifyListeners();
    return true;
  }

  void toggleMicrophone() {
    if (!isOnMic || _status != RoomSessionStatus.joined) {
      return;
    }
    _micMuted = !_micMuted;
    final int index = _seats.indexWhere(
      (MicSeat seat) => seat.userName == '我',
    );
    if (index >= 0) {
      _seats = List<MicSeat>.of(_seats)
        ..[index] = _seats[index].copyWith(
          state: _micMuted
              ? MicSeatState.occupiedMuted
              : MicSeatState.occupied,
        );
    }
    notifyListeners();
  }

  void sendPublicMessage(String content) {
    final String normalized = content.trim();
    if (normalized.isEmpty || _status != RoomSessionStatus.joined) {
      return;
    }
    _messages.add(RoomMessage(sender: '我', content: normalized));
    notifyListeners();
  }

  Future<bool> sendGift({
    required String giftName,
    required String targetName,
    required int unitPrice,
    required int quantity,
  }) async {
    final int total = unitPrice * quantity;
    if (_status != RoomSessionStatus.joined || total > _giftBalance) {
      return false;
    }

    await Future<void>.delayed(const Duration(milliseconds: 220));
    _giftBalance -= total;
    _messages.add(
      RoomMessage(
        sender: '系统',
        content: '我送给 $targetName $giftName ×$quantity',
        isSystem: true,
      ),
    );
    notifyListeners();
    return true;
  }

  Future<void> simulateReconnect() async {
    if (_status != RoomSessionStatus.joined) {
      return;
    }
    _status = RoomSessionStatus.reconnecting;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _status = RoomSessionStatus.joined;
    _messages.add(
      const RoomMessage(
        sender: '系统',
        content: '已恢复连接。断线期间公屏消息可能未显示。',
        isSystem: true,
      ),
    );
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    if (_status == RoomSessionStatus.leaving ||
        _status == RoomSessionStatus.left) {
      return;
    }
    _status = RoomSessionStatus.leaving;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    _status = RoomSessionStatus.left;
    notifyListeners();
  }
}
