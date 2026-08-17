import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';

class MockRoomLifecycleRepository implements RoomLifecycleRepository {
  MockRoomLifecycleRepository();

  RoomConfiguration? _ownedRoom = const RoomConfiguration(
    roomId: '952700',
    roomCode: '952700',
    title: '周末松弛聊天局',
    topicTitle: '今晚话题',
    topicContent: '不赶时间，慢慢认识新朋友',
    welcomeMessage: '欢迎来到房间，请尊重彼此。',
    accessMode: RoomAccessMode.publicRoom,
    password: '',
    showInHall: true,
    autoLockMic: false,
    availability: RoomAvailability.open,
  );

  @override
  Future<RoomConfiguration?> fetchOwnedRoom() async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    return _ownedRoom;
  }

  @override
  Future<RoomConfiguration> fetchRoom(String roomId) async {
    await Future<void>.delayed(const Duration(milliseconds: 140));
    final RoomConfiguration? room = _ownedRoom;
    if (room == null || room.roomId != roomId) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '房间已失效或不存在',
      );
    }
    return room;
  }

  @override
  Future<RoomLifecycleSaveResult> saveRoom(
    RoomConfiguration configuration,
  ) async {
    _validate(configuration);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    final bool created = !configuration.hasExistingRoom;
    final String roomId = configuration.roomId ?? '952701';
    final String roomCode = configuration.roomCode ?? roomId;
    _ownedRoom = configuration.copyWith(
      roomId: roomId,
      roomCode: roomCode,
      availability: RoomAvailability.open,
    );
    return RoomLifecycleSaveResult(
      roomId: roomId,
      roomCode: roomCode,
      created: created,
    );
  }

  @override
  Future<void> closeRoom(String roomId) async {
    final RoomConfiguration? room = _ownedRoom;
    if (room == null || room.roomId != roomId) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '房间状态已变化，请刷新后重试',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _ownedRoom = room.copyWith(availability: RoomAvailability.closed);
  }

  @override
  Future<RoomLinkResolution> resolveRoomLink(String input) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final String normalized = _extractRoomId(input);
    if (normalized.isEmpty) {
      return RoomLinkResolution(
        status: RoomLinkStatus.invalid,
        input: input,
        message: '链接或房间号格式不正确',
      );
    }
    final RoomConfiguration? room = _ownedRoom;
    if (room != null &&
        (room.roomId == normalized || room.roomCode == normalized)) {
      if (!room.isOpen) {
        return RoomLinkResolution(
          status: RoomLinkStatus.closed,
          input: input,
          room: room,
          message: '房间已经关闭',
        );
      }
      return RoomLinkResolution(
        status: RoomLinkStatus.valid,
        input: input,
        room: room,
      );
    }
    if (normalized == '880217' || normalized == '660318') {
      return RoomLinkResolution(
        status: RoomLinkStatus.valid,
        input: input,
        room: RoomConfiguration(
          roomId: normalized,
          roomCode: normalized,
          title: normalized == '880217' ? '深夜温柔陪伴' : '下班后的松弛时刻',
          topicTitle: '当前话题',
          topicContent: '正在发生的实时语音聊天',
          welcomeMessage: '',
          accessMode: RoomAccessMode.publicRoom,
          password: '',
          showInHall: true,
          autoLockMic: false,
          availability: RoomAvailability.open,
        ),
      );
    }
    return RoomLinkResolution(
      status: RoomLinkStatus.unavailable,
      input: input,
      message: '目标房间不存在、已失效或暂不可进入',
    );
  }

  static void _validate(RoomConfiguration configuration) {
    final String title = configuration.title.trim();
    if (title.isEmpty || title.length > 64) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间名称需为 1–64 个字符',
      );
    }
    if (configuration.topicTitle.length > 64 ||
        configuration.topicContent.length > 500) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间话题内容过长',
      );
    }
    if (configuration.welcomeMessage.length > 300) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '欢迎语不能超过 300 个字符',
      );
    }
    if (configuration.accessMode == RoomAccessMode.password &&
        !RegExp(r'^\d{4}$').hasMatch(configuration.password)) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '密码房需要设置 4 位数字密码',
      );
    }
  }

  static String _extractRoomId(String input) {
    final String normalized = input.trim();
    if (RegExp(r'^\d{4,18}$').hasMatch(normalized)) {
      return normalized;
    }
    final Uri? uri = Uri.tryParse(normalized);
    if (uri == null) {
      return '';
    }
    final String? queryId = uri.queryParameters['roomId'];
    if (queryId != null && RegExp(r'^\d{4,18}$').hasMatch(queryId)) {
      return queryId;
    }
    if (uri.host == 'room' && uri.pathSegments.isNotEmpty) {
      final String candidate = uri.pathSegments.first;
      if (RegExp(r'^\d{4,18}$').hasMatch(candidate)) {
        return candidate;
      }
    }
    final List<String> segments = uri.pathSegments;
    final int roomIndex = segments.indexOf('room');
    if (roomIndex >= 0 && roomIndex + 1 < segments.length) {
      final String candidate = segments[roomIndex + 1];
      if (RegExp(r'^\d{4,18}$').hasMatch(candidate)) {
        return candidate;
      }
    }
    return '';
  }
}
