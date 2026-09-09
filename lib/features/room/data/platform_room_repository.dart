import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';

class PlatformRoom {
  const PlatformRoom({
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    required this.ownerUserId,
    required this.status,
    required this.version,
    required this.accessMode,
  });
  final String roomId, roomCode, roomName, status, accessMode;
  final int ownerUserId, version;
}

class PlatformRoomPageResult {
  const PlatformRoomPageResult(this.rooms, this.current, this.hasMore);
  final List<PlatformRoom> rooms;
  final int current;
  final bool hasMore;
}

class PendingRoomLifecycle {
  PendingRoomLifecycle(this.roomId, this.expectedVersion, this.reopen)
    : requestId =
          'platform-room-${List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join()}',
      body = Map.unmodifiable({
        'roomId': roomId,
        'expectedVersion': expectedVersion,
      });
  final String roomId, requestId;
  final int expectedVersion;
  final bool reopen;
  final Map<String, Object?> body;
}

abstract interface class PlatformRoomRepository {
  (int, int) get identity;
  Listenable get identityChanges;
  PendingRoomLifecycle? get pending;
  Future<bool> authority();
  Future<PlatformRoomPageResult> list({int page = 1, String keyword = ''});
  Future<void> control({
    required String roomId,
    required int version,
    required bool reopen,
  });
}

/// Account-scoped in-memory journal. Unknown commands survive route disposal
/// and logout; in-flight futures are never shared across identity generations.
class BackendPlatformRoomRepository implements PlatformRoomRepository {
  BackendPlatformRoomRepository({
    required ApiClient apiClient,
    required (int, int) Function() identity,
    required this.identityChanges,
    BackendRouteCatalog routes = const BackendRouteCatalog(),
  }) : _api = apiClient,
       _identity = identity,
       _routes = routes;
  final ApiClient _api;
  final (int, int) Function() _identity;
  final BackendRouteCatalog _routes;
  @override
  final Listenable identityChanges;
  @override
  (int, int) get identity => _identity();
  final Map<int, PendingRoomLifecycle> _pending = {};
  final Map<(int, int), Future<void>> _flights = {};
  @override
  PendingRoomLifecycle? get pending => _pending[identity.$1];

  void _require((int, int) original) {
    if (original.$1 <= 0 || identity != original) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '账号已变化，请返回原账号确认房间操作',
      );
    }
  }

  static Never _invalid() => throw const ApiException(
    kind: ApiFailureKind.protocol,
    message: '平台房间响应无效',
  );
  @override
  Future<bool> authority() async {
    final original = identity;
    _require(original);
    final response = await _api.get(_routes.platformRoomAuthority);
    _require(original);
    final data = response.data;
    if (data is! Map || data['platformStaff'] is! bool) _invalid();
    return data['platformStaff'] as bool;
  }

  @override
  Future<PlatformRoomPageResult> list({
    int page = 1,
    String keyword = '',
  }) async {
    final original = identity;
    _require(original);
    if (page < 1 || keyword.length > 120) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '平台房间搜索条件无效',
      );
    }
    if (!await authority()) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        httpStatus: 403,
        message: '无平台房间管理权限',
      );
    }
    _require(original);
    final response = await _api.get(
      _routes.platformRoomList,
      query: {'pageNum': '$page', 'pageSize': '20', 'keyword': keyword},
    );
    _require(original);
    final data = response.data;
    if (data is! Map ||
        data['list'] is! List ||
        data['records'] is! List ||
        jsonEncode(data['list']) != jsonEncode(data['records']) ||
        data['current'] is! int ||
        data['pageSize'] is! int ||
        data['current'] != page ||
        data['pageSize'] != 20 ||
        data['total'] is! int ||
        (data['total'] as int) < 0 ||
        data['pages'] is! int ||
        data['pages'] != ((data['total'] as int) + 19) ~/ 20 ||
        data['hasMore'] is! bool ||
        data['hasMore'] != (page < (data['pages'] as int)))
      _invalid();
    final rows = data['list'] as List;
    final total = data['total'] as int;
    if (rows.length != min(20, max(0, total - (page - 1) * 20))) _invalid();
    final rooms = <PlatformRoom>[];
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map ||
          row['roomId'] is! String ||
          !RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(row['roomId'] as String) ||
          !seen.add(row['roomId'] as String) ||
          row['roomCode'] is! String ||
          row['roomName'] is! String ||
          (row['roomName'] as String).isEmpty ||
          row['ownerUserId'] is! int ||
          (row['ownerUserId'] as int) <= 0 ||
          row['version'] is! int ||
          (row['version'] as int) < 0 ||
          !const ['OPEN', 'CLOSED'].contains(row['status']) ||
          !const ['PUBLIC', 'PASSWORD'].contains(row['accessMode']))
        _invalid();
      rooms.add(
        PlatformRoom(
          roomId: row['roomId'] as String,
          roomCode: row['roomCode'] as String,
          roomName: row['roomName'] as String,
          ownerUserId: row['ownerUserId'] as int,
          status: row['status'] as String,
          version: row['version'] as int,
          accessMode: row['accessMode'] as String,
        ),
      );
    }
    return PlatformRoomPageResult(
      List.unmodifiable(rooms),
      page,
      data['hasMore'] as bool,
    );
  }

  @override
  Future<void> control({
    required String roomId,
    required int version,
    required bool reopen,
  }) {
    final original = identity;
    _require(original);
    if (roomId.isEmpty || version < 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间和确认版本无效',
      );
    }
    final prior = pending;
    if (prior != null &&
        (prior.roomId != roomId ||
            prior.expectedVersion != version ||
            prior.reopen != reopen)) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '请先确认原房间操作，不能更换房间、版本或动作',
      );
    }
    final flight = _flights[original];
    if (flight != null) return flight;
    final command = prior ?? PendingRoomLifecycle(roomId, version, reopen);
    _pending[original.$1] = command;
    late final Future<void> work;
    work = (() async {
      try {
        final response = await _api.postBoundToIdentity(
          reopen ? _routes.reopenRoom : _routes.closeRoom,
          requireIdentity: () => _require(original),
          headers: {'X-Request-Id': command.requestId},
          body: command.body,
        );
        _require(original);
        final data = response.data;
        if (data is! Map ||
            data['roomId'] != roomId ||
            data['status'] != (reopen ? 'OPEN' : 'CLOSED') ||
            data[reopen ? 'reopened' : 'closed'] != true ||
            data['version'] is! int ||
            ((data['version'] != version + 1) &&
                (reopen || data['version'] != version)) ||
            (reopen && data['providerInvocation'] != false))
          _invalid();
        if (identical(_pending[original.$1], command))
          _pending.remove(original.$1);
      } catch (error) {
        // A rejection of an initial attempt proves no write. Once unknown,
        // even a later 403/404/409 cannot prove the original never committed.
        if (prior == null &&
            original == identity &&
            error is ApiException &&
            (error.kind == ApiFailureKind.validation ||
                error.kind == ApiFailureKind.business ||
                error.kind == ApiFailureKind.forbidden ||
                error.kind == ApiFailureKind.unauthorized ||
                error.kind == ApiFailureKind.conflict) &&
            error.code != 40901 &&
            error.code != 40902) {
          if (identical(_pending[original.$1], command))
            _pending.remove(original.$1);
        }
        rethrow;
      }
    })();
    _flights[original] = work;
    work.then<void>(
      (_) {
        if (identical(_flights[original], work)) _flights.remove(original);
      },
      onError: (Object _, StackTrace __) {
        if (identical(_flights[original], work)) _flights.remove(original);
      },
    );
    return work;
  }
}

/// No platform binding is fabricated in demo mode.
class UnboundPlatformRoomRepository implements PlatformRoomRepository {
  UnboundPlatformRoomRepository(this.identityChanges, this._identity);
  @override
  final Listenable identityChanges;
  final (int, int) Function() _identity;
  @override
  (int, int) get identity => _identity();
  @override
  PendingRoomLifecycle? get pending => null;
  @override
  Future<bool> authority() async => false;
  @override
  Future<PlatformRoomPageResult> list({
    int page = 1,
    String keyword = '',
  }) async => _denied();
  @override
  Future<void> control({
    required String roomId,
    required int version,
    required bool reopen,
  }) async => _denied();
  Never _denied() => throw const ApiException(
    kind: ApiFailureKind.business,
    httpStatus: 403,
    message: '当前账号未绑定平台房间管理权限',
  );
}
