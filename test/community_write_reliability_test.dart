import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/community/data/backend_community_repository.dart';
import 'package:voice_social_app/features/community/domain/community_request_id.dart';

void main() {
  test('community request ids are secure-shaped, bounded, and classified', () {
    final String first = newCommunityRequestId('flutter-community-test');
    final String second = newCommunityRequestId('flutter-community-test');
    expect(first, matches(RegExp(r'^flutter-community-test-[0-9a-f]{32}$')));
    expect(first.length, lessThanOrEqualTo(80));
    expect(second, isNot(first));

    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.timeout,
          message: 'response lost',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40901,
          httpStatus: 409,
          message: 'unknown commit',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40902,
          httpStatus: 409,
          message: 'unknown commit',
        ),
      ),
      isTrue,
    );
    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40903,
          httpStatus: 409,
          message: 'definitive conflict',
        ),
      ),
      isFalse,
    );
    expect(
      shouldRetainCommunityWriteRequest(
        const ApiException(
          kind: ApiFailureKind.validation,
          code: 40001,
          httpStatus: 400,
          message: 'invalid',
        ),
      ),
      isFalse,
    );
  });

  test(
    'same community intent single-flights and rotates after success',
    () async {
      final Completer<void> release = Completer<void>();
      final Completer<void> firstSeen = Completer<void>();
      int applyCalls = 0;
      final _Harness harness = await _Harness.start((
        RequestRecord request,
      ) async {
        if (request.path.endsWith('/applyForMembership')) {
          applyCalls += 1;
          if (applyCalls == 1) {
            firstSeen.complete();
            await release.future;
          }
          return _Reply.ok(<String, Object?>{
            'applicationId': 'application-1',
            'guildId': 'guild-1',
            'status': 'PENDING',
          });
        }
        return _Reply.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      final Future<void> first = harness.repository.applyToJoinGuild('guild-1');
      await firstSeen.future;
      final Future<void> second = harness.repository.applyToJoinGuild(
        'guild-1',
      );
      expect(
        harness.requests.where(
          (RequestRecord item) => item.path.endsWith('/applyForMembership'),
        ),
        hasLength(1),
      );
      release.complete();
      await Future.wait(<Future<void>>[first, second]);

      await harness.repository.applyToJoinGuild('guild-1');
      final List<RequestRecord> writes = harness.requests
          .where(
            (RequestRecord item) => item.path.endsWith('/applyForMembership'),
          )
          .toList(growable: false);
      expect(writes, hasLength(2));
      expect(writes[0].requestId, isNotEmpty);
      expect(writes[0].requestId, isNot(writes[1].requestId));
    },
  );

  test(
    'ambiguous community retry retains id while definitive conflict rotates',
    () async {
      int attempts = 0;
      final _Harness harness = await _Harness.start((RequestRecord request) {
        if (request.path.endsWith('/applyForMembership')) {
          attempts += 1;
          if (attempts == 1) {
            return const _Reply(
              statusCode: 500,
              code: 50001,
              message: 'committed but response unknown',
              data: null,
            );
          }
          if (attempts == 3) {
            return const _Reply(
              statusCode: 409,
              code: 40903,
              message: 'already resolved',
              data: null,
            );
          }
          return _Reply.ok(<String, Object?>{
            'applicationId': 'application-1',
            'guildId': 'guild-1',
            'status': 'PENDING',
          });
        }
        return _Reply.ok(<String, Object?>{});
      });
      addTearDown(harness.close);

      await expectLater(
        harness.repository.applyToJoinGuild('guild-1'),
        throwsA(isA<ApiException>()),
      );
      await harness.repository.applyToJoinGuild('guild-1');
      await expectLater(
        harness.repository.applyToJoinGuild('guild-1'),
        throwsA(isA<ApiException>()),
      );
      await harness.repository.applyToJoinGuild('guild-1');

      final List<RequestRecord> writes = harness.requests
          .where(
            (RequestRecord item) => item.path.endsWith('/applyForMembership'),
          )
          .toList(growable: false);
      expect(writes, hasLength(4));
      expect(writes[0].requestId, writes[1].requestId);
      expect(writes[1].requestId, isNot(writes[2].requestId));
      expect(writes[2].requestId, isNot(writes[3].requestId));
    },
  );

  test('401 recovery replays the same community request id', () async {
    int recoveryCalls = 0;
    int attempts = 0;
    final _Harness harness = await _Harness.start(
      (RequestRecord request) {
        if (request.path.endsWith('/applyForMembership')) {
          attempts += 1;
          if (attempts == 1) {
            return const _Reply(
              statusCode: 401,
              code: 401,
              message: 'expired',
              data: null,
            );
          }
          return _Reply.ok(<String, Object?>{
            'applicationId': 'application-1',
            'guildId': 'guild-1',
            'status': 'PENDING',
          });
        }
        return _Reply.ok(<String, Object?>{});
      },
      unauthorizedRecovery: () async {
        recoveryCalls += 1;
        return true;
      },
    );
    addTearDown(harness.close);

    await harness.repository.applyToJoinGuild('guild-1');

    final List<RequestRecord> writes = harness.requests
        .where(
          (RequestRecord item) => item.path.endsWith('/applyForMembership'),
        )
        .toList(growable: false);
    expect(recoveryCalls, 1);
    expect(writes, hasLength(2));
    expect(writes[0].requestId, isNotEmpty);
    expect(writes[0].requestId, writes[1].requestId);
  });

  test('conflicting member mutations serialize per member entity', () async {
    final Completer<void> release = Completer<void>();
    final Completer<void> firstSeen = Completer<void>();
    int calls = 0;
    final _Harness harness = await _Harness.start((
      RequestRecord request,
    ) async {
      if (request.path.endsWith('/memberBanOrUnseal')) {
        calls += 1;
        if (calls == 1) {
          firstSeen.complete();
          await release.future;
        }
        final Map<String, Object?> body = request.body! as Map<String, Object?>;
        return _Reply.ok(<String, Object?>{
          'guildId': 'guild-1',
          'userId': 7,
          'muted': body['muted'],
        });
      }
      return _Reply.ok(<String, Object?>{});
    });
    addTearDown(harness.close);

    final Future<void> mute = harness.repository.setGuildMemberMuted(
      guildId: 'guild-1',
      userId: 7,
      muted: true,
    );
    await firstSeen.future;
    final Future<void> unmute = harness.repository.setGuildMemberMuted(
      guildId: 'guild-1',
      userId: 7,
      muted: false,
    );
    expect(calls, 1);
    release.complete();
    await Future.wait(<Future<void>>[mute, unmute]);

    final List<RequestRecord> writes = harness.requests
        .where((RequestRecord item) => item.path.endsWith('/memberBanOrUnseal'))
        .toList(growable: false);
    expect(writes, hasLength(2));
    expect((writes[0].body! as Map<String, Object?>)['muted'], isTrue);
    expect((writes[1].body! as Map<String, Object?>)['muted'], isFalse);
    expect(writes[0].requestId, isNot(writes[1].requestId));
  });
}

class _Harness {
  _Harness._(this.server, this.requests, this.repository);

  final HttpServer server;
  final List<RequestRecord> requests;
  final BackendCommunityRepository repository;

  static Future<_Harness> start(
    FutureOr<_Reply> Function(RequestRecord request) handler, {
    UnauthorizedRecovery? unauthorizedRecovery,
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<RequestRecord> requests = <RequestRecord>[];
    final BackendCommunityRepository repository = BackendCommunityRepository(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer reliability-test',
        unauthorizedRecovery: unauthorizedRecovery,
      ),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
      identityGeneration: () => 1,
    );
    final _Harness harness = _Harness._(server, requests, repository);
    server.listen((HttpRequest request) async {
      final String rawBody = await utf8.decoder.bind(request).join();
      final Object? decodedBody = rawBody.trim().isEmpty
          ? null
          : jsonDecode(rawBody);
      final RequestRecord record = RequestRecord(
        method: request.method,
        path: request.uri.path,
        requestId: request.headers.value('X-Request-Id') ?? '',
        body: decodedBody is Map
            ? Map<String, Object?>.from(decodedBody)
            : decodedBody,
      );
      requests.add(record);
      final _Reply reply = await handler(record);
      request.response.statusCode = reply.statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'code': reply.code,
          'message': reply.message,
          'data': reply.data,
        }),
      );
      await request.response.close();
    });
    return harness;
  }

  Future<void> close() => server.close(force: true);
}

class RequestRecord {
  const RequestRecord({
    required this.method,
    required this.path,
    required this.requestId,
    required this.body,
  });

  final String method;
  final String path;
  final String requestId;
  final Object? body;
}

class _Reply {
  const _Reply({
    required this.statusCode,
    required this.code,
    required this.message,
    required this.data,
  });

  const _Reply.ok(Object? data)
    : statusCode = 200,
      code = 200,
      message = 'OK',
      data = data;

  final int statusCode;
  final int code;
  final String message;
  final Object? data;
}
