import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/media/media_identity.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'support/media_http_fakes.dart';

void main() {
  test(
    'invalid scope still observes an already-started late failing operation',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      actor.change(2);
      await expectLater(
        scope.wait(Future<int>.error(StateError('late I/O'))),
        throwsA(isA<ApiException>()),
      );
      await Future<void>.delayed(Duration.zero); // no orphan asynchronous error
    },
  );
  test(
    'refresh notification keeps tuple; ABA never revives old scope',
    () async {
      final actor = TestMediaIdentity();
      final scope = actor.scope();
      addTearDown(scope.dispose);
      actor.refreshToken();
      expect(await scope.wait(Future.value(7)), 7);
      int aborts = 0;
      scope.onCancel(() => aborts++);
      final pending = scope.wait(Completer<int>().future);
      final expectation = expectLater(pending, throwsA(isA<ApiException>()));
      actor.change(2);
      actor.change(1);
      await expectation;
      expect(aborts, 1);
      expect(scope.isCurrent, isFalse);
      expect(scope.check, throwsA(MediaIdentityScope.invalid));
    },
  );
}
