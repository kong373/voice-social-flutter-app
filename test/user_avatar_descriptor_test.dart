import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/account/domain/user_avatar_descriptor.dart';

const _presetIds = <String>[
  'avatar-preset-moon',
  'avatar-preset-sun',
  'avatar-preset-cloud',
  'avatar-preset-star',
  'avatar-preset-sea',
  'avatar-preset-leaf',
];

const _uploadId = '123e4567-e89b-42d3-a456-426614174000';

const _preset = <String, Object?>{
  'kind': 'PRESET',
  'reference': 'avatar-preset-moon',
};

const _uploaded = <String, Object?>{
  'kind': 'UPLOADED',
  'reference': _uploadId,
  'version': 0,
};

void main() {
  test(
    'all six exact presets produce preset descriptors without a version',
    () {
      for (final id in _presetIds) {
        final data = <String, Object?>{'kind': 'PRESET', 'reference': id};

        final descriptor = UserAvatarDescriptor.fromBackendData(data);

        expect(descriptor.kind, UserAvatarKind.preset);
        expect(descriptor.reference, id);
        expect(descriptor.version, isNull);

        final optional = UserAvatarDescriptor.parseOptional(data);
        expect(optional, isNotNull);
        expect(optional!.kind, UserAvatarKind.preset);
        expect(optional.reference, id);
        expect(optional.version, isNull);
      }
    },
  );

  test(
    'uploaded descriptors accept canonical references with versions 0 and 1',
    () {
      for (final version in <int>[0, 1]) {
        final data = <String, Object?>{..._uploaded, 'version': version};

        final descriptor = UserAvatarDescriptor.fromBackendData(data);

        expect(descriptor.kind, UserAvatarKind.uploaded);
        expect(descriptor.reference, _uploadId);
        expect(descriptor.version, version);

        final optional = UserAvatarDescriptor.parseOptional(data);
        expect(optional, isNotNull);
        expect(optional!.kind, UserAvatarKind.uploaded);
        expect(optional.reference, _uploadId);
        expect(optional.version, version);
      }
    },
  );

  test(
    'only the optional entry point accepts null and it supplies no default',
    () {
      expect(UserAvatarDescriptor.parseOptional(null), isNull);
      _expectInvalid(null);
    },
  );

  test('non-map inputs and empty maps are rejected', () {
    for (final raw in <Object?>[
      true,
      false,
      0,
      1.5,
      '',
      'PRESET',
      '{"kind":"PRESET","reference":"avatar-preset-moon"}',
      <Object?>[],
      <Object?>[_preset],
      <String, Object?>{},
      Object(),
    ]) {
      _expectInvalid(raw);
    }
  });

  test('map generic types do not replace validation of actual fields', () {
    final data = <Object?, Object?>{
      'kind': 'UPLOADED',
      'reference': _uploadId,
      'version': 1,
    };

    final descriptor = UserAvatarDescriptor.fromBackendData(data);
    expect(descriptor.kind, UserAvatarKind.uploaded);
    expect(descriptor.reference, _uploadId);
    expect(descriptor.version, 1);

    _expectInvalid(<Object?, Object?>{..._preset, 1: 'unexpected'});
    _expectInvalid(<Object?, Object?>{..._uploaded, null: 'unexpected'});
    _expectInvalid(<Object?, Object?>{0: 'PRESET', 1: 'avatar-preset-moon'});
  });

  test('each required field rejects both absence and explicit null', () {
    for (final source in <Map<String, Object?>>[_preset, _uploaded]) {
      for (final field in source.keys) {
        final missing = <String, Object?>{...source}..remove(field);
        _expectInvalid(missing);

        _expectInvalid(<String, Object?>{...source, field: null});
      }
    }
  });

  test('kind requires an exact supported string', () {
    for (final source in <Map<String, Object?>>[_preset, _uploaded]) {
      for (final kind in <Object?>[
        '',
        ' ',
        'preset',
        'uploaded',
        'Preset',
        'Uploaded',
        ' PRESET',
        'PRESET ',
        'UPLOADED\n',
        'UNKNOWN',
        0,
        1.0,
        true,
        UserAvatarKind.preset,
        <String>['PRESET'],
        <String, Object?>{'value': 'UPLOADED'},
      ]) {
        _expectInvalid(<String, Object?>{...source, 'kind': kind});
      }
    }
  });

  test('reference rejects invalid types, URLs, paths and empty values', () {
    for (final source in <Map<String, Object?>>[_preset, _uploaded]) {
      for (final reference in <Object?>[
        null,
        0,
        1.5,
        true,
        false,
        <String>[],
        <String, Object?>{'id': _uploadId},
        '',
        ' ',
        '\u3000',
        'https://example.invalid/avatar.png',
        'https://example.invalid/avatar?signature=synthetic',
        '/private/avatar.png',
        '../avatar.png',
        'file:///private/avatar.png',
        'data:image/png;base64,AA==',
        'avatar.png',
      ]) {
        _expectInvalid(<String, Object?>{...source, 'reference': reference});
      }
    }
  });

  test('preset references are exact and unknown IDs never fall back', () {
    for (final id in _presetIds) {
      for (final invalid in <String>[
        ' $id',
        '$id ',
        '$id\n',
        '$id\u3000',
        id.toUpperCase(),
      ]) {
        _expectInvalid(<String, Object?>{
          'kind': 'PRESET',
          'reference': invalid,
        });
      }
    }

    for (final invalid in <String>[
      'avatar-preset-unknown',
      'avatar-preset',
      'moon',
      '月兔',
      _uploadId,
    ]) {
      _expectInvalid(<String, Object?>{..._preset, 'reference': invalid});
    }
  });

  test(
    'uploaded references reject every tested noncanonical UUID spelling',
    () {
      for (final invalid in <String>[
        _uploadId.toUpperCase(),
        _uploadId.replaceAll('-', ''),
        _uploadId.replaceFirst('-', '_'),
        '1-1-1-1-1',
        'g23e4567-e89b-42d3-a456-426614174000',
        '123e4567-e89b-42d3-a456-42661417400',
        '123e4567-e89b-42d3-a456-4266141740000',
        '{$_uploadId}',
        'urn:uuid:$_uploadId',
        ' $_uploadId',
        '$_uploadId ',
        '$_uploadId\n',
        '$_uploadId\u0000',
        'avatar-preset-moon',
      ]) {
        _expectInvalid(<String, Object?>{..._uploaded, 'reference': invalid});
      }
    },
  );

  test('uploaded version is required and is never coerced or truncated', () {
    for (final version in <Object?>[
      null,
      -1,
      -2,
      0.0,
      1.0,
      0.5,
      -0.5,
      double.nan,
      double.infinity,
      '',
      '0',
      '1',
      '1.0',
      ' 1 ',
      true,
      false,
      <int>[0],
      <String, Object?>{'value': 0},
    ]) {
      _expectInvalid(<String, Object?>{..._uploaded, 'version': version});
    }

    final missing = <String, Object?>{..._uploaded}..remove('version');
    _expectInvalid(missing);
  });

  test(
    'preset rejects a version field even when its value is null or zero',
    () {
      for (final version in <Object?>[null, 0, 1, '0', false]) {
        _expectInvalid(<String, Object?>{..._preset, 'version': version});
      }
    },
  );

  test('both kinds reject extra fields instead of ignoring them', () {
    for (final source in <Map<String, Object?>>[_preset, _uploaded]) {
      for (final field in <String>[
        'url',
        'signedUrl',
        'objectKey',
        'mediaId',
        'size',
        'width',
        'height',
        'mime',
        'contentType',
        'extra',
      ]) {
        for (final value in <Object?>[null, 1, 'untrusted-extra-marker']) {
          _expectInvalid(<String, Object?>{...source, field: value});
        }
      }
    }
  });

  test('immutable maps are accepted and key insertion order is irrelevant', () {
    final data = Map<String, Object?>.unmodifiable(<String, Object?>{
      'version': 1,
      'reference': _uploadId,
      'kind': 'UPLOADED',
    });

    final descriptor = UserAvatarDescriptor.fromBackendData(data);

    expect(descriptor.kind, UserAvatarKind.uploaded);
    expect(descriptor.reference, _uploadId);
    expect(descriptor.version, 1);
    expect(data, <String, Object?>{
      'kind': 'UPLOADED',
      'reference': _uploadId,
      'version': 1,
    });
  });

  test('later input mutations cannot change the parsed projection', () {
    final data = <String, Object?>{..._uploaded};
    final first = UserAvatarDescriptor.fromBackendData(data);
    final second = UserAvatarDescriptor.fromBackendData(data);

    data
      ..['kind'] = 'UNKNOWN'
      ..['reference'] = 'https://example.invalid/replacement'
      ..['version'] = -1
      ..['extra'] = 'untrusted-extra-marker';

    for (final descriptor in <UserAvatarDescriptor>[first, second]) {
      expect(descriptor.kind, UserAvatarKind.uploaded);
      expect(descriptor.reference, _uploadId);
      expect(descriptor.version, 0);
    }

    _expectInvalid(data);
  });

  test(
    'descriptor diagnostics omit references and exceptions omit payloads',
    () {
      final preset = UserAvatarDescriptor.fromBackendData(_preset);
      final uploaded = UserAvatarDescriptor.fromBackendData(_uploaded);

      expect(preset.toString(), 'UserAvatarDescriptor(kind: preset)');
      expect(uploaded.toString(), 'UserAvatarDescriptor(kind: uploaded)');
      expect(preset.toString(), isNot(contains(preset.reference)));
      expect(uploaded.toString(), isNot(contains(uploaded.reference)));

      _expectInvalid(<String, Object?>{
        'kind': 'untrusted-kind-marker',
        'reference': 'untrusted-reference-marker',
        'version': 'untrusted-version-marker',
      });
    },
  );
}

void _expectInvalid(Object? raw) {
  final failure = throwsA(
    isA<FormatException>()
        .having(
          (error) => error.message,
          'message',
          'Invalid user avatar descriptor',
        )
        .having((error) => error.source, 'source', isNull)
        .having((error) => error.offset, 'offset', isNull)
        .having(
          (error) => error.toString(),
          'diagnostic',
          'FormatException: Invalid user avatar descriptor',
        ),
  );

  expect(() => UserAvatarDescriptor.fromBackendData(raw), failure);

  // Null alone is the optional parser's compatibility case.
  if (raw != null) {
    expect(() => UserAvatarDescriptor.parseOptional(raw), failure);
  }
}
