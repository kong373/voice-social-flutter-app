import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/account/domain/preset_avatar.dart';

void main() {
  const expectedIds = <String>[
    'avatar-preset-moon',
    'avatar-preset-sun',
    'avatar-preset-cloud',
    'avatar-preset-star',
    'avatar-preset-sea',
    'avatar-preset-leaf',
  ];

  const expectedLabels = <String>['月兔', '暖阳', '云朵', '星狐', '小鲸', '叶熊'];

  test(
    'catalog contains exactly six unique IDs with stable labels and order',
    () {
      final values = PresetAvatars.values;

      expect(values, hasLength(6));
      expect(values.map((avatar) => avatar.id), orderedEquals(expectedIds));
      expect(
        values.map((avatar) => avatar.label),
        orderedEquals(expectedLabels),
      );
      expect(values.map((avatar) => avatar.id).toSet(), hasLength(6));
      expect(values.map((avatar) => avatar.label).toSet(), hasLength(6));
    },
  );

  test('exact lookup returns the matching immutable catalog entry', () {
    for (var index = 0; index < expectedIds.length; index++) {
      final result = PresetAvatars.byId(expectedIds[index]);

      expect(result, same(PresetAvatars.values[index]));
      expect(result?.id, expectedIds[index]);
      expect(result?.label, expectedLabels[index]);
      expect(PresetAvatars.byId(expectedIds[index]), same(result));
    }
  });

  test('unknown and noncanonical IDs never fall back to a preset', () {
    for (final id in <String>[
      '',
      ' ',
      'unknown',
      'avatar-preset',
      'avatar-preset-unknown',
      'AVATAR-PRESET-MOON',
      'avatar-preset-Moon',
      '月兔',
      '/avatar-preset-moon',
      'avatar-preset-moon.png',
    ]) {
      expect(PresetAvatars.byId(id), isNull, reason: 'Unexpected ID: $id');
    }

    for (final id in expectedIds) {
      expect(PresetAvatars.byId(' $id'), isNull);
      expect(PresetAvatars.byId('$id '), isNull);
      expect(PresetAvatars.byId('$id\n'), isNull);
      expect(PresetAvatars.byId('$id\u3000'), isNull);
    }
  });

  test('catalog cannot be extended, replaced, removed or cleared', () {
    final values = PresetAvatars.values;
    const extra = PresetAvatar(id: 'not-in-catalog', label: '测试');

    expect(() => values.add(extra), throwsUnsupportedError);
    expect(() => values[0] = extra, throwsUnsupportedError);
    expect(() => values.removeAt(0), throwsUnsupportedError);
    expect(() => values.clear(), throwsUnsupportedError);

    expect(values.map((avatar) => avatar.id), orderedEquals(expectedIds));
    expect(values.map((avatar) => avatar.label), orderedEquals(expectedLabels));
    expect(PresetAvatars.byId(extra.id), isNull);
  });
}
