import 'dart:convert';

/// A provider-neutral, metadata-only refresh hint.
///
/// Tencent custom elements are untrusted input.  The provider adapter parses
/// them into this value only after it has established that the message came
/// from an explicitly trusted first-party source.  No provider payload,
/// sender, room id, or display text crosses this boundary.
class ImRefreshHint {
  const ImRefreshHint({required this.messageId, required this.eventVersion});

  static const Set<String> allowedFields = <String>{
    'messageId',
    'eventVersion',
  };
  static const int maximumPayloadBytes = 8192;
  static const int maximumMessageIdLength = 128;

  /// Backend message IDs are positive Java signed `long` values.  Keep the
  /// same bound instead of narrowing them to a 32-bit sequence.
  static const int maximumEventVersion = 0x7fffffffffffffff;
  static final RegExp _messageIdPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$',
  );

  final String messageId;
  final int eventVersion;

  /// Attempts to parse the allow-listed first-party hint shape.
  ///
  /// The [trustedSource] bit is supplied by the provider adapter's explicit
  /// trust seam; it is never read from the custom element itself.  Returning
  /// `null` for every malformed/untrusted value makes the message callback a
  /// safe ignore path and avoids exposing provider content to the UI.
  static ImRefreshHint? tryParse(Object? raw, {required bool trustedSource}) {
    if (!trustedSource) {
      return null;
    }
    if (raw is Map && raw.length > allowedFields.length) {
      return null;
    }
    final Object? decoded = _decode(raw);
    if (decoded is! Map) {
      return null;
    }
    late final Map<Object?, Object?> source;
    try {
      source = Map<Object?, Object?>.from(decoded);
    } on Object {
      return null;
    }
    if (source.length != allowedFields.length ||
        source.keys.any(
          (Object? key) => key is! String || !allowedFields.contains(key),
        )) {
      return null;
    }
    final Object? messageIdValue = source['messageId'];
    final Object? versionValue = source['eventVersion'];
    if (messageIdValue is! String ||
        messageIdValue.length > maximumMessageIdLength ||
        !_messageIdPattern.hasMatch(messageIdValue)) {
      return null;
    }
    if (versionValue is! int ||
        versionValue < 1 ||
        versionValue > maximumEventVersion) {
      return null;
    }
    return ImRefreshHint(messageId: messageIdValue, eventVersion: versionValue);
  }

  Map<String, Object> toMetadata() => <String, Object>{
    'messageId': messageId,
    'eventVersion': eventVersion,
  };

  @override
  String toString() =>
      'ImRefreshHint(messageId=$messageId, '
      'eventVersion=$eventVersion)';

  static Object? _decode(Object? raw) {
    if (raw is Map) {
      return raw;
    }
    if (raw is! String) {
      return null;
    }
    if (utf8.encode(raw).length > maximumPayloadBytes) {
      return null;
    }
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    } on Object {
      return null;
    }
  }
}
