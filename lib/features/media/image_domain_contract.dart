import '../../core/media/media_models.dart';

/// Missing media is only the legacy, attachment-free representation. A present
/// field must obey the domain six-field contract, not the upload status DTO.
List<MediaReference> domainImages(Object? raw, MediaPurpose purpose) {
  if (raw is! List) throw mediaProtocol();
  final media = raw.map(MediaReference.fromJson).toList(growable: false);
  imageAssetIds(media, purpose);
  return List.unmodifiable(media);
}

List<String> imageAssetIds(List<MediaReference> media, MediaPurpose purpose) {
  if (media.any((item) => item.purpose != purpose)) throw mediaProtocol();
  final ids = media.map((item) => item.assetId).toList(growable: false);
  MediaLimits.validateReferences(purpose, ids);
  return List.unmodifiable(ids);
}

bool sameImageIds(List<MediaReference> left, List<MediaReference> right) =>
    left.length == right.length &&
    List.generate(
      left.length,
      (i) => left[i].assetId == right[i].assetId,
    ).every((same) => same);
