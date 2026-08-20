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
  });

  final int index;
  final int status;
  final int? userId;
  final String? userName;
  final String? avatarUrl;
  final int? userRoleCode;

  bool get isOccupied => status == 3 || status == 4;
}

class FixedEightSeatAdapter {
  const FixedEightSeatAdapter();

  List<MicSeat> adapt(List<BackendMicSeat> backendSeats) {
    final Map<int, BackendMicSeat> regular = <int, BackendMicSeat>{
      for (final BackendMicSeat seat in backendSeats)
        if (seat.index >= 1 && seat.index <= 8) seat.index: seat,
    };
    final BackendMicSeat? ownerSeat = _findSeat(backendSeats, 0);

    final List<MicSeat> result = <MicSeat>[
      for (int uiIndex = 1; uiIndex <= 8; uiIndex += 1)
        _toUiSeat(
          uiIndex: uiIndex,
          backend:
              regular[uiIndex] ?? BackendMicSeat(index: uiIndex, status: 0),
        ),
    ];

    if (ownerSeat == null || !ownerSeat.isOccupied) {
      return List<MicSeat>.unmodifiable(result);
    }

    final int availableIndex = result.indexWhere(
      (MicSeat seat) => seat.state == MicSeatState.available,
    );
    if (availableIndex < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '后端同时返回了 9 个占用麦位，无法安全映射为固定 8 麦',
      );
    }
    result[availableIndex] = _toUiSeat(
      uiIndex: result[availableIndex].number,
      backend: ownerSeat,
    );
    return List<MicSeat>.unmodifiable(result);
  }

  static BackendMicSeat? _findSeat(List<BackendMicSeat> seats, int index) {
    for (final BackendMicSeat seat in seats) {
      if (seat.index == index) {
        return seat;
      }
    }
    return null;
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
