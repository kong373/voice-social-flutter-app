import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

class BackendMicSeat {
  const BackendMicSeat({
    required this.index,
    required this.status,
    this.userId,
    this.userName,
    this.avatarUrl,
    this.userRoleCode,
    this.isOnline = true,
    this.isSpeaking = false,
  });

  final int index;
  final int status;
  final int? userId;
  final String? userName;
  final String? avatarUrl;
  final int? userRoleCode;
  final bool isOnline;
  final bool isSpeaking;

  bool get isOccupied => status == 3 || status == 4;
}

class FixedEightSeatAdapter {
  const FixedEightSeatAdapter();

  List<MicSeat> adapt(List<BackendMicSeat> backendSeats) {
    // Keep the public class name for source compatibility. Canonical S02 is
    // 1..9; an explicit zero identifies the old 0..8 wire contract only.
    final bool legacy = backendSeats.any((seat) => seat.index == 0);
    final Map<int, BackendMicSeat> regular = {};
    for (final seat in backendSeats) {
      final number = seat.index + (legacy ? 1 : 0);
      if (number < 1 || number > 9 || regular.containsKey(number)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '麦位编号重复或混用了新旧九麦契约',
        );
      }
      regular[number] = seat;
    }
    return List<MicSeat>.unmodifiable([
      for (int uiIndex = 1; uiIndex <= 9; uiIndex += 1)
        _toUiSeat(
          uiIndex: uiIndex,
          backend:
              regular[uiIndex] ??
              BackendMicSeat(index: uiIndex - (legacy ? 1 : 0), status: 0),
        ),
    ]);
  }

  static MicSeat _toUiSeat({
    required int uiIndex,
    required BackendMicSeat backend,
  }) {
    return MicSeat(
      number: uiIndex,
      backendIndex: backend.index,
      state: _stateFromBackend(backend.status),
      userId: backend.userId,
      userName: backend.userName,
      avatarUrl: backend.avatarUrl,
      userRole: _roleFromBackend(backend.userRoleCode),
      isOnline: backend.isOccupied && backend.isOnline,
      isSpeaking: backend.isOccupied && backend.isOnline && backend.isSpeaking,
    );
  }

  static MicSeatState _stateFromBackend(int status) {
    switch (status) {
      case 1:
        return MicSeatState.locked;
      case 2:
        return MicSeatState.mutedAvailable;
      case 3:
        return MicSeatState.occupied;
      case 4:
        return MicSeatState.occupiedMuted;
      case 0:
      default:
        return MicSeatState.available;
    }
  }

  static RoomRole _roleFromBackend(int? role) {
    switch (role) {
      case 3:
        return RoomRole.owner;
      case 1:
      case 5:
        return RoomRole.moderator;
      case 2:
      case 4:
        return RoomRole.platformModerator;
      default:
        return RoomRole.listener;
    }
  }
}
