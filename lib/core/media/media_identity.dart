import 'dart:async';
import 'package:flutter/foundation.dart';
import '../network/api_exception.dart';

/// Captures the existing session tuple, never a token. Token rotation alone is
/// allowed; logout/account ABA permanently invalidates this scope and its files.
class MediaIdentityScope {
  MediaIdentityScope({
    required int Function() currentUserId,
    required int Function() identityGeneration,
    required Listenable changes,
  }) : _user = currentUserId,
       _generation = identityGeneration,
       _changes = changes,
       userId = currentUserId(),
       generation = identityGeneration() {
    check();
    _changes.addListener(_changed);
  }
  final int userId;
  final int generation;
  final int Function() _user;
  final int Function() _generation;
  final Listenable _changes;
  final _cancelled = Completer<void>();
  final _callbacks = <void Function()>{};
  bool _closed = false;
  bool get isCurrent =>
      !_closed &&
      userId > 0 &&
      userId == _user() &&
      generation == _generation();
  static const invalid = ApiException(
    kind: ApiFailureKind.unauthorized,
    message: '账号已变化，请重新选择媒体',
  );

  void check() {
    if (!isCurrent) {
      dispose();
      throw invalid;
    }
  }

  void _changed() {
    if (!isCurrent) dispose();
  }

  /// Unregister after each request. Cancellation aborts idle I/O too, without
  /// waiting for another chunk or network timeout.
  void Function() onCancel(void Function() callback) {
    check();
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  Future<T> wait<T>(Future<T> future) async {
    // The supplied future has already started. Observe it even if the scope
    // was invalidated synchronously while starting I/O, and discard its error
    // as well as its result after identity loss.
    final observed = future.then<T>(
      (value) {
        check();
        return value;
      },
      onError: (Object error, StackTrace stack) {
        check();
        Error.throwWithStackTrace(error, stack);
      },
    );
    if (!isCurrent) dispose();
    final value = await Future.any<T>([
      observed,
      _cancelled.future.then<T>((_) => throw invalid),
    ]);
    check();
    return value;
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _changes.removeListener(_changed);
    _cancelled.complete();
    final callbacks = _callbacks.toList();
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}
