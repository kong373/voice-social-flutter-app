import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:voice_social_app/features/im/domain/im_refresh_hint.dart';

typedef ImCorrelationTraceSink = void Function(String line);

enum ImCorrelationTracePageAction { entered, ignored, queued, dequeued }

class ImCorrelationTraceContext {
  const ImCorrelationTraceContext._({
    required this.trace,
    required this.fingerprint,
    required this.eventVersion,
  });

  final ImCorrelationTrace trace;
  final String fingerprint;
  final int eventVersion;

  bool matches(ImRefreshHint hint) =>
      eventVersion == hint.eventVersion &&
      fingerprint == ImCorrelationTrace.fingerprintFor(hint.messageId);
}

/// Narrow, QA-only correlation for one trusted IM refresh chain.
///
/// The build flag is compile-time and the release gate is deliberately
/// independent: a release build can never emit these records, even if a
/// caller passes a test override. A context is created only from a validated
/// [ImRefreshHint], so raw or untrusted provider data cannot start tracing.
class ImCorrelationTrace {
  static const bool _requested = bool.fromEnvironment(
    'QA_IM_TRACE',
    defaultValue: false,
  );
  static final Object _zoneKey = Object();
  static final ImCorrelationTrace instance = ImCorrelationTrace._(
    enabled: kDebugMode && _requested,
    sink: _defaultSink,
  );

  ImCorrelationTrace._({
    required this.enabled,
    required ImCorrelationTraceSink sink,
  }) : _sink = sink,
       _clock = Stopwatch() {
    if (enabled) _clock.start();
  }

  @visibleForTesting
  ImCorrelationTrace.forTest({
    required bool enabled,
    required ImCorrelationTraceSink sink,
  }) : this._(enabled: kDebugMode && enabled, sink: sink);

  final bool enabled;
  final ImCorrelationTraceSink _sink;
  final Stopwatch _clock;
  int _sequence = 0;

  static ImCorrelationTrace get active =>
      currentContext?.trace ?? ImCorrelationTrace.instance;

  static ImCorrelationTraceContext? get currentContext {
    final Object? value = Zone.current[_zoneKey];
    return value is ImCorrelationTraceContext ? value : null;
  }

  static String fingerprintFor(String messageId) =>
      sha256.convert(utf8.encode(messageId)).toString().substring(0, 16);

  /// Runs [action] in a context derived from a structurally revalidated hint.
  /// Invalid values still run normally, but cannot produce a trace context.
  T runForValidatedHint<T>(ImRefreshHint hint, T Function() action) {
    if (!enabled) return action();
    final ImRefreshHint? validated = ImRefreshHint.tryParse(
      hint.toMetadata(),
      trustedSource: true,
    );
    if (validated == null) return action();
    final ImCorrelationTraceContext context = ImCorrelationTraceContext._(
      trace: this,
      fingerprint: fingerprintFor(validated.messageId),
      eventVersion: validated.eventVersion,
    );
    return runZoned<T>(
      action,
      zoneValues: <Object, Object?>{_zoneKey: context},
    );
  }

  T runInContext<T>(ImCorrelationTraceContext context, T Function() action) {
    if (!enabled || !identical(context.trace, this)) return action();
    return runZoned<T>(
      action,
      zoneValues: <Object, Object?>{_zoneKey: context},
    );
  }

  /// Runs an ordinary periodic refresh without inheriting a provider-hint
  /// context from the code that scheduled its timer.
  T runWithoutContext<T>(T Function() action) =>
      runZoned<T>(action, zoneValues: <Object, Object?>{_zoneKey: null});

  void sdkCallback() =>
      _record(stage: 'sdk_callback', event: 'trusted_custom_callback');

  void adapterAccepted() => _record(stage: 'adapter_parse', event: 'accepted');

  void busAccepted({required int handlers}) => _record(
    stage: 'bus_dispatch',
    event: 'accepted',
    details: ' handlers=${_nonNegative(handlers)}',
  );

  void busCompleted({required int successful, required int failed}) => _record(
    stage: 'bus_dispatch',
    event: 'complete',
    details:
        ' successful=${_nonNegative(successful)} failed=${_nonNegative(failed)}',
  );

  void busRejected({required String reason}) => _record(
    stage: 'bus_dispatch',
    event: 'rejected',
    details: ' reason=${_safeReason(reason)}',
  );

  void pageHandler({
    required bool active,
    required bool flight,
    required ImCorrelationTracePageAction action,
  }) => _record(
    stage: 'page_handler',
    event: action.name,
    details: ' active=$active flight=$flight',
  );

  void pageLoadStart() => _record(stage: 'page_load', event: 'start');

  int? httpStart({required String method, required bool identityBound}) {
    if (!enabled || _contextForThisTrace == null) return null;
    final int startedAtUs = _clock.elapsedMicroseconds;
    _record(
      stage: 'http',
      event: 'start',
      details: ' method=${_safeMethod(method)} bound=$identityBound',
    );
    return startedAtUs;
  }

  void httpComplete({
    required int? startedAtUs,
    required String method,
    required bool identityBound,
    required int? status,
    required String outcome,
  }) {
    if (startedAtUs == null) return;
    final int elapsedUs = _clock.elapsedMicroseconds - startedAtUs;
    _record(
      stage: 'http',
      event: 'complete',
      details:
          ' method=${_safeMethod(method)} bound=$identityBound'
          ' status=${_safeStatus(status)} outcome=${_safeOutcome(outcome)}'
          ' durationUs=${elapsedUs < 0 ? 0 : elapsedUs}',
    );
  }

  void httpAuthRecoveryStart() =>
      _record(stage: 'http', event: 'auth_recovery_start');

  void httpReplayStart() => _record(stage: 'http', event: 'replay_start');

  void httpReplaySkipped() => _record(stage: 'http', event: 'replay_skipped');

  void pagePublish({required bool followLatest}) => _record(
    stage: 'page_publish',
    event: 'publish',
    details: ' followLatest=$followLatest',
  );

  void pageFrame() => _record(stage: 'page_frame', event: 'first_frame');

  ImCorrelationTraceContext? get _contextForThisTrace {
    final ImCorrelationTraceContext? context = currentContext;
    return context != null && identical(context.trace, this) ? context : null;
  }

  void _record({
    required String stage,
    required String event,
    String details = '',
  }) {
    final ImCorrelationTraceContext? context = _contextForThisTrace;
    if (!enabled || context == null) return;
    try {
      final int sequence = ++_sequence;
      _sink(
        'im.qa.trace seq=$sequence tUs=${_clock.elapsedMicroseconds}'
        ' stage=$stage event=$event fp=${context.fingerprint}$details',
      );
    } on Object {
      // Diagnostics must never alter the traced operation's result or error.
    }
  }

  static void _defaultSink(String line) => debugPrint(line);

  static String _safeMethod(String method) => switch (method) {
    'GET' => 'GET',
    'POST' => 'POST',
    'PUT' => 'PUT',
    'PATCH' => 'PATCH',
    'DELETE' => 'DELETE',
    _ => 'OTHER',
  };

  static String _safeStatus(int? status) {
    if (status == null) return 'none';
    return status >= 100 && status <= 599 ? '$status' : 'other';
  }

  static String _safeOutcome(String outcome) => switch (outcome) {
    'success' => 'success',
    'unauthorized' => 'unauthorized',
    'api_error' => 'api_error',
    'timeout' => 'timeout',
    'network' => 'network',
    'protocol' => 'protocol',
    _ => 'error',
  };

  static String _safeReason(String reason) => switch (reason) {
    'duplicate' => 'duplicate',
    'stale' => 'stale',
    'no_subscribers' => 'no_subscribers',
    _ => 'error',
  };

  static int _nonNegative(int value) => value < 0 ? 0 : value;
}
