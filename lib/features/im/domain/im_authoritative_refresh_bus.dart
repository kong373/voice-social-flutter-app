import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';

enum ImAuthoritativeRefreshScope { privateConversation }

class ImAuthoritativeRefreshRequest {
  const ImAuthoritativeRefreshRequest({
    required this.scope,
    required this.hint,
  });

  final ImAuthoritativeRefreshScope scope;
  final ImRefreshHint hint;
}

enum ImRefreshDispatchStatus {
  delivered,
  noSubscribers,
  duplicate,
  stale,
  failed,
}

class ImRefreshDispatchResult {
  const ImRefreshDispatchResult({
    required this.status,
    this.successfulHandlers = 0,
    this.failedHandlers = 0,
  });

  final ImRefreshDispatchStatus status;
  final int successfulHandlers;
  final int failedHandlers;
}

typedef ImAuthoritativeRefreshHandler =
    Future<void> Function(ImAuthoritativeRefreshRequest request);

/// In-process bridge from provider events to first-party HTTP refreshes.
///
/// A custom element can request a refresh, but it can never provide message
/// content.  Consumers must call an existing authoritative repository method
/// and keep their current UI state when that call fails.
class ImAuthoritativeRefreshBus {
  ImAuthoritativeRefreshBus({this.maximumRememberedHints = 256})
    : assert(maximumRememberedHints > 0);

  final int maximumRememberedHints;
  final Map<String, int> _rememberedVersions = <String, int>{};
  final Map<int, ImAuthoritativeRefreshHandler> _handlers =
      <int, ImAuthoritativeRefreshHandler>{};
  int? _lastAcceptedVersion;
  int _nextHandlerId = 0;
  bool _disposed = false;

  ImAuthoritativeRefreshSubscription subscribe(
    ImAuthoritativeRefreshHandler handler,
  ) {
    if (_disposed) {
      return ImAuthoritativeRefreshSubscription._inactive();
    }
    final int id = _nextHandlerId++;
    _handlers[id] = handler;
    return ImAuthoritativeRefreshSubscription._(() {
      _handlers.remove(id);
    });
  }

  Future<ImRefreshDispatchResult> publish(
    ImRefreshHint hint, {
    bool Function()? isCurrent,
  }) async {
    if (_disposed) {
      return const ImRefreshDispatchResult(
        status: ImRefreshDispatchStatus.failed,
      );
    }
    if (isCurrent != null && !isCurrent()) {
      return const ImRefreshDispatchResult(
        status: ImRefreshDispatchStatus.stale,
      );
    }
    final int? previousVersion = _lastAcceptedVersion;
    final int? previousForMessage = _rememberedVersions[hint.messageId];
    if (previousForMessage != null && hint.eventVersion <= previousForMessage) {
      return const ImRefreshDispatchResult(
        status: ImRefreshDispatchStatus.duplicate,
      );
    }
    if (previousVersion != null && hint.eventVersion <= previousVersion) {
      return const ImRefreshDispatchResult(
        status: ImRefreshDispatchStatus.stale,
      );
    }
    _lastAcceptedVersion = hint.eventVersion;
    _rememberedVersions[hint.messageId] = hint.eventVersion;
    while (_rememberedVersions.length > maximumRememberedHints) {
      _rememberedVersions.remove(_rememberedVersions.keys.first);
    }

    final List<ImAuthoritativeRefreshHandler> handlers =
        List<ImAuthoritativeRefreshHandler>.of(_handlers.values);
    if (handlers.isEmpty) {
      return const ImRefreshDispatchResult(
        status: ImRefreshDispatchStatus.noSubscribers,
      );
    }
    final ImAuthoritativeRefreshRequest request = ImAuthoritativeRefreshRequest(
      scope: ImAuthoritativeRefreshScope.privateConversation,
      hint: hint,
    );
    int successfulHandlers = 0;
    int failedHandlers = 0;
    await Future.wait<void>(
      handlers.map((ImAuthoritativeRefreshHandler handler) async {
        if (isCurrent != null && !isCurrent()) {
          return;
        }
        try {
          await handler(request);
          successfulHandlers += 1;
        } on Object {
          // A refresh hint is advisory.  One failed consumer must not turn an
          // IM callback into an application-wide error or reveal its details.
          failedHandlers += 1;
        }
      }),
    );
    return ImRefreshDispatchResult(
      status: failedHandlers == 0
          ? ImRefreshDispatchStatus.delivered
          : ImRefreshDispatchStatus.failed,
      successfulHandlers: successfulHandlers,
      failedHandlers: failedHandlers,
    );
  }

  void dispose() {
    _disposed = true;
    _handlers.clear();
    _rememberedVersions.clear();
  }
}

class ImAuthoritativeRefreshSubscription {
  ImAuthoritativeRefreshSubscription._(this._onCancel);

  ImAuthoritativeRefreshSubscription._inactive() : _onCancel = null;

  final void Function()? _onCancel;
  bool _cancelled = false;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _onCancel?.call();
  }
}
