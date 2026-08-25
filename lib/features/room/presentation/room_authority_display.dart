/// Presentation helpers for values that must come from the room snapshot.
///
/// A room page may be opened before its authoritative snapshot has loaded. In
/// that state the UI must make the absence explicit instead of borrowing a
/// fixture title or member identity.
String roomAuthorityTitle(String? value) {
  final String normalized = value?.trim() ?? '';
  return normalized.isEmpty ? '房间名称不可用' : normalized;
}
