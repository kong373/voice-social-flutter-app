import '../../../core/media/media_models.dart';

MediaReference? parseRoomMedia(Object? raw, MediaPurpose expected) {
  if (raw == null) return null;
  final media = MediaReference.fromJson(raw);
  if (media.assetId.length != 36 ||
      media.purpose != expected ||
      !{MediaPurpose.roomCover, MediaPurpose.roomBackground}.contains(expected))
    throw mediaProtocol();
  return media;
}

bool sameRoomMedia(MediaReference? left, MediaReference? right) =>
    left == null || right == null
    ? left == right
    : left.assetId == right.assetId &&
          left.purpose == right.purpose &&
          left.mediaType == right.mediaType &&
          left.bytes == right.bytes &&
          left.durationMillis == right.durationMillis &&
          left.version == right.version;

/// An omitted edit is different from an explicit clear. Neither is inferred
/// from a failed upload, missing descriptor or discarded picker selection.
class RoomImageChange {
  const RoomImageChange.unchanged() : changed = false, media = null;
  const RoomImageChange.clear() : changed = true, media = null;
  const RoomImageChange.replace(MediaReference value)
    : changed = true,
      media = value;
  final bool changed;
  final MediaReference? media;
  String get intent => !changed ? 'KEEP' : media?.assetId ?? 'CLEAR';

  void validate(MediaPurpose purpose) {
    if (media != null) parseRoomMedia(media!.toJson(), purpose);
  }

  Map<String, Object?> write(String field) =>
      changed ? {field: media?.assetId} : const {};
  MediaReference? apply(MediaReference? previous) => changed ? media : previous;
}
