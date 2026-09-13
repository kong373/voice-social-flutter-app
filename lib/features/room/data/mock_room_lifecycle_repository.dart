import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_lifecycle_repository.dart'
    show RoomReopenRepository;
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';

class MockRoomLifecycleRepository
    implements
        RoomLifecycleRepository,
        RoomReopenRepository,
        OwnedRoomSelectionRepository {
  MockRoomLifecycleRepository({
    List<RoomConfiguration>? initialRooms,
    this.roomLimit = 1,
  }) : _rooms = {
         for (final room in initialRooms ?? const [_defaultRoom])
           room.roomId!: room,
       };

  final int roomLimit;
  final Map<String, RoomConfiguration> _rooms;
  int _nextRoomId = 952701;

  @override
  final RoomLifecycleCapabilities capabilities =
      const RoomLifecycleCapabilities(
        supportsApprovalAccessMode: false,
        supportsTopicTitle: true,
        supportsAutoLockMic: true,
        supportsReopen: true,
      );

  static const RoomConfiguration _defaultRoom = RoomConfiguration(
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
    version: 0,
  );

  @override
  Future<List<OwnedRoomSummary>> fetchOwnedRooms() async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    return List<OwnedRoomSummary>.unmodifiable(
      _rooms.values.map(
        (room) => OwnedRoomSummary(
          roomId: room.roomId!,
          roomCode: room.roomCode!,
          title: room.title,
          availability: room.availability,
          accessMode: room.accessMode,
        ),
      ),
    );
  }

  @override
  Future<RoomConfiguration?> fetchOwnedRoom() async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    return _rooms.values.firstOrNull;
  }

  @override
  Future<RoomConfiguration> fetchRoom(String roomId) async {
    await Future<void>.delayed(const Duration(milliseconds: 140));
    final RoomConfiguration? room = _rooms[roomId];
    if (room == null) {
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
    if (configuration.coverImageChange.changed ||
        configuration.backgroundImageChange.changed) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '演示环境不保存房间图片，不生成虚假上传回执',
      );
    }
    _validate(configuration);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    final bool created = !configuration.hasExistingRoom;
    if (created && _rooms.length >= roomLimit) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40998,
        message: '已达到公会可建房数量上限',
      );
    }
    while (_rooms.containsKey('$_nextRoomId')) {
      _nextRoomId++;
    }
    final String roomId = configuration.roomId ?? '${_nextRoomId++}';
    if (!created && !_rooms.containsKey(roomId)) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '房间不属于当前账号',
      );
    }
    final String roomCode = configuration.roomCode ?? roomId;
    _rooms[roomId] = configuration.copyWith(
      roomId: roomId,
      roomCode: roomCode,
      availability: created
          ? RoomAvailability.open
          : configuration.availability,
      version: created
          ? (configuration.version ?? 0)
          : (configuration.version ?? 0) + 1,
    );
    return RoomLifecycleSaveResult(
      roomId: roomId,
      roomCode: roomCode,
      created: created,
    );
  }

  @override
  Future<void> closeRoom(String roomId, {int? expectedVersion}) async {
    final RoomConfiguration? room = _rooms[roomId];
    if (room == null) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '房间状态已变化，请刷新后重试',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _rooms[roomId] = room.copyWith(
      availability: RoomAvailability.closed,
      version: (expectedVersion ?? room.version ?? 0) + 1,
    );
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
    final RoomConfiguration? room = _rooms.values
        .where(
          (room) => room.roomId == normalized || room.roomCode == normalized,
        )
        .firstOrNull;
    if (room != null) {
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
          version: 0,
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
    if (configuration.accessMode == RoomAccessMode.approval) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请选择公开房或密码房后保存',
      );
    }
    final String title = configuration.title.trim();
    if (title.isEmpty || title.length > 64) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间名称需为 1–64 个字符',
      );
    }
    final String topicTitle = configuration.topicTitle.trim();
    final String topicContent = configuration.topicContent.trim();
    final String welcomeMessage = configuration.welcomeMessage.trim();
    if (topicTitle.length > 64 || topicContent.length > 240) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间话题内容过长',
      );
    }
    if (welcomeMessage.length > 240) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '欢迎语不能超过 240 个字符',
      );
    }
    if (configuration.accessMode == RoomAccessMode.password &&
        ((!configuration.passwordConfigured &&
                configuration.password.isEmpty) ||
            (configuration.password.isNotEmpty &&
                !RegExp(r'^\d{4}$').hasMatch(configuration.password)))) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '密码房需要设置 4 位数字密码',
      );
    }
  }

  @override
  Future<void> reopenRoom(String roomId, {required int expectedVersion}) async {
    final room = await fetchRoom(roomId);
    if (room.version != expectedVersion || room.isOpen) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '房间状态已变化，请刷新后重试',
      );
    }
    if (room.accessMode == RoomAccessMode.approval) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '请先保存公开房或密码房设置',
      );
    }
    _rooms[roomId] = room.copyWith(
      availability: RoomAvailability.open,
      version: expectedVersion + 1,
    );
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
