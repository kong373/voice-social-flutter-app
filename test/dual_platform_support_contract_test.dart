import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/dual_first_party_business_support.dart';

void main() {
  test('platform endpoints and private runtime paths are fixed', () {
    for (final platform in DualPlatform.values) {
      final support = DualPlatformSupport.forTest(platform);
      final android = platform == DualPlatform.android;
      expect(
        support.backend,
        android ? dualBackend : 'http://127.0.0.1:28080/',
      );
      expect(support.relayHost, android ? '10.0.2.2' : '127.0.0.1');
      expect(
        support.runtimePath('dual-runtime-role'),
        '${android ? '/data/user/0/com.kong373.voice_social_app/cache' : Directory.systemTemp.path}/dual-runtime-role',
      );
      expect(
        support.runtimePath('dual-runtime-relay-token'),
        endsWith('/dual-runtime-relay-token'),
      );
      expect(() => support.runtimePath('../other'), throwsStateError);
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      expect(DualPlatformSupport.current, throwsStateError);
    }
  });

  test(
    'runtime token rejects missing, short and embedded whitespace without echo',
    () async {
      final token = List.filled(48, 'x').join();
      expect(await readDualRuntimeToken(read: () async => '$token\n'), token);
      for (final value in ['', 'short', '$token $token', '$token\n$token']) {
        await expectLater(
          readDualRuntimeToken(read: () async => value),
          throwsStateError,
        );
      }
      await expectLater(
        readDualRuntimeToken(
          read: () async => throw const FileSystemException('private'),
        ),
        throwsStateError,
      );
    },
  );
}
