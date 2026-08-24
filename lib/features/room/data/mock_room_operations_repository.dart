import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';
import 'package:voice_social_app/features/room/domain/room_operations_repository.dart';

class MockRoomOperationsRepository
    implements
        RoomOperationsRepository,
        RoomJoinRequestRepository,
        RoomBanRepository {
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
  final List<RoomJoinRequest> _joinRequests = <RoomJoinRequest>[];
  final Map<String, RoomJoinRequestApplicantStatus> _applicantStatuses =
      <String, RoomJoinRequestApplicantStatus>{};
  final List<RoomBannedUser> _bannedUsers = <RoomBannedUser>[];

  void seedJoinRequestForQa(RoomJoinRequest request) {
    _joinRequests
      ..removeWhere((RoomJoinRequest item) => item.id == request.id)
      ..add(request);
    _applicantStatuses[request.id] = RoomJoinRequestApplicantStatus(
      roomId: '9527',
      joinRequestId: request.id,
      status: request.status,
      roomState: 'OPEN',
      banned: false,
      canCancel: request.status == RoomJoinRequestStatus.pending,
      message: request.message,
      createdAt: request.createdAt,
      resolvedAt: request.resolvedAt,
    );
  }

  void seedApplicantStatusForQa(RoomJoinRequestApplicantStatus status) {
    _applicantStatuses[status.joinRequestId] = status;
  }

  void seedBannedUserForQa(RoomBannedUser user) {
    _bannedUsers
      ..removeWhere(
        (RoomBannedUser item) => item.member.userId == user.member.userId,
      )
      ..add(user);
  }

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
  Future<RoomJoinRequestPage> fetchJoinRequests({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (page < 1 || pageSize < 1) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '入房申请分页参数无效',
      );
    }
    final int start = (page - 1) * pageSize;
    final int end = (start + pageSize).clamp(0, _joinRequests.length).toInt();
    final List<RoomJoinRequest> items = start >= _joinRequests.length
        ? const <RoomJoinRequest>[]
        : _joinRequests.sublist(start, end);
    final int pages = _joinRequests.isEmpty
        ? 0
        : (_joinRequests.length / pageSize).ceil();
    return RoomJoinRequestPage(
      items: List<RoomJoinRequest>.unmodifiable(items),
      page: page,
      total: _joinRequests.length,
      pages: pages,
    );
  }

  @override
  Future<void> resolveJoinRequest({
    required String joinRequestId,
    required bool approved,
    String? requestId,
  }) async {
    final int index = _joinRequests.indexWhere(
      (RoomJoinRequest request) => request.id == joinRequestId,
    );
    if (index < 0 || !_joinRequests[index].isPending) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '入房申请状态已变化，请刷新后重试',
      );
    }
    final RoomJoinRequest current = _joinRequests[index];
    _joinRequests[index] = RoomJoinRequest(
      id: current.id,
      member: current.member,
      status: approved
          ? RoomJoinRequestStatus.approved
          : RoomJoinRequestStatus.rejected,
      message: current.message,
      createdAt: current.createdAt,
      resolvedAt: DateTime.now(),
    );
    final RoomJoinRequestApplicantStatus? applicant =
        _applicantStatuses[joinRequestId];
    if (applicant != null) {
      _applicantStatuses[joinRequestId] = RoomJoinRequestApplicantStatus(
        roomId: applicant.roomId,
        joinRequestId: applicant.joinRequestId,
        status: approved
            ? RoomJoinRequestStatus.approved
            : RoomJoinRequestStatus.rejected,
        roomState: applicant.roomState,
        banned: applicant.banned,
        canCancel: false,
        message: applicant.message,
        createdAt: applicant.createdAt,
        resolvedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<RoomJoinRequestApplicantStatus> fetchJoinRequestStatus({
    String? roomId,
    String? joinRequestId,
  }) async {
    RoomJoinRequestApplicantStatus? result;
    if (joinRequestId != null && joinRequestId.trim().isNotEmpty) {
      result = _applicantStatuses[joinRequestId.trim()];
    } else if (roomId != null && roomId.trim().isNotEmpty) {
      result = _applicantStatuses.values
          .where(
            (RoomJoinRequestApplicantStatus item) =>
                item.roomId == roomId.trim(),
          )
          .firstOrNull;
    }
    if (result == null) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '入房申请不存在',
      );
    }
    return result;
  }

  @override
  Future<RoomJoinRequestCancellation> cancelJoinRequest({
    required String roomId,
    required String joinRequestId,
    String? requestId,
  }) async {
    final RoomJoinRequestApplicantStatus? current =
        _applicantStatuses[joinRequestId];
    if (current == null || current.roomId != roomId) {
      throw const ApiException(
        kind: ApiFailureKind.business,
        message: '入房申请不存在',
      );
    }
    if (current.status == RoomJoinRequestStatus.cancelled) {
      return RoomJoinRequestCancellation(
        roomId: roomId,
        joinRequestId: joinRequestId,
        status: RoomJoinRequestStatus.cancelled,
        cancelled: true,
        alreadyCancelled: true,
      );
    }
    if (!current.canCancel) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '入房申请当前不可撤回',
      );
    }
    _applicantStatuses[joinRequestId] = RoomJoinRequestApplicantStatus(
      roomId: current.roomId,
      joinRequestId: current.joinRequestId,
      status: RoomJoinRequestStatus.cancelled,
      roomState: current.roomState,
      banned: current.banned,
      canCancel: false,
      message: current.message,
      createdAt: current.createdAt,
      resolvedAt: DateTime.now(),
    );
    return RoomJoinRequestCancellation(
      roomId: roomId,
      joinRequestId: joinRequestId,
      status: RoomJoinRequestStatus.cancelled,
      cancelled: true,
      alreadyCancelled: false,
    );
  }

  @override
  Future<RoomBannedUserPage> fetchBannedUsers({
    required String roomId,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (page < 1 || pageSize < 1) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '房间限制分页参数无效',
      );
    }
    final int start = (page - 1) * pageSize;
    final int end = (start + pageSize).clamp(0, _bannedUsers.length).toInt();
    final List<RoomBannedUser> items = start >= _bannedUsers.length
        ? const <RoomBannedUser>[]
        : _bannedUsers.sublist(start, end);
    final int pages = _bannedUsers.isEmpty
        ? 0
        : (_bannedUsers.length / pageSize).ceil();
    return RoomBannedUserPage(
      items: List<RoomBannedUser>.unmodifiable(items),
      page: page,
      total: _bannedUsers.length,
      pages: pages,
    );
  }

  @override
  Future<void> unbanUser({
    required String roomId,
    required int userId,
    String? requestId,
  }) async {
    final int before = _bannedUsers.length;
    _bannedUsers.removeWhere(
      (RoomBannedUser banned) => banned.member.userId == userId,
    );
    if (_bannedUsers.length == before) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        message: '该用户当前不在房间限制列表中',
      );
    }
  }

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
