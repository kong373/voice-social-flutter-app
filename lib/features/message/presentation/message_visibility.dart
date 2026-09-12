part of 'message_pages.dart';

/// Presentation-only, per-repository AND per-login-generation revocation.
/// Holds no message/name/media or pending write. A stale list cannot resurrect
/// a peer denied by the history endpoint; another login never inherits it.
class _MessageVisibility extends ChangeNotifier {
  static final _scopes = Expando<Map<(int?, int), _MessageVisibility>>();

  static _MessageVisibility forViewer(
    MessageRepository repository,
    (int?, int) viewer,
  ) => (_scopes[repository] ??= {}).putIfAbsent(viewer, _MessageVisibility.new);

  final Map<int, String> _deniedPeers = {};
  final Map<int, int> _peerDenialGenerations = {};
  String? viewerReason;
  int revision = 0;

  Iterable<int> get deniedPeers => _deniedPeers.keys;

  int peerDenialGeneration(int peer) => _peerDenialGenerations[peer] ?? 0;

  String? reasonFor(int peer) => viewerReason ?? _deniedPeers[peer];

  void deny(_MessageReadDenial denial, {int? peer}) {
    if (denial.viewer || peer == null) {
      if (viewerReason != null) return;
      viewerReason = denial.reason;
    } else {
      // A repeated denial still fences an older peer recheck, even though the
      // already-redacted UI does not need another revision notification.
      _peerDenialGenerations[peer] = peerDenialGeneration(peer) + 1;
      if (_deniedPeers.containsKey(peer)) return;
      _deniedPeers[peer] = denial.reason;
    }
    revision++;
    notifyListeners();
  }

  // Only after an explicit, current-identity authoritative recheck.
  void restore({int? peer}) {
    viewerReason = null;
    if (peer != null) _deniedPeers.remove(peer);
    revision++;
    notifyListeners();
  }

  // Only an unchanged peer-denial generation may be restored by a recheck.
  bool restorePeerIfCurrent(int peer, int generation) {
    if (peerDenialGeneration(peer) != generation ||
        !_deniedPeers.containsKey(peer)) {
      return false;
    }
    restore(peer: peer);
    return true;
  }
}

class _MessageReadDenial {
  const _MessageReadDenial(this.reason, {this.viewer = false});
  final String reason;
  final bool viewer;

  static _MessageReadDenial? from(Object error, {bool reading = true}) {
    if (error is! ApiException) return null;
    if (error.isAuthenticationFailure ||
        (error.httpStatus == 403 &&
            (error.code == 40332 || error.code == 40322))) {
      return const _MessageReadDenial(
        '当前账号暂不可查看消息，请返回后重新验证账号状态。',
        viewer: true,
      );
    }
    if (error.httpStatus == 404 && error.code == 40402) {
      return const _MessageReadDenial('会话对象已不可用，无法查看或发送消息。');
    }
    // Send privacy restrictions reuse 40381, but do not revoke history access.
    // Only history/read 403 or the exact blocked-pair send response does so.
    if (error.httpStatus == 403 &&
        (reading ||
            (error.code == 40381 && error.message == 'BLOCKED_RELATION'))) {
      return const _MessageReadDenial('当前会话已无访问权限，无法查看或发送消息。');
    }
    return null;
  }
}

ConversationSummary _redactedConversation(
  ConversationSummary original,
  String reason,
) => ConversationSummary(
  id: original.id,
  kind: original.kind,
  title: '会话不可用',
  lastMessage: '',
  updatedAt: null,
  unreadCount: 0,
  targetUserId: original.targetUserId,
  available: false,
  unavailableReason: reason,
);
