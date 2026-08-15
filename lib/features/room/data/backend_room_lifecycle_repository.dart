import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';

class BackendRoomLifecycleRepository implements RoomLifecycleRepository {
  BackendRoomLifecycleRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  })  : _apiClient = apiClient,
        _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;

  @override
  Future<RoomConfiguration?> fetchOwnedRoom() async {
    final ApiResponse response = await _apiClient.get(_routes.ownedRooms);
    final List<Object?> rooms = _asList(response.data);
    if (rooms.isEmpty) {
      return null;
    }
    final Object? first = rooms.first;
    if (first is! Map<String, Object?>) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间列表结构无法识别',
      );
    }
    final String roomId = _nonEmptyString(first['id']) ??
        _nonEmptyString(first['roomId']) ??
        '';
    if (roomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间缺少房间 ID',
      );
    }
    return fetchRoom(roomId);
  }

  @override
  Future<RoomConfiguration> fetchRoom(String roomId) async {
    final List<ApiResponse> responses = await Future.wait<ApiResponse>(
      <Future<ApiResponse>>[
        _apiClient.get(
          _routes.roomById,
          query: <String, String>{'id': roomId},
        ),
        _apiClient.get(
          _routes.roomTopic,
          query: <String, String>{'roomId': roomId},
        ),
      ],
    );
    final Map<String, Object?> info = _asMap(responses[0].data);
    final Map<String, Object?> topic = _asMap(responses[1].data);
    final String id = _nonEmptyString(info['idStr']) ??
        _nonEmptyString(info['id']) ??
        roomId;
    return RoomConfiguration(
      roomId: id,
      roomCode: _nonEmptyString(info['code']) ?? id,
      title: _nonEmptyString(info['name']) ?? '语音房',
      topicTitle: _nonEmptyString(topic['topicTitle']) ?? '',
      topicContent: _nonEmptyString(topic['topicContent']) ?? '',
      welcomeMessage: _nonEmptyString(info['welcomeWord']) ?? '',
      accessMode: _asInt(info['isLock']) == 1
          ? RoomAccessMode.password
          : RoomAccessMode.publicRoom,
      password: _nonEmptyString(info['password']) ?? '',
      showInHall: _asInt(info['isShow']) == 1,
      autoLockMic: _asInt(info['isAutoLockMic']) == 1,
      availability: _availability(info),
      coverUrl: _nonEmptyString(info['coverImgUrl']),
    );
  }

  @override
  Future<RoomLifecycleSaveResult> saveRoom(
    RoomConfiguration configuration,
  ) async {
    _validate(configuration);
    final String? roomId = configuration.roomId;
    if (roomId == null || roomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '当前后端按注册时自动创建个人房运行，尚未确认新增普通房接口',
      );
    }
    await _apiClient.put(
      _routes.updateRoomInformation,
      body: <String, Object?>{
        'id': int.tryParse(roomId) ?? roomId,
        'name': configuration.title.trim(),
        'isShow': configuration.showInHall ? 1 : 0,
        'isLock': configuration.accessMode == RoomAccessMode.password ? 1 : 0,
        'password': configuration.accessMode == RoomAccessMode.password
            ? configuration.password
            : '',
        'welcomeWord': configuration.welcomeMessage.trim(),
      },
    );
    await _apiClient.patch(
      _routes.updateRoomTopic,
      body: <String, Object?>{
        'roomId': int.tryParse(roomId) ?? roomId,
        'topicTitle': configuration.topicTitle.trim(),
        'topicContent': configuration.topicContent.trim(),
      },
    );
    final RoomConfiguration authoritative = await fetchRoom(roomId);
    if (authoritative.title != configuration.title.trim() ||
        authoritative.topicTitle != configuration.topicTitle.trim() ||
        authoritative.topicContent != configuration.topicContent.trim()) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '房间信息已被其他操作更新，请刷新后重新确认',
      );
    }
    return RoomLifecycleSaveResult(
      roomId: roomId,
      roomCode: authoritative.roomCode ?? roomId,
      created: false,
    );
  }

  @override
  Future<void> closeRoom(String roomId) async {
    throw const ApiException(
      kind: ApiFailureKind.configuration,
      message: '尚未确认服务端关闭房间接口，当前版本不会用退出房间代替关闭房间',
    );
  }

  @override
  Future<RoomLinkResolution> resolveRoomLink(String input) async {
    final String roomId = _extractRoomId(input);
    if (roomId.isEmpty) {
      return RoomLinkResolution(
        status: RoomLinkStatus.invalid,
        input: input,
        message: '链接或房间号格式不正确',
      );
    }
    try {
      final RoomConfiguration room = await fetchRoom(roomId);
      if (!room.isOpen) {
        return RoomLinkResolution(
          status: RoomLinkStatus.closed,
          input: input,
          room: room,
          message: '房间已经关闭或不可进入',
        );
      }
      return RoomLinkResolution(
        status: RoomLinkStatus.valid,
        input: input,
        room: room,
      );
    } on ApiException catch (error) {
      if (error.kind == ApiFailureKind.business ||
          error.kind == ApiFailureKind.validation) {
        return RoomLinkResolution(
          status: RoomLinkStatus.unavailable,
          input: input,
          message: error.message,
        );
      }
      rethrow;
    }
  }

  static RoomAvailability _availability(Map<String, Object?> info) {
    final int status = _asInt(info['status']) ?? 0;
    final int sysStatus = _asInt(info['sysStatus']) ?? 0;
    if (status == 2 || sysStatus == 2) {
      return RoomAvailability.unavailable;
    }
    if (sysStatus == 1) {
      return RoomAvailability.closed;
    }
    return RoomAvailability.open;
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
        configuration.topicContent.length > 500 ||
        configuration.welcomeMessage.length > 300) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间话题或欢迎语超过长度限制',
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

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};

  static List<Object?> _asList(Object? value) =>
      value is List<Object?> ? value : <Object?>[];

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _nonEmptyString(Object? value) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
