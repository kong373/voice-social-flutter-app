import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/community/data/backend_community_repository.dart';

import 'support/media_http_fakes.dart';

const _guild = 'guild-test-A';
const _realName = '合成测试甲';
const _document = 'SYNTHETIC-DOCUMENT-A';
const _realNameReceipt = <String, Object?>{
  'status': 'PENDING',
  'statusCode': 1,
  'needsAgeResubmission': false,
  'canSubmit': false,
  'providerStatus': 'FIRST_PARTY_REVIEW',
  'reviewStatus': 'FIRST_PARTY_REVIEW',
  'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
  'providerInvocation': false,
};

final _writes = <String, Future<void> Function(_Fixture)>{
  'apply': (f) => f.community.applyToJoinGuild(_guild),
  'quit': (f) => f.community.quitGuild(_guild),
  'resolve': (f) => f.community.resolveGuildApplication(
    applicationId: 'application-A',
    accepted: true,
  ),
  'mute': (f) =>
      f.community.setGuildMemberMuted(guildId: _guild, userId: 7, muted: true),
  'remove': (f) => f.community.removeGuildMember(guildId: _guild, userId: 7),
  'real-name': (f) =>
      f.compliance.submitRealName(realName: _realName, idNumber: _document),
};

void main() {
  for (final entry in _writes.entries) {
    test('${entry.key} pending open ABA never sends headers or body', () async {
      final fixture = _Fixture(_reply);
      final opened = Completer<void>();
      final release = Completer<void>();
      fixture.http.beforeOpen = (_) {
        opened.complete();
        return release.future;
      };
      final result = _outcome(entry.value(fixture));
      await opened.future;
      fixture.actor.change(2);
      fixture.actor.change(1);
      release.complete();
      final error = await result;
      final request = fixture.http.requests.single;
      expect(request.headers.value('Authorization'), isNull);
      expect(request.headers.value('X-Request-Id'), isNull);
      expect(request.body, isEmpty);
      expect(request.closes, 0);
      expect(request.aborted, true);
      expect(error, _identityFailure);
    });
  }

  test('real-name A to B never submits A document with B token', () async {
    final fixture = _Fixture(_reply);
    final opened = Completer<void>();
    final release = Completer<void>();
    fixture.http.beforeOpen = (_) {
      opened.complete();
      return release.future;
    };
    final result = _outcome(_writes['real-name']!(fixture));
    await opened.future;
    fixture.actor.change(2);
    release.complete();
    final error = await result;
    expect(fixture.http.requests.single.body, isEmpty);
    expect(fixture.http.requests.single.headers.value('Authorization'), isNull);
    expect(error, _identityFailure);
  });

  for (final fails in [false, true]) {
    test(
      'queued guild write is invalidated after old ${fails ? 'failure' : 'success'} and ABA',
      () async {
        final gate = Completer<HttpClientResponse>();
        final firstStarted = Completer<void>();
        final fixture = _Fixture((request) {
          if (request.uri.path.endsWith('/applyForMembership')) {
            firstStarted.complete();
            return gate.future;
          }
          return _reply(request);
        });
        final first = _outcome(fixture.community.applyToJoinGuild(_guild));
        await firstStarted.future;
        final queued = _outcome(fixture.community.quitGuild(_guild));
        fixture.actor.change(2);
        fixture.actor.change(1);
        if (fails) {
          gate.completeError(const SocketException('old transport failure'));
        } else {
          gate.complete(_reply(fixture.http.requests.first));
        }
        final errors = await Future.wait([first, queued]);
        expect(
          fixture.http.requests,
          hasLength(1),
          reason: 'The stale queue must stop before openUrl.',
        );
        expect(errors, everyElement(_identityFailure));
      },
    );
  }

  for (final kind in ['apply', 'real-name']) {
    for (final changeIdentity in [false, true]) {
      test(
        '$kind 401 recovery ${changeIdentity ? 'ABA forbids replay' : 'same identity replays original intent'}',
        () async {
          var count = 0;
          final fixture = _Fixture(
            (request) {
              if (++count == 1)
                return MediaFakeResponse.json(null, status: 401, code: 401);
              return _reply(request);
            },
            refresh: (actor) async {
              if (changeIdentity) {
                actor.change(2);
                actor.change(1);
              } else {
                actor.refreshToken();
              }
              return true;
            },
          );
          final error = await _outcome(_writes[kind]!(fixture));
          if (changeIdentity) {
            expect(error, _identityFailure);
            expect(fixture.http.requests, hasLength(1));
          } else {
            expect(error, isNull);
            final requests = fixture.http.requests;
            expect(requests, hasLength(2));
            expect(requests.last.body, requests.first.body);
            expect(
              requests.last.headers.value('X-Request-Id'),
              requests.first.headers.value('X-Request-Id'),
            );
            expect(
              requests.last.headers.value('Authorization'),
              fixture.actor.token,
            );
          }
        },
      );
    }

    test(
      '$kind late transport error after A to B is reported as obsolete identity',
      () async {
        final gate = Completer<HttpClientResponse>();
        final started = Completer<void>();
        final fixture = _Fixture((_) {
          started.complete();
          return gate.future;
        });
        final operation = _outcome(_writes[kind]!(fixture));
        await started.future;
        fixture.actor.change(2);
        gate.completeError(const SocketException('STALE-TRANSPORT-ERROR'));
        final error = await operation;
        expect(error, _identityFailure);
        expect(
          (error as ApiException).message,
          isNot(contains('STALE-TRANSPORT-ERROR')),
        );
        expect(fixture.http.requests, hasLength(1));
      },
    );

    test(
      '$kind new generation does not share the old in-flight result',
      () async {
        final firstStarted = Completer<void>();
        final gate = Completer<HttpClientResponse>();
        var count = 0;
        final fixture = _Fixture((request) {
          if (++count == 1) {
            firstStarted.complete();
            return gate.future;
          }
          return _reply(request);
        });
        final first = _outcome(_writes[kind]!(fixture));
        await firstStarted.future;
        fixture.actor.change(2);
        fixture.actor.change(1);
        final next = _outcome(_writes[kind]!(fixture));
        gate.complete(_reply(fixture.http.requests.first));
        final errors = await Future.wait([first, next]);
        expect(fixture.http.requests, hasLength(2));
        expect(errors.first, _identityFailure);
        expect(errors.last, isNull);
        final requests = fixture.http.requests;
        expect(
          requests.last.headers.value('X-Request-Id'),
          isNot(requests.first.headers.value('X-Request-Id')),
        );
      },
    );

    test(
      '$kind unknown same-identity refresh keeps key but next generation does not',
      () async {
        var count = 0;
        final fixture = _Fixture((request) {
          if (++count <= 2) throw const SocketException('unknown');
          return _reply(request);
        });
        expect(await _outcome(_writes[kind]!(fixture)), isA<ApiException>());
        fixture.actor.refreshToken();
        expect(await _outcome(_writes[kind]!(fixture)), isA<ApiException>());
        fixture.actor.change(2);
        fixture.actor.change(1);
        await _writes[kind]!(fixture);
        final requests = fixture.http.requests;
        expect(requests, hasLength(3));
        expect(requests[1].body, requests[0].body);
        expect(
          requests[1].headers.value('X-Request-Id'),
          requests[0].headers.value('X-Request-Id'),
        );
        expect(
          requests[2].headers.value('X-Request-Id'),
          isNot(requests[0].headers.value('X-Request-Id')),
        );
      },
    );
  }

  test(
    'new actor queue runs independently while the stale guild queue stays blocked',
    () async {
      final firstStarted = Completer<void>();
      final newStarted = Completer<void>();
      final gate = Completer<HttpClientResponse>();
      var count = 0;
      final fixture = _Fixture((request) {
        if (++count == 1) {
          firstStarted.complete();
          return gate.future;
        }
        newStarted.complete();
        return _reply(request);
      });
      final first = _outcome(fixture.community.applyToJoinGuild(_guild));
      await firstStarted.future;
      final staleQueue = _outcome(fixture.community.quitGuild(_guild));
      fixture.actor.change(2);
      final next = _outcome(fixture.community.quitGuild(_guild));
      try {
        await newStarted.future.timeout(const Duration(seconds: 2));
        expect(await next, isNull);
        expect(
          fixture.http.requests.last.headers.value('Authorization'),
          fixture.actor.token,
        );
      } finally {
        gate.complete(_reply(fixture.http.requests.first));
        expect(await first, _identityFailure);
        expect(await staleQueue, _identityFailure);
      }
      expect(fixture.http.requests, hasLength(2));
    },
  );

  test(
    'missing partial or invalid identity injection fails closed before any HTTP',
    () async {
      final actor = TestMediaIdentity();
      addTearDown(actor.dispose);
      final http = MediaFakeHttp(_reply);
      for (final providers in <(int? Function()?, int Function()?)>[
        (null, null),
        (() => 1, null),
        (null, () => 1),
        (() => null, () => 1),
        (() => 0, () => 1),
        (() => 1, () => -1),
      ]) {
        final community = BackendCommunityRepository(
          apiClient: http.api(actor),
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: providers.$1,
          identityGeneration: providers.$2,
        );
        final compliance = BackendAccountComplianceRepository(
          apiClient: http.api(actor),
          currentUserIdProvider: providers.$1,
          identityGeneration: providers.$2,
        );
        await expectLater(
          Future<void>.sync(() => community.applyToJoinGuild(_guild)),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          Future<void>.sync(
            () => compliance.submitRealName(
              realName: _realName,
              idNumber: _document,
            ),
          ),
          throwsA(isA<ApiException>()),
        );
      }
      expect(http.opens, 0);
      expect(http.requests, isEmpty);
    },
  );
}

final _identityFailure = isA<ApiException>().having(
  (e) => e.kind,
  'kind',
  ApiFailureKind.unauthorized,
);

Future<Object?> _outcome(Future<void> operation) =>
    operation.then<Object?>((_) => null, onError: (Object error) => error);

HttpClientResponse _reply(MediaFakeRequest request) {
  final body = jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;
  final data = request.uri.path.endsWith('/real-name')
      ? _realNameReceipt
      : <String, Object?>{
          'guildId': body['guildId'] ?? _guild,
          'applicationId': body['applicationId'] ?? 'application-A',
          'status': body.containsKey('approved')
              ? 'APPROVED'
              : request.uri.path.endsWith('/quitGuild')
              ? 'LEFT'
              : 'PENDING',
          'left': true,
          'userId': body['userId'],
          'muted': body['muted'],
          'removed': true,
          'providerInvocation': false,
        };
  return MediaFakeResponse.json(data);
}

class _Fixture {
  _Fixture(
    FutureOr<HttpClientResponse> Function(MediaFakeRequest) handler, {
    Future<bool> Function(TestMediaIdentity)? refresh,
  }) {
    http = MediaFakeHttp(handler);
    final api = http.api(
      actor,
      refresh: refresh == null ? null : () => refresh(actor),
    );
    community = BackendCommunityRepository(
      apiClient: api,
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => actor.user,
      identityGeneration: () => actor.generation,
    );
    compliance = BackendAccountComplianceRepository(
      apiClient: api,
      currentUserIdProvider: () => actor.user,
      identityGeneration: () => actor.generation,
    );
    addTearDown(actor.dispose);
  }

  final actor = TestMediaIdentity();
  late final MediaFakeHttp http;
  late final BackendCommunityRepository community;
  late final BackendAccountComplianceRepository compliance;
}
