import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/room_write_guard.dart';

void main() {
  test(
    'same room intent is single-flight with a stable bounded request id',
    () async {
      final RoomWriteGuard guard = RoomWriteGuard(scope: 'room-test');
      final Completer<void> gate = Completer<void>();
      int calls = 0;
      final List<Map<String, String>> headers = <Map<String, String>>[];

      Future<void> action(Map<String, String> requestHeaders) async {
        calls += 1;
        headers.add(requestHeaders);
        await gate.future;
      }

      final Future<void> first = guard.run<void>(
        intent: 'mute:9527:10002:true',
        action: action,
      );
      final Future<void> replay = guard.run<void>(
        intent: 'mute:9527:10002:true',
        action: action,
      );
      expect(identical(first, replay), isFalse);
      gate.complete();
      await Future.wait(<Future<void>>[first, replay]);

      expect(calls, 1);
      expect(
        headers.single['X-Request-Id'],
        matches(RegExp(r'^room-test-[0-9a-f]{32}$')),
      );
      expect(headers.single['X-Request-Id']!.length, lessThanOrEqualTo(128));
    },
  );

  test(
    'request-id fingerprints are released after a completed write',
    () async {
      final RoomWriteGuard guard = RoomWriteGuard(scope: 'room-test');
      final List<String> fingerprints = <String>[];

      await guard.run<void>(
        intent: 'first-intent',
        requestId: 'explicit-lifecycle-id',
        fingerprint: 'first-fingerprint',
        action: (_) async => fingerprints.add('first'),
      );
      await guard.run<void>(
        intent: 'second-intent',
        requestId: 'explicit-lifecycle-id',
        fingerprint: 'second-fingerprint',
        action: (_) async => fingerprints.add('second'),
      );

      expect(fingerprints, <String>['first', 'second']);
    },
  );

  test(
    'different room intents are serialized and a failure does not poison the queue',
    () async {
      final RoomWriteGuard guard = RoomWriteGuard(scope: 'room-test');
      final List<String> order = <String>[];

      final Future<void> failed = guard.run<void>(
        intent: 'first',
        action: (_) async {
          order.add('first');
          throw const ApiException(
            kind: ApiFailureKind.business,
            message: 'rejected',
          );
        },
      );
      final Future<void> second = guard.run<void>(
        intent: 'second',
        action: (_) async => order.add('second'),
      );

      await expectLater(failed, throwsA(isA<ApiException>()));
      await second;
      expect(order, <String>['first', 'second']);
    },
  );

  test(
    'successful same-intent submissions rotate to a fresh request id',
    () async {
      final RoomWriteGuard guard = RoomWriteGuard(scope: 'room-test');
      final List<String> ids = <String>[];

      await guard.run<void>(
        intent: 'close:9527',
        action: (Map<String, String> headers) async =>
            ids.add(headers['X-Request-Id']!),
      );
      await guard.run<void>(
        intent: 'close:9527',
        action: (Map<String, String> headers) async =>
            ids.add(headers['X-Request-Id']!),
      );

      expect(ids, hasLength(2));
      expect(ids[0], isNot(ids[1]));
    },
  );

  test(
    'ambiguous failure retains its id for the next same-intent retry',
    () async {
      final RoomWriteGuard guard = RoomWriteGuard(scope: 'room-test');
      final List<String> ids = <String>[];
      int attempts = 0;

      Future<void> action(Map<String, String> headers) async {
        ids.add(headers['X-Request-Id']!);
        attempts += 1;
        if (attempts == 1) {
          throw const ApiException(
            kind: ApiFailureKind.timeout,
            message: 'response lost',
          );
        }
      }

      await expectLater(
        guard.run<void>(intent: 'mute:9527:10002:true', action: action),
        throwsA(isA<ApiException>()),
      );
      await guard.run<void>(intent: 'mute:9527:10002:true', action: action);

      expect(ids, hasLength(2));
      expect(ids[0], ids[1]);
    },
  );

  test('unclassified failures conservatively retain the request id', () async {
    final RoomWriteGuard guard = RoomWriteGuard(scope: 'room-test');
    final List<String> ids = <String>[];
    int attempts = 0;

    Future<void> action(Map<String, String> headers) async {
      ids.add(headers['X-Request-Id']!);
      attempts += 1;
      if (attempts == 1) {
        throw StateError('transport result unavailable');
      }
    }

    await expectLater(
      guard.run<void>(intent: 'gift:room:user:gift:1', action: action),
      throwsA(isA<StateError>()),
    );
    await guard.run<void>(intent: 'gift:room:user:gift:1', action: action);

    expect(ids, hasLength(2));
    expect(ids[1], ids[0]);
  });

  test(
    'backend idempotency pending conflicts retain the original request id',
    () async {
      final RoomWriteGuard guard = RoomWriteGuard(scope: 'room-test');
      final List<String> ids = <String>[];
      int attempts = 0;

      Future<void> action(Map<String, String> headers) async {
        ids.add(headers['X-Request-Id']!);
        attempts += 1;
        if (attempts <= 2) {
          throw ApiException(
            kind: ApiFailureKind.conflict,
            code: attempts == 1 ? 40901 : 40902,
            httpStatus: 409,
            message: attempts == 1 ? '幂等状态缺失' : '请求仍在处理中',
          );
        }
      }

      await expectLater(
        guard.run<void>(intent: 'create:owner:nonce', action: action),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        guard.run<void>(intent: 'create:owner:nonce', action: action),
        throwsA(isA<ApiException>()),
      );
      await guard.run<void>(intent: 'create:owner:nonce', action: action);

      expect(ids, hasLength(3));
      expect(ids.toSet(), hasLength(1));
    },
  );

  test('idempotency fingerprint conflicts rotate the request id', () async {
    final RoomWriteGuard guard = RoomWriteGuard(scope: 'room-test');
    final List<String> ids = <String>[];
    int attempts = 0;

    Future<void> action(Map<String, String> headers) async {
      ids.add(headers['X-Request-Id']!);
      attempts += 1;
      if (attempts == 1) {
        throw const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40903,
          httpStatus: 409,
          message: '同一幂等键的请求参数不一致',
        );
      }
    }

    await expectLater(
      guard.run<void>(intent: 'update:room:topic', action: action),
      throwsA(isA<ApiException>()),
    );
    await guard.run<void>(intent: 'update:room:topic', action: action);

    expect(ids, hasLength(2));
    expect(ids[0], isNot(ids[1]));
  });

  test(
    'definitive failure rotates the id for the next same-intent submission',
    () async {
      final RoomWriteGuard guard = RoomWriteGuard(scope: 'room-test');
      final List<String> ids = <String>[];
      int attempts = 0;

      Future<void> action(Map<String, String> headers) async {
        ids.add(headers['X-Request-Id']!);
        attempts += 1;
        if (attempts == 1) {
          throw const ApiException(
            kind: ApiFailureKind.business,
            message: 'permission denied',
          );
        }
      }

      await expectLater(
        guard.run<void>(intent: 'kick:9527:10002', action: action),
        throwsA(isA<ApiException>()),
      );
      await guard.run<void>(intent: 'kick:9527:10002', action: action);

      expect(ids, hasLength(2));
      expect(ids[0], isNot(ids[1]));
    },
  );

  test(
    'explicit negative mutation authority is not treated as HTTP success',
    () {
      expect(
        () => RoomWriteGuard.validateMutationResponse(
          const ApiResponse(
            code: 200,
            message: 'OK',
            data: <String, Object?>{'success': false},
          ),
          operation: '禁言成员',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => RoomWriteGuard.validateMutationResponse(
          const ApiResponse(code: 200, message: 'OK', data: null),
          operation: '禁言成员',
        ),
        returnsNormally,
      );
      expect(
        () => RoomWriteGuard.validateMutationResponse(
          const ApiResponse(
            code: 200,
            message: 'OK',
            data: <String, Object?>{},
          ),
          operation: '关闭房间',
          requiredFields: <String>['roomId', 'status'],
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
