import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';

class MockRoomOperationsRepository implements RoomOperationsRepository {
  MockRoomOperationsRepository({
    this.micCoordinationMode = MicCoordinationMode.approval,
  });

  @override
  final MicCoordinationMode micCoordinationMode;

  RoomTopic _topic = const RoomTopic(
    title: '今晚话题',
    content: '最近让你觉得被治愈的一件小事',
    version: 0,
  );

  final List<RoomMember> _members = <RoomMember>[
    const RoomMember(
      userId: 20001,
      name: '房主 · 鹿屿',
      role: RoomRole.owner,
      presence: RoomMemberPresence.onMic,
      seatNumber: 1,
      wealthLevel: 18,
    ),
    const RoomMember(
      userId: 20002,
      name: '南风',
      role: RoomRole.speaker,
      presence: RoomMemberPresence.onMic,
      seatNumber: 2,
      isMuted: true,
    ),
    const RoomMember(
      userId: 20003,
      name: '晚星',
      role: RoomRole.speaker,
      presence: RoomMemberPresence.onMic,
      seatNumber: 3,
    ),
    const RoomMember(
      userId: 20004,
      name: '清禾',
      role: RoomRole.moderator,
      presence: RoomMemberPresence.listener,
      charmLevel: 12,
    ),
    const RoomMember(
      userId: 20005,
      name: '阿岚',
      role: RoomRole.listener,
      presence: RoomMemberPresence.listener,
    ),
    const RoomMember(
      userId: 20006,
      name: '小岛',
      role: RoomRole.listener,
      presence: RoomMemberPresence.listener,
    ),
    const RoomMember(
      userId: 20007,
      name: '夏至',
      role: RoomRole.listener,
      presence: RoomMemberPresence.listener,
    ),
    const RoomMember(
      userId: 20008,
      name: '云深',
      role: RoomRole.listener,
      presence: RoomMemberPresence.listener,
    ),
  ];

  final List<MicAccessRequest> _requests = <MicAccessRequest>[];

  @override
  Future<RoomMemberPage> fetchOnlineMembers({
    required String roomId,
    required int page,
    int pageSize = 20,
  }) async {
    final int start = (page - 1) * pageSize;
    final int safeStart = start < 0
        ? 0
        : start > _members.length
        ? _members.length
        : start;
    final int proposedEnd = safeStart + pageSize;
    final int end = proposedEnd > _members.length
        ? _members.length
        : proposedEnd;
    final int pages = _members.isEmpty
        ? 1
        : (_members.length / pageSize).ceil();
    return RoomMemberPage(
      items: List<RoomMember>.unmodifiable(_members.sublist(safeStart, end)),
      page: page,
      total: _members.length,
      pages: pages,
    );
  }

  @override
  Future<List<RoomMember>> fetchOffMicListeners(String roomId) async =>
      List<RoomMember>.unmodifiable(
        _members.where(
          (RoomMember member) => member.presence == RoomMemberPresence.listener,
        ),
      );

  @override
  Future<List<RoomMember>> fetchManagers(String roomId) async =>
      List<RoomMember>.unmodifiable(
        _members.where((RoomMember member) => member.isManager),
      );

  @override
  Future<List<RoomMember>> fetchMutedUsers(String roomId) async =>
      List<RoomMember>.unmodifiable(
        _members.where((RoomMember member) => member.isMuted),
      );

  @override
  Future<RoomTopic> fetchTopic(String roomId) async => _topic;

  @override
  Future<void> updateTopic({
    required String roomId,
    required RoomTopic topic,
  }) async {
    _topic = RoomTopic(
      title: topic.title,
      content: topic.content,
      version: (topic.version ?? _topic.version ?? 0) + 1,
    );
  }

  @override
  Future<void> setUserMuted({
    required String roomId,
    required int userId,
    required bool muted,
  }) async {
    _replaceMember(
      userId,
      (RoomMember member) => member.copyWith(isMuted: muted),
    );
  }

  @override
  Future<void> setUserRole({
    required String roomId,
    required int userId,
    required bool manager,
  }) async {
    _replaceMember(
      userId,
      (RoomMember member) => member.copyWith(
        role: manager ? RoomRole.moderator : RoomRole.listener,
      ),
    );
  }

  @override
  Future<void> kickUser({required String roomId, required int userId}) async {
    _members.removeWhere((RoomMember member) => member.userId == userId);
  }

  @override
  Future<void> takeUserOffMic({
    required String roomId,
    required int backendMicIndex,
    required int userId,
  }) async {
    _replaceMember(
      userId,
      (RoomMember member) => member.copyWith(
        role: RoomRole.listener,
        presence: RoomMemberPresence.listener,
        clearSeatNumber: true,
      ),
    );
  }

  @override
  Future<void> setSeatLocked({
    required String roomId,
    required int backendMicIndex,
    required bool locked,
  }) async {}

  @override
  Future<void> setSeatMuted({
    required String roomId,
    required int backendMicIndex,
    required bool muted,
  }) async {
    final int index = _members.indexWhere(
      (RoomMember member) => member.seatNumber == backendMicIndex,
    );
    if (index >= 0) {
      _members[index] = _members[index].copyWith(isMuted: muted);
    }
  }

  @override
  Future<List<MicAccessRequest>> fetchMicRequests(String roomId) async =>
      List<MicAccessRequest>.unmodifiable(_requests);

  @override
  Future<void> submitMicRequest({
    required String roomId,
    required int userId,
    required int seatNumber,
  }) async {
    _requests.removeWhere(
      (MicAccessRequest request) =>
          request.member.userId == userId &&
          request.status == MicRequestStatus.pending,
    );
    RoomMember? member;
    for (final RoomMember item in _members) {
      if (item.userId == userId) {
        member = item;
        break;
      }
    }
    member ??= RoomMember(
      userId: userId,
      name: '我',
      role: RoomRole.listener,
      presence: RoomMemberPresence.listener,
    );
    _requests.add(
      MicAccessRequest(
        id: 'request-$userId-$seatNumber',
        member: member,
        seatNumber: seatNumber,
        status: MicRequestStatus.pending,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> cancelMicRequest({required String requestId}) async {
    final int index = _requests.indexWhere(
      (MicAccessRequest request) => request.id == requestId,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '申请已失效，请刷新状态',
      );
    }
    final MicAccessRequest request = _requests[index];
    _requests[index] = MicAccessRequest(
      id: request.id,
      member: request.member,
      seatNumber: request.seatNumber,
      status: MicRequestStatus.cancelled,
      createdAt: request.createdAt,
    );
  }

  @override
  Future<void> resolveMicRequest({
    required String requestId,
    required bool accepted,
  }) async {
    final int index = _requests.indexWhere(
      (MicAccessRequest request) => request.id == requestId,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '申请已失效，请刷新列表',
      );
    }
    final MicAccessRequest request = _requests[index];
    _requests[index] = MicAccessRequest(
      id: request.id,
      member: request.member,
      seatNumber: request.seatNumber,
      status: accepted ? MicRequestStatus.accepted : MicRequestStatus.rejected,
      createdAt: request.createdAt,
    );
  }

  @override
  Future<void> inviteUserToMic({
    required String roomId,
    required int userId,
    required int seatNumber,
  }) async {
    final RoomMember member = _members.firstWhere(
      (RoomMember item) => item.userId == userId,
      orElse: () => throw const ApiException(
        kind: ApiFailureKind.business,
        message: '成员已经离开房间',
      ),
    );
    _requests.add(
      MicAccessRequest(
        id: 'invite-$userId-$seatNumber',
        member: member,
        seatNumber: seatNumber,
        status: MicRequestStatus.pending,
        createdAt: DateTime.now(),
      ),
    );
  }

  void _replaceMember(
    int userId,
    RoomMember Function(RoomMember member) transform,
  ) {
    final int index = _members.indexWhere(
      (RoomMember member) => member.userId == userId,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '成员已经离开房间',
      );
    }
    _members[index] = transform(_members[index]);
  }
}
