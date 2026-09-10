import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/account/compliance/domain/real_name_submission_policy.dart';

const _statusCodes = <String, int>{
  'NOT_SUBMITTED': 0,
  'UNVERIFIED': 0,
  'PENDING': 1,
  'VERIFIED': 2,
  'APPROVED': 2,
  'REJECTED': 3,
};

// Explicit expected matrix: status, code, needsAgeResubmission, canSubmit.
const _validCases = <(String, int, bool, bool)>[
  ('NOT_SUBMITTED', 0, false, true),
  ('UNVERIFIED', 0, false, true),
  ('PENDING', 1, false, false),
  ('VERIFIED', 2, false, false),
  ('VERIFIED', 2, true, true),
  ('APPROVED', 2, false, false),
  ('APPROVED', 2, true, true),
  ('REJECTED', 3, false, true),
];

const _validResubmission = <String, Object?>{
  'status': 'VERIFIED',
  'statusCode': 2,
  'needsAgeResubmission': true,
  'canSubmit': true,
};

void main() {
  for (final value in _validCases) {
    final (status, code, needsResubmission, canSubmit) = value;

    test('$status/$code accepts needsAgeResubmission=$needsResubmission '
        'and canSubmit=$canSubmit', () {
      final policy = RealNameSubmissionPolicy.fromBackendData(
        _data(status, code, needsResubmission, canSubmit),
      );

      expect(policy.needsAgeResubmission, needsResubmission);
      expect(policy.canSubmit, canSubmit);
    });
  }

  test('every other boolean combination is rejected for each known status', () {
    for (final entry in _statusCodes.entries) {
      for (final needsResubmission in <bool>[false, true]) {
        for (final canSubmit in <bool>[false, true]) {
          final candidate = (
            entry.key,
            entry.value,
            needsResubmission,
            canSubmit,
          );

          if (!_validCases.contains(candidate)) {
            _expectInvalid(
              _data(entry.key, entry.value, needsResubmission, canSubmit),
            );
          }
        }
      }
    }
  });

  test('all four fields are required and cannot be explicitly null', () {
    for (final field in <String>[
      'status',
      'statusCode',
      'needsAgeResubmission',
      'canSubmit',
    ]) {
      final missing = <String, Object?>{..._validResubmission}..remove(field);
      _expectInvalid(missing);

      _expectInvalid(<String, Object?>{..._validResubmission, field: null});
    }

    _expectInvalid(<String, Object?>{});
  });

  test('status requires an exact supported string without normalization', () {
    for (final status in <Object?>[
      '',
      ' ',
      'UNKNOWN',
      'verified',
      'Verified',
      ' VERIFIED',
      'VERIFIED ',
      'VERIFIED\n',
      'VERIFIED\u3000',
      '2',
      2,
      2.0,
      true,
      false,
      <String>['VERIFIED'],
      <String, Object?>{'value': 'VERIFIED'},
    ]) {
      _expectInvalid(<String, Object?>{
        ..._validResubmission,
        'status': status,
      });
    }
  });

  test('statusCode must be an actual int and is never coerced', () {
    for (final value in _validCases) {
      final (status, code, needsResubmission, canSubmit) = value;

      for (final invalidCode in <Object?>[
        code.toString(),
        code.toDouble(),
        true,
        false,
        <int>[code],
        <String, Object?>{'value': code},
      ]) {
        _expectInvalid(<String, Object?>{
          ..._data(status, code, needsResubmission, canSubmit),
          'statusCode': invalidCode,
        });
      }
    }
  });

  test(
    'each status rejects every wrong code, including out-of-range codes',
    () {
      for (final value in _validCases) {
        final (status, code, needsResubmission, canSubmit) = value;

        for (final wrongCode in <int>[-1, 0, 1, 2, 3, 4, 99]) {
          if (wrongCode != code) {
            _expectInvalid(<String, Object?>{
              ..._data(status, code, needsResubmission, canSubmit),
              'statusCode': wrongCode,
            });
          }
        }
      }
    },
  );

  test(
    'both workflow fields require actual bool values in every valid case',
    () {
      for (final value in _validCases) {
        final (status, code, needsResubmission, canSubmit) = value;

        for (final field in <String>['needsAgeResubmission', 'canSubmit']) {
          for (final invalid in <Object?>[
            null,
            0,
            1,
            0.0,
            1.0,
            '',
            'true',
            'false',
            '0',
            '1',
            <bool>[true],
            <String, Object?>{'value': false},
          ]) {
            _expectInvalid(<String, Object?>{
              ..._data(status, code, needsResubmission, canSubmit),
              field: invalid,
            });
          }
        }
      }
    },
  );

  test(
    'verified records explicitly distinguish resubmission from completion',
    () {
      final legacyWithoutAge =
          RealNameSubmissionPolicy.fromBackendData(const <String, Object?>{
            'status': 'VERIFIED',
            'statusCode': 2,
            'needsAgeResubmission': true,
            'canSubmit': true,
          });
      expect(legacyWithoutAge.needsAgeResubmission, isTrue);
      expect(legacyWithoutAge.canSubmit, isTrue);

      final complete =
          RealNameSubmissionPolicy.fromBackendData(const <String, Object?>{
            'status': 'VERIFIED',
            'statusCode': 2,
            'needsAgeResubmission': false,
            'canSubmit': false,
          });
      expect(complete.needsAgeResubmission, isFalse);
      expect(complete.canSubmit, isFalse);

      final pending =
          RealNameSubmissionPolicy.fromBackendData(const <String, Object?>{
            'status': 'PENDING',
            'statusCode': 1,
            'needsAgeResubmission': false,
            'canSubmit': false,
          });
      expect(pending.needsAgeResubmission, isFalse);
      expect(pending.canSubmit, isFalse);
    },
  );

  test(
    'unrelated fields are ignored and an immutable input is not modified',
    () {
      final data = Map<String, Object?>.unmodifiable(<String, Object?>{
        ..._validResubmission,
        'providerStatus': 42,
        'reviewMode': <Object?>[null],
        'accountUsable': false,
        'youthMode': true,
        'unknownExtra': Object(),
      });

      final policy = RealNameSubmissionPolicy.fromBackendData(data);

      // This remains a workflow projection, not authorization to act.
      expect(policy.needsAgeResubmission, isTrue);
      expect(policy.canSubmit, isTrue);
      expect(data['accountUsable'], isFalse);
      expect(data['youthMode'], isTrue);
      expect(data['providerStatus'], 42);
      expect(data['reviewMode'], <Object?>[null]);
    },
  );

  test('parsed flags do not change when the input map is later modified', () {
    final data = <String, Object?>{..._validResubmission};
    final policy = RealNameSubmissionPolicy.fromBackendData(data);

    data['needsAgeResubmission'] = false;
    data['canSubmit'] = false;

    expect(policy.needsAgeResubmission, isTrue);
    expect(policy.canSubmit, isTrue);

    final next = RealNameSubmissionPolicy.fromBackendData(data);
    expect(next.needsAgeResubmission, isFalse);
    expect(next.canSubmit, isFalse);
  });

  test('unknown status never exposes the supplied value in its exception', () {
    _expectInvalid(const <String, Object?>{
      'status': 'untrusted-status-marker',
      'statusCode': 2,
      'needsAgeResubmission': true,
      'canSubmit': true,
    });
  });
}

Map<String, Object?> _data(
  String status,
  int code,
  bool needsAgeResubmission,
  bool canSubmit,
) {
  return <String, Object?>{
    'status': status,
    'statusCode': code,
    'needsAgeResubmission': needsAgeResubmission,
    'canSubmit': canSubmit,
  };
}

void _expectInvalid(Map<String, Object?> data) {
  expect(
    () => RealNameSubmissionPolicy.fromBackendData(data),
    throwsA(
      isA<FormatException>()
          .having(
            (error) => error.message,
            'message',
            'INVALID_REAL_NAME_SUBMISSION_POLICY',
          )
          .having((error) => error.source, 'source', isNull)
          .having((error) => error.offset, 'offset', isNull)
          .having(
            (error) => error.toString(),
            'diagnostic',
            'FormatException: INVALID_REAL_NAME_SUBMISSION_POLICY',
          ),
    ),
  );
}
