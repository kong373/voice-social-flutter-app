import '../network/api_exception.dart';

enum MediaPurpose {
  dynamicImage('DYNAMIC_IMAGE'),
  privateImage('PRIVATE_IMAGE'),
  privateVoice('PRIVATE_VOICE'),
  privateVideo('PRIVATE_VIDEO'),
  supportImage('SUPPORT_IMAGE');

  const MediaPurpose(this.wire);
  final String wire;
  int get maximumBytes => this == privateVideo ? 100000000 : 10000000;
  int get maximumCount => this == dynamicImage
      ? 9
      : this == supportImage
      ? 3
      : 1;
  Set<String> get mediaTypes => switch (this) {
    privateVoice => const {
      'audio/aac',
      'audio/mp4',
      'audio/mpeg',
      'audio/ogg',
      'audio/wav',
    },
    privateVideo => const {'video/mp4'},
    _ => const {'image/jpeg', 'image/png', 'image/webp'},
  };
  static MediaPurpose parse(Object? value) => values.firstWhere(
    (p) => p.wire == value,
    orElse: () => throw mediaProtocol(),
  );
}

enum MediaAssetState {
  allocated('ALLOCATED'),
  uploading('UPLOADING'),
  quarantined('QUARANTINED'),
  ready('READY'),
  rejected('REJECTED'),
  revoked('REVOKED');

  const MediaAssetState(this.wire);
  final String wire;
  static MediaAssetState parse(Object? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => throw mediaProtocol(),
  );
}

class MediaLimits {
  static void validateSelection(
    MediaPurpose purpose, {
    required int bytes,
    required int durationMillis,
  }) {
    if (bytes <= 0 || bytes > purpose.maximumBytes) throw mediaProtocol();
    validateDuration(purpose, durationMillis);
  }

  static void validateDuration(MediaPurpose purpose, int value) {
    final maximum = switch (purpose) {
      MediaPurpose.privateVoice => 60000,
      MediaPurpose.privateVideo => 30000,
      _ => 0,
    };
    if (value < 0 || value > maximum || (maximum > 0 && value == 0))
      throw mediaProtocol();
  }

  static void validateReferences(MediaPurpose purpose, List<String> ids) {
    if (ids.length > purpose.maximumCount || ids.toSet().length != ids.length)
      throw mediaProtocol();
    for (final id in ids) {
      requireMediaId(id);
    }
  }
}

class MediaReference {
  const MediaReference._(
    this.assetId,
    this.purpose,
    this.mediaType,
    this.bytes,
    this.durationMillis,
    this.version,
  );
  final String assetId;
  final MediaPurpose purpose;
  final String mediaType;
  final int bytes;
  final int durationMillis;
  final int version;

  factory MediaReference.fromJson(Object? raw) {
    final map = mediaMap(raw, const {
      'assetId',
      'purpose',
      'mediaType',
      'bytes',
      'durationMillis',
      'version',
    });
    final purpose = MediaPurpose.parse(map['purpose']);
    final type = map['mediaType'];
    if (type is! String || !purpose.mediaTypes.contains(type))
      throw mediaProtocol();
    final bytes = mediaInteger(map['bytes']);
    final duration = mediaInteger(map['durationMillis']);
    MediaLimits.validateSelection(
      purpose,
      bytes: bytes,
      durationMillis: duration,
    );
    return MediaReference._(
      requireMediaId(map['assetId']),
      purpose,
      type,
      bytes,
      duration,
      mediaInteger(map['version']),
    );
  }

  Map<String, Object?> toJson() => {
    'assetId': assetId,
    'purpose': purpose.wire,
    'mediaType': mediaType,
    'bytes': bytes,
    'durationMillis': durationMillis,
    'version': version,
  };
}

class MediaAssetStatus {
  const MediaAssetStatus._(
    this.assetId,
    this.purpose,
    this.state,
    this.version,
    this.expiresAt,
    this.mediaType,
    this.bytes,
    this.durationMillis,
  );
  final String assetId;
  final MediaPurpose purpose;
  final MediaAssetState state;
  final int version;
  final DateTime expiresAt;
  final String? mediaType;
  final int? bytes;
  final int? durationMillis;
  int get maximumBytes => purpose.maximumBytes;
  bool isExpired(DateTime now) => !expiresAt.isAfter(now);

  factory MediaAssetStatus.fromJson(Object? raw) {
    final map = mediaMap(raw, const {
      'assetId',
      'purpose',
      'state',
      'version',
      'maximumBytes',
      'expiresAt',
      'mediaType',
      'bytes',
      'durationMillis',
    });
    final purpose = MediaPurpose.parse(map['purpose']);
    final state = MediaAssetState.parse(map['state']);
    if (map['maximumBytes'] is! int ||
        map['maximumBytes'] != purpose.maximumBytes)
      throw mediaProtocol();
    final type = map['mediaType'];
    if (type != null && (type is! String || !purpose.mediaTypes.contains(type)))
      throw mediaProtocol();
    final bytes = map['bytes'] == null ? null : mediaInteger(map['bytes']);
    final duration = map['durationMillis'] == null
        ? null
        : mediaInteger(map['durationMillis']);
    if (bytes != null && (bytes == 0 || bytes > purpose.maximumBytes))
      throw mediaProtocol();
    if (duration != null) MediaLimits.validateDuration(purpose, duration);
    final result = MediaAssetStatus._(
      requireMediaId(map['assetId']),
      purpose,
      state,
      mediaInteger(map['version']),
      _utcInstant(map['expiresAt']),
      type as String?,
      bytes,
      duration,
    );
    if (state == MediaAssetState.ready) result.ready;
    return result;
  }

  MediaReference? get ready => state != MediaAssetState.ready
      ? null
      : MediaReference.fromJson({
          'assetId': assetId,
          'purpose': purpose.wire,
          'version': version,
          'mediaType': mediaType,
          'bytes': bytes,
          'durationMillis': durationMillis,
        });
}

String requireMediaId(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      ).hasMatch(value))
    throw mediaProtocol();
  return value;
}

int mediaInteger(Object? value) {
  if (value is! int || value < 0) throw mediaProtocol();
  return value;
}

Map<String, Object?> mediaMap(Object? value, Set<String> fields) {
  if (value is! Map<String, Object?> ||
      value.length != fields.length ||
      !value.keys.every(fields.contains))
    throw mediaProtocol();
  return value;
}

ApiException mediaProtocol() =>
    const ApiException(kind: ApiFailureKind.protocol, message: '媒体数据或限制不符合约定');

DateTime _utcInstant(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$',
      ).hasMatch(value))
    throw mediaProtocol();
  final date = DateTime.tryParse(value);
  if (date == null ||
      !date.isUtc ||
      date.toIso8601String().substring(0, 19) != value.substring(0, 19))
    throw mediaProtocol();
  return date;
}
