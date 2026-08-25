import 'dart:convert';

import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_models.dart';
import 'package:voice_social_app/features/room/domain/room_lifecycle_repository.dart';
import 'package:voice_social_app/features/room/data/room_write_guard.dart';
import 'package:voice_social_app/features/room/domain/room_intent_digest.dart';

class BackendRoomLifecycleRepository implements RoomLifecycleRepository {
  BackendRoomLifecycleRepository({
    required ApiClient apiClient,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  }) : _apiClient = apiClient,
       _routes = routes;

  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;
  final RoomWriteGuard _writeGuard = RoomWriteGuard(scope: 'room-lifecycle');

  @override
  final RoomLifecycleCapabilities capabilities =
      const RoomLifecycleCapabilities(
        supportsApprovalAccessMode: true,
        supportsTopicTitle: true,
        supportsAutoLockMic: true,
        supportsReopen: true,
      );

  static const int _ownedPageSize = 50;
  static const int _ownedPageCountCap = 100;

  @override
  Future<RoomConfiguration?> fetchOwnedRoom() async {
    final List<Map<String, Object?>> rooms = await _fetchOwnedRows();
    if (rooms.isEmpty) {
      return null;
    }
    return _configurationFromOwnerRow(rooms.first);
  }

  @override
  Future<RoomConfiguration> fetchRoom(String roomId) async {
    final String normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间 ID 不能为空',
      );
    }
    final List<Map<String, Object?>> rooms = await _fetchOwnedRows();
    Map<String, Object?>? ownerRow;
    for (final Map<String, Object?> candidate in rooms) {
      if (_roomIdFrom(candidate) == normalizedRoomId) {
        ownerRow = candidate;
        break;
      }
    }
    if (ownerRow == null) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '房间不存在、已失效或不属于当前账号',
      );
    }
    return _configurationFromOwnerRow(ownerRow);
  }

  Future<RoomConfiguration> _configurationFromOwnerRow(
    Map<String, Object?> ownerRow,
  ) async {
    final String id = _requiredOwnerText(ownerRow, 'roomId');
    final String accessMode = _accessMode(ownerRow);
    final String status = _requiredOwnerText(ownerRow, 'status');
    final RoomAvailability availability = _ownerAvailability(status);
    final bool showInHall = _requiredBool(ownerRow, 'hallVisible');
    final ApiResponse topicResponse = await _apiClient.get(
      _routes.roomTopic,
      query: <String, String>{'roomId': id},
    );
    final Map<String, Object?> topic = _asMap(topicResponse.data);
    final String topicRoomId = _requiredExactNonEmptyString(topic, 'roomId');
    if (topicRoomId != id) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间话题响应与房间 ID 不一致',
      );
    }
    final String topicContent = _requiredStringField(topic, 'topic');
    final String topicTitle = _requiredStringField(topic, 'topicTitle');
    final String welcomeMessage = _requiredStringField(topic, 'welcomeText');
    final bool canEdit = _requiredBool(topic, 'canEdit');
    final bool expectedCanEdit = availability == RoomAvailability.open;
    if (canEdit != expectedCanEdit) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间话题响应 canEdit 与房间状态不一致',
      );
    }
    final bool autoLockMic = _requiredBool(topic, 'autoLockMic');
    final int version = _requiredNonNegativeInt(topic, 'version');
    final String roomCode = _requiredOwnerText(ownerRow, 'roomCode');
    final String title = _requiredOwnerText(ownerRow, 'roomName');
    return RoomConfiguration(
      roomId: id,
      roomCode: roomCode,
      title: title,
      topicTitle: topicTitle,
      topicContent: topicContent,
      welcomeMessage: welcomeMessage,
      accessMode: _roomAccessMode(accessMode),
      // Password hashes are intentionally never returned to the client.
      password: '',
      passwordConfigured: accessMode == 'PASSWORD',
      showInHall: showInHall,
      autoLockMic: autoLockMic,
      availability: availability,
      coverUrl: _nonEmptyString(ownerRow['coverImgUrl']),
      version: version,
    );
  }

  Future<RoomConfiguration> _fetchPublicRoom(String roomId) async {
    final List<ApiResponse> responses = await Future.wait<ApiResponse>(
      <Future<ApiResponse>>[
        _apiClient.get(
          _routes.roomById,
          query: <String, String>{'roomId': roomId},
        ),
        _apiClient.get(
          _routes.roomTopic,
          query: <String, String>{'roomId': roomId},
        ),
      ],
    );
    final Map<String, Object?> info = _asMap(responses[0].data);
    final Map<String, Object?> topic = _asMap(responses[1].data);
    if (info.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间详情响应为空',
      );
    }
    final String id = _requiredExactNonEmptyString(info, 'roomId');
    if (id != roomId) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间详情响应与请求房间 ID 不一致',
      );
    }
    final String topicRoomId = _requiredExactNonEmptyString(topic, 'roomId');
    if (topicRoomId != id) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间话题响应与房间详情 ID 不一致',
      );
    }
    final String? explicitAccessMode = _nonEmptyString(info['accessMode']);
    final RoomAccessMode accessMode = explicitAccessMode == null
        ? RoomAccessMode.publicRoom
        : _roomAccessMode(explicitAccessMode.toUpperCase());
    final int version = _requiredNonNegativeInt(topic, 'version');
    return RoomConfiguration(
      roomId: id,
      roomCode:
          _nonEmptyString(info['roomCode']) ??
          _nonEmptyString(info['code']) ??
          id,
      title:
          _nonEmptyString(info['roomName']) ??
          _nonEmptyString(info['name']) ??
          '语音房',
      topicTitle: _requiredStringField(topic, 'topicTitle'),
      topicContent: _nonEmptyString(topic['topic']) ?? '',
      welcomeMessage: _nonEmptyString(topic['welcomeText']) ?? '',
      accessMode: accessMode,
      password: '',
      showInHall: _asBool(info['hallVisible']),
      autoLockMic: _requiredBool(topic, 'autoLockMic'),
      availability: _availability(info),
      coverUrl: _nonEmptyString(info['coverImgUrl']),
      version: version,
    );
  }

  Future<List<Map<String, Object?>>> _fetchOwnedRows() async {
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    int page = 1;
    int? totalPages;
    int? total;
    while (true) {
      final _OwnedRoomPage current = await _fetchOwnedPage(page);
      totalPages ??= current.pages;
      total ??= current.total;
      if (current.pages != totalPages || current.total != total) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '我的房间分页元数据在请求期间发生变化',
        );
      }
      if (current.pages > _ownedPageCountCap) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '我的房间分页超过安全上限',
        );
      }
      rows.addAll(current.items);
      if (current.pages == 0 || page >= current.pages) {
        break;
      }
      page += 1;
      if (page > _ownedPageCountCap) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '我的房间分页超出安全范围',
        );
      }
    }
    if (rows.length != total) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间分页记录数量与 total 不一致',
      );
    }
    return rows;
  }

  Future<_OwnedRoomPage> _fetchOwnedPage(int page) async {
    final ApiResponse response = await _apiClient.get(
      _routes.ownedRooms,
      query: <String, String>{
        'pageNum': '$page',
        'pageSize': '$_ownedPageSize',
      },
    );
    final Map<String, Object?> data = _asMap(response.data);
    if (data.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间分页响应为空',
      );
    }
    final List<Object?> list = _requiredObjectList(data['list']);
    final List<Object?> records = _requiredObjectList(data['records']);
    if (!_sameValue(list, records)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间分页 list 与 records 不一致',
      );
    }
    final int current = _requiredPageField(data, 'current', allowZero: false);
    final int pageSize = _requiredPageField(data, 'pageSize', allowZero: false);
    final int size = _requiredPageField(data, 'size', allowZero: false);
    final int total = _requiredPageField(data, 'total', allowZero: true);
    final int pages = _requiredPageField(data, 'pages', allowZero: true);
    if (current != page ||
        pageSize != _ownedPageSize ||
        size != _ownedPageSize ||
        pageSize != size) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间分页 current 或 pageSize 与请求不一致',
      );
    }
    final int expectedPages = total == 0
        ? 0
        : (total + pageSize - 1) ~/ pageSize;
    if (pages != expectedPages) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间分页 pages 与 total 不一致',
      );
    }
    final int expectedCount = pages == 0
        ? 0
        : page < pages
        ? pageSize
        : total - ((pages - 1) * pageSize);
    if (list.length != expectedCount) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间分页记录数量不安全',
      );
    }
    return _OwnedRoomPage(
      items: <Map<String, Object?>>[
        for (final Object? item in list) _requiredObjectMap(item),
      ],
      total: total,
      pages: pages,
    );
  }

  @override
  Future<RoomLifecycleSaveResult> saveRoom(
    RoomConfiguration configuration,
  ) async {
    _validate(configuration);
    final String? configuredRoomId = configuration.roomId?.trim();
    if (configuredRoomId != null && configuredRoomId.isNotEmpty) {
      _requireExpectedVersion(configuration.version, operation: '保存房间');
    }
    final String intent = _saveIntent(configuration);
    return _writeGuard.run<RoomLifecycleSaveResult>(
      intent: intent,
      action: (Map<String, String> headers) async {
        final String? roomId = configuration.roomId?.trim();
        if (roomId == null || roomId.isEmpty) {
          final ApiResponse response = await _apiClient.post(
            _routes.createRoom,
            headers: headers,
            body: _writeBody(configuration),
          );
          RoomWriteGuard.validateMutationResponse(response, operation: '创建房间');
          final Map<String, Object?> created = _asMap(response.data);
          return _saveResultFromCreateSnapshot(
            created,
            requested: configuration,
          );
        }
        int expectedVersion = _requireExpectedVersion(
          configuration.version,
          operation: '保存房间',
        );
        if (configuration.availability == RoomAvailability.closed) {
          expectedVersion = await _ensureRoomOpenForUpdate(
            roomId,
            expectedVersion,
            headers,
          );
        }
        // updateRoomInformation is authoritative for the complete editable
        // room configuration, including topic and welcomeText. Do not follow
        // it with the legacy setRoomTopics write: that second request could
        // partially overwrite a successful edit (especially for empty topic).
        final ApiResponse response = await _apiClient.patch(
          _routes.updateRoomInformation,
          headers: headers,
          body: <String, Object?>{
            ..._writeBody(configuration),
            'roomId': roomId,
            'expectedVersion': expectedVersion,
          },
        );
        RoomWriteGuard.validateMutationResponse(
          response,
          operation: '更新房间信息',
          requiredFields: <String>[
            'roomId',
            'topicTitle',
            'autoLockMic',
            'status',
            'rtcStatus',
            'imStatus',
            'providerInvocation',
            'version',
          ],
        );
        final Map<String, Object?> updateData = _asMap(response.data);
        final int updateVersion = _requiredNonNegativeInt(
          updateData,
          'version',
        );
        if (_requiredExactNonEmptyString(updateData, 'roomId') != roomId ||
            _requiredExactNonEmptyString(updateData, 'status') != 'OPEN' ||
            _requiredStringField(updateData, 'topicTitle') !=
                configuration.topicTitle.trim() ||
            _requiredBool(updateData, 'autoLockMic') !=
                configuration.autoLockMic ||
            _requiredExactNonEmptyString(updateData, 'rtcStatus') !=
                'VENDOR_BLOCKED' ||
            _requiredExactNonEmptyString(updateData, 'imStatus') !=
                'VENDOR_BLOCKED' ||
            _requiredBool(updateData, 'providerInvocation') ||
            updateVersion != _nextVersion(expectedVersion)) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '更新房间响应与请求配置不一致',
          );
        }
        final RoomConfiguration authoritative = await fetchRoom(roomId);
        if (authoritative.version != updateVersion) {
          throw const ApiException(
            kind: ApiFailureKind.conflict,
            message: '房间版本在保存后发生变化，请刷新后重新确认',
          );
        }
        if (authoritative.title != configuration.title.trim() ||
            authoritative.topicContent != configuration.topicContent.trim() ||
            authoritative.topicTitle != configuration.topicTitle.trim() ||
            authoritative.welcomeMessage !=
                configuration.welcomeMessage.trim() ||
            authoritative.accessMode != configuration.accessMode ||
            authoritative.showInHall != configuration.showInHall) {
          throw const ApiException(
            kind: ApiFailureKind.business,
            message: '房间信息已被其他操作更新，请刷新后重新确认',
          );
        }
        if (authoritative.autoLockMic != configuration.autoLockMic ||
            authoritative.availability != RoomAvailability.open) {
          throw const ApiException(
            kind: ApiFailureKind.business,
            message: '房间麦位或开放状态已变化，请刷新后重试',
          );
        }
        return RoomLifecycleSaveResult(
          roomId: roomId,
          roomCode: authoritative.roomCode ?? roomId,
          created: false,
        );
      },
    );
  }

  Future<int> _reopenRoom(
    String roomId,
    int expectedVersion,
    Map<String, String> headers,
  ) async {
    final ApiResponse response = await _apiClient.post(
      _routes.reopenRoom,
      headers: headers,
      body: <String, Object?>{
        'roomId': roomId,
        'expectedVersion': expectedVersion,
      },
    );
    RoomWriteGuard.validateMutationResponse(
      response,
      operation: '重新开放房间',
      requiredFields: <String>[
        'roomId',
        'status',
        'reopened',
        'providerInvocation',
        'version',
      ],
    );
    final Map<String, Object?> data = _asMap(response.data);
    final int version = _requiredNonNegativeInt(data, 'version');
    if (_requiredExactNonEmptyString(data, 'roomId') != roomId ||
        _requiredExactNonEmptyString(data, 'status') != 'OPEN' ||
        !_requiredBool(data, 'reopened') ||
        _requiredBool(data, 'providerInvocation') ||
        version != _nextVersion(expectedVersion)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '重新开放房间响应与请求不一致',
      );
    }
    return version;
  }

  Future<int> _ensureRoomOpenForUpdate(
    String roomId,
    int expectedVersion,
    Map<String, String> headers,
  ) async {
    try {
      return await _reopenRoom(roomId, expectedVersion, headers);
    } on ApiException catch (error, stackTrace) {
      if (error.code != 40933) {
        rethrow;
      }
      // A previous save can reopen successfully and then fail while updating
      // the editable configuration. The page still carries the last closed
      // snapshot in that case. Only treat the duplicate-open response as
      // recovered after an authoritative read proves the room is now open.
      final RoomConfiguration authoritative = await fetchRoom(roomId);
      if (authoritative.availability != RoomAvailability.open) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      return _requireExpectedVersion(
        authoritative.version,
        operation: '重新开放房间',
      );
    }
  }

  @override
  Future<void> closeRoom(String roomId, {int? expectedVersion}) async {
    final String normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间 ID 不能为空',
      );
    }
    final int version = _requireExpectedVersion(
      expectedVersion,
      operation: '关闭房间',
    );
    await _writeGuard.run<void>(
      intent: 'close:$normalizedRoomId:$version',
      action: (Map<String, String> headers) async {
        final ApiResponse response = await _apiClient.post(
          _routes.closeRoom,
          headers: headers,
          body: <String, Object?>{
            'roomId': normalizedRoomId,
            'expectedVersion': version,
          },
        );
        RoomWriteGuard.validateMutationResponse(
          response,
          operation: '关闭房间',
          requiredFields: <String>['roomId', 'status', 'closed', 'version'],
        );
        final Map<String, Object?> data = _asMap(response.data);
        final int responseVersion = _requiredNonNegativeInt(data, 'version');
        if (_requiredExactNonEmptyString(data, 'roomId') != normalizedRoomId ||
            _nonEmptyString(data['status'])?.toUpperCase() != 'CLOSED' ||
            !_asBool(data['closed']) ||
            (responseVersion != version &&
                responseVersion != _nextVersion(version))) {
          throw const ApiException(
            kind: ApiFailureKind.protocol,
            message: '关闭房间响应与请求状态不一致',
          );
        }
      },
    );
  }

  static String _saveIntent(RoomConfiguration configuration) {
    return roomIntentDigest(
      scope: 'room-lifecycle-save',
      fields: <String>[
        configuration.roomId?.trim() ?? 'new',
        configuration.title.trim(),
        configuration.topicTitle.trim(),
        configuration.topicContent.trim(),
        configuration.welcomeMessage.trim(),
        configuration.accessMode.name,
        configuration.password,
        configuration.passwordConfigured.toString(),
        configuration.showInHall.toString(),
        configuration.autoLockMic.toString(),
        configuration.availability.name,
        configuration.version?.toString() ?? 'missing',
      ],
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
      final RoomConfiguration room = await _fetchPublicRoom(roomId);
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
    final String state = _nonEmptyString(info['status'])?.toUpperCase() ?? '';
    if (state == 'CLOSED' || state == 'UNAVAILABLE') {
      return state == 'CLOSED'
          ? RoomAvailability.closed
          : RoomAvailability.unavailable;
    }
    if (state == 'OPEN') {
      return RoomAvailability.open;
    }
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

  static RoomAvailability _ownerAvailability(String status) {
    return switch (status) {
      'OPEN' => RoomAvailability.open,
      'CLOSED' => RoomAvailability.closed,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间 status 只能为 OPEN 或 CLOSED',
      ),
    };
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

  static String _extractRoomId(String input) {
    final String normalized = input.trim();
    if (_isRoomIdentifier(normalized)) {
      return normalized;
    }
    final Uri? uri = Uri.tryParse(normalized);
    if (uri == null) {
      return '';
    }
    final String? queryId = uri.queryParameters['roomId'];
    if (queryId != null && _isRoomIdentifier(queryId)) {
      return queryId;
    }
    if (uri.host == 'room' && uri.pathSegments.isNotEmpty) {
      final String candidate = uri.pathSegments.first;
      if (_isRoomIdentifier(candidate)) {
        return candidate;
      }
    }
    final List<String> segments = uri.pathSegments;
    final int roomIndex = segments.indexOf('room');
    if (roomIndex >= 0 && roomIndex + 1 < segments.length) {
      final String candidate = segments[roomIndex + 1];
      if (_isRoomIdentifier(candidate)) {
        return candidate;
      }
    }
    return '';
  }

  static bool _isRoomIdentifier(String value) =>
      RegExp(r'^\d{4,18}$').hasMatch(value) ||
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
        r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};

  static Map<String, Object?> _requiredObjectMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    throw const ApiException(
      kind: ApiFailureKind.protocol,
      message: '我的房间分页记录结构无法识别',
    );
  }

  static List<Object?> _requiredObjectList(Object? value) {
    if (value is List<Object?>) {
      return value;
    }
    throw const ApiException(
      kind: ApiFailureKind.protocol,
      message: '我的房间分页缺少 list 或 records',
    );
  }

  static int _requiredPageField(
    Map<String, Object?> data,
    String field, {
    required bool allowZero,
  }) {
    final int? value = _asInt(data[field]);
    if (value == null || (allowZero ? value < 0 : value <= 0)) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间分页字段 $field 无效',
      );
    }
    return value;
  }

  static String _requiredOwnerText(Map<String, Object?> data, String field) {
    return _requiredExactNonEmptyString(data, field);
  }

  static String _requiredStringField(
    Map<String, Object?> data,
    String field, {
    bool allowEmpty = true,
  }) {
    final Object? value = data[field];
    if (value is! String) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应字段 $field 必须为字符串',
      );
    }
    final String normalized = value.trim();
    if (!allowEmpty && normalized.isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应字段 $field 不能为空',
      );
    }
    return normalized;
  }

  static String _requiredExactNonEmptyString(
    Map<String, Object?> data,
    String field,
  ) {
    final Object? value = data[field];
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应字段 $field 必须为无空白非空字符串',
      );
    }
    return value;
  }

  static bool _requiredBool(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! bool) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应字段 $field 必须为布尔值',
      );
    }
    return value;
  }

  static int _requiredNonNegativeInt(Map<String, Object?> data, String field) {
    final Object? value = data[field];
    if (value is! int || value < 0) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '响应字段 $field 必须为非负整数',
      );
    }
    return value;
  }

  static int _requireExpectedVersion(
    int? version, {
    required String operation,
  }) {
    if (version == null || version < 0) {
      throw ApiException(
        kind: ApiFailureKind.validation,
        message: '$operation 缺少有效的房间版本，请刷新后重试',
      );
    }
    return version;
  }

  static int _nextVersion(int version) => version + 1;

  static bool _sameValue(Object? left, Object? right) {
    try {
      return jsonEncode(left) == jsonEncode(right);
    } on Object {
      return false;
    }
  }

  static Map<String, Object?> _writeBody(RoomConfiguration configuration) {
    final String accessMode = switch (configuration.accessMode) {
      RoomAccessMode.password => 'PASSWORD',
      RoomAccessMode.approval => 'APPROVAL',
      RoomAccessMode.publicRoom => 'PUBLIC',
    };
    return <String, Object?>{
      'roomName': configuration.title.trim(),
      'topicTitle': configuration.topicTitle.trim(),
      'topic': configuration.topicContent.trim(),
      'welcomeText': configuration.welcomeMessage.trim(),
      'accessMode': accessMode,
      'hallVisible': configuration.showInHall,
      'autoLockMic': configuration.autoLockMic,
      if (accessMode == 'PASSWORD' && configuration.password.isNotEmpty)
        'password': configuration.password,
    };
  }

  static RoomLifecycleSaveResult _saveResultFromCreateSnapshot(
    Map<String, Object?> data, {
    required RoomConfiguration requested,
  }) {
    final String roomId = _requiredExactNonEmptyString(data, 'roomId');
    final String roomCode = _requiredExactNonEmptyString(data, 'roomCode');
    final String roomName = _requiredExactNonEmptyString(data, 'roomName');
    final String topicTitle = _requiredStringField(data, 'topicTitle');
    final String topic = _requiredStringField(data, 'topic');
    final String welcomeText = _requiredStringField(data, 'welcomeText');
    final String status = _requiredExactNonEmptyString(data, 'status');
    if (status != 'OPEN') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '创建房间响应 status 必须为 OPEN',
      );
    }
    final String accessMode = _requiredExactNonEmptyString(data, 'accessMode');
    _strictRoomAccessMode(accessMode);
    final bool hallVisible = _requiredBool(data, 'hallVisible');
    final bool autoLockMic = _requiredBool(data, 'autoLockMic');
    _requiredNonNegativeInt(data, 'version');
    final bool created = _requiredBool(data, 'created');
    final bool reused = _requiredBool(data, 'reused');
    if (created == reused) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '创建房间响应 created 与 reused 必须互斥',
      );
    }
    if (_requiredExactNonEmptyString(data, 'rtcStatus') != 'VENDOR_BLOCKED') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '创建房间响应 rtcStatus 必须为 VENDOR_BLOCKED',
      );
    }
    if (_requiredExactNonEmptyString(data, 'imStatus') != 'VENDOR_BLOCKED') {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '创建房间响应 imStatus 必须为 VENDOR_BLOCKED',
      );
    }
    if (_requiredBool(data, 'providerInvocation')) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '创建房间响应 providerInvocation 必须为 false',
      );
    }
    if (created &&
        (roomName != requested.title.trim() ||
            topic != requested.topicContent.trim() ||
            topicTitle != requested.topicTitle.trim() ||
            welcomeText != requested.welcomeMessage.trim() ||
            accessMode != _accessModeValue(requested.accessMode) ||
            hallVisible != requested.showInHall ||
            autoLockMic != requested.autoLockMic)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '创建房间响应与提交配置不一致',
      );
    }
    return RoomLifecycleSaveResult(
      roomId: roomId,
      roomCode: roomCode,
      created: created,
    );
  }

  static String _accessModeValue(RoomAccessMode accessMode) {
    return switch (accessMode) {
      RoomAccessMode.publicRoom => 'PUBLIC',
      RoomAccessMode.password => 'PASSWORD',
      RoomAccessMode.approval => 'APPROVAL',
    };
  }

  static RoomAccessMode _strictRoomAccessMode(String value) {
    return switch (value) {
      'PUBLIC' => RoomAccessMode.publicRoom,
      'PASSWORD' => RoomAccessMode.password,
      'APPROVAL' => RoomAccessMode.approval,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '创建房间响应 accessMode 无法识别',
      ),
    };
  }

  static String _roomIdFrom(Map<String, Object?> data) =>
      _nonEmptyString(data['roomId']) ??
      _nonEmptyString(data['roomIdStr']) ??
      _nonEmptyString(data['id']) ??
      '';

  static String _accessMode(Map<String, Object?> info) {
    final String? value = _nonEmptyString(info['accessMode']);
    if (value == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '我的房间配置缺少 accessMode',
      );
    }
    return value.toUpperCase();
  }

  static RoomAccessMode _roomAccessMode(String value) {
    return switch (value.toUpperCase()) {
      'PUBLIC' => RoomAccessMode.publicRoom,
      'PASSWORD' => RoomAccessMode.password,
      'APPROVAL' => RoomAccessMode.approval,
      _ => throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '房间 accessMode 无法识别',
      ),
    };
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return switch (value?.toString().trim().toLowerCase()) {
      'true' || '1' || 'yes' => true,
      _ => false,
    };
  }

  static String? _nonEmptyString(Object? value) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}

class _OwnedRoomPage {
  const _OwnedRoomPage({
    required this.items,
    required this.total,
    required this.pages,
  });

  final List<Map<String, Object?>> items;
  final int total;
  final int pages;
}
