import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Returns an opaque, deterministic key for coordinating one room intent.
///
/// Room intent maps must not retain passwords or user-authored public-message
/// content as keys. Length-prefixed UTF-8 fields avoid ambiguous concatenation
/// before hashing while keeping the process-local key non-reversible.
String roomIntentDigest({
  required String scope,
  required Iterable<String> fields,
}) {
  final List<int> bytes = <int>[];

  void append(String value) {
    final List<int> encoded = utf8.encode(value);
    bytes
      ..addAll(utf8.encode('${encoded.length}:'))
      ..addAll(encoded);
  }

  append(scope);
  for (final String field in fields) {
    append(field);
  }
  return sha256.convert(bytes).toString();
}
