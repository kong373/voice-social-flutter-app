import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';

/// Provider-neutral events emitted by an initialized IM adapter.
enum ImSessionEventKind {
  userSigExpired,
  networkOffline,
  networkOnline,
  refreshHint,
}

class ImSessionEvent {
  const ImSessionEvent({required this.kind, this.refreshHint});

  const ImSessionEvent.userSigExpired()
    : this(kind: ImSessionEventKind.userSigExpired);

  const ImSessionEvent.networkOffline()
    : this(kind: ImSessionEventKind.networkOffline);

  const ImSessionEvent.networkOnline()
    : this(kind: ImSessionEventKind.networkOnline);

  const ImSessionEvent.refresh(ImRefreshHint hint)
    : this(kind: ImSessionEventKind.refreshHint, refreshHint: hint);

  final ImSessionEventKind kind;

  /// The only custom-message value allowed to leave the provider adapter.
  /// It is null for lifecycle/network events.
  final ImRefreshHint? refreshHint;
}
