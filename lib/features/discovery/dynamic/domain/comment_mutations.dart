import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'dynamic_models.dart';
import 'dynamic_request_id.dart';

class PendingCommentMutation {
  PendingCommentMutation(this.kind, this.body, this.requestId);
  final String kind;
  final Map<String, Object?> body;
  final String requestId;
  bool uncertain = false;
  String get dynamicId => body['dynamicId'].toString();
}

abstract interface class CommentActions {
  (int, int) get commentIdentity;
  Listenable? get commentIdentityChanges;
  PendingCommentMutation? get pendingCommentMutation;
  Future<CommentDeletion> deleteComment({
    required String dynamicId,
    required String commentId,
    String? requestId,
  });
}

/// Repository-lifetime, account-scoped journal. Futures never cross generations;
/// unknown commands retain their exact body/key through page disposal/logout.
mixin CommentMutationJournal implements CommentActions {
  final Map<int, PendingCommentMutation> _commands = {};
  final Map<(int, int), Future<Object>> _flights = {};
  final Map<(int, String), String> _keyBindings = {};
  @override
  PendingCommentMutation? get pendingCommentMutation =>
      _commands[commentIdentity.$1];

  void requireCommentIdentity((int, int) identity) {
    if (identity.$1 <= 0 || identity != commentIdentity) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '登录身份已变化，请返回原账号处理未确认评论操作',
      );
    }
  }

  Future<T> commentMutation<T extends Object>(
    String kind,
    Map<String, Object?> body,
    String? requestId,
    Future<T> Function(PendingCommentMutation, (int, int)) send,
  ) async {
    final identity = commentIdentity;
    requireCommentIdentity(identity);
    final fingerprint = jsonEncode([kind, body]);
    final existing = _commands[identity.$1];
    if (existing != null &&
        jsonEncode([existing.kind, existing.body]) != fingerprint) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40903,
        message: '请先重试原评论操作，不能更换目标或内容',
      );
    }
    final key =
        existing?.requestId ??
        (requestId == null
            ? newDynamicRequestId('comment-$kind')
            : normalizeDynamicRequestId(requestId));
    final bound = _keyBindings[(identity.$1, key)];
    if (bound != null && bound != fingerprint) {
      throw const ApiException(
        kind: ApiFailureKind.conflict,
        code: 40903,
        message: '请求键不能用于另一评论操作',
      );
    }
    _keyBindings[(identity.$1, key)] = fingerprint;
    final flight = _flights[identity];
    if (flight != null) return await flight as T;
    final command =
        existing ?? PendingCommentMutation(kind, Map.unmodifiable(body), key);
    final wasUncertain = command.uncertain;
    command.uncertain = true;
    _commands[identity.$1] = command;
    late final Future<Object> work;
    work = send(command, identity)
        .then<Object>(
          (value) {
            requireCommentIdentity(identity);
            if (identical(_commands[identity.$1], command))
              _commands.remove(identity.$1);
            return value;
          },
          onError: (Object error, StackTrace stack) {
            if (identity == commentIdentity &&
                !wasUncertain &&
                !shouldRetainDynamicWriteRequest(error) &&
                identical(_commands[identity.$1], command)) {
              _commands.remove(identity.$1);
            }
            Error.throwWithStackTrace(error, stack);
          },
        )
        .whenComplete(() {
          if (identical(_flights[identity], work)) _flights.remove(identity);
        });
    _flights[identity] = work;
    return await work as T;
  }
}
