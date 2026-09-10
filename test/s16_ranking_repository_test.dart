import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/backend_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 's16_ranking_fixtures.dart';

void main() {
  test(
    'logged out or invalid pagination is rejected before any network call',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var actor = 0, calls = 0;
      server.listen((request) async {
        calls++;
        await request.drain<void>();
        await reply(request, rankingWire(total: 0));
      });
      final repository = BackendDynamicRepository(
        apiClient: client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => actor,
      );
      await expectLater(
        repository.fetchRanking(
          board: RankingBoard.charm,
          period: RankingPeriod.day,
        ),
        throwsA(isA<ApiException>()),
      );
      actor = 10001;
      for (final (page, size) in [
        (0, 20),
        (1, 0),
        (1, 51),
        (2147483648, 1),
        (2147483647, 50),
      ]) {
        await expectLater(
          repository.fetchRanking(
            board: RankingBoard.charm,
            period: RankingPeriod.day,
            page: page,
            pageSize: size,
          ),
          throwsA(isA<ApiException>()),
        );
      }
      expect(calls, 0);
    },
  );
  test('retired contribution query never reaches the network', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var calls = 0;
    server.listen((request) async {
      calls++;
      await request.drain<void>();
      await reply(
        request,
        rankingWire(board: RankingBoard.contribution, total: 0),
      );
    });
    final repository = BackendDynamicRepository(
      apiClient: client(server),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => 10001,
    );
    await expectLater(
      repository.fetchRanking(
        board: RankingBoard.contribution,
        period: RankingPeriod.day,
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'retired code',
          41001,
        ),
      ),
    );
    expect(calls, 0);
  });
  for (final board in RankingBoard.values.where(
    (value) => value != RankingBoard.contribution,
  )) {
    for (final period in RankingPeriod.values) {
      test(
        'real HTTP ${board.name}/${period.name} requests page2 and preserves exact score',
        () async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(() => server.close(force: true));
          final calls = <Object?>[];
          server.listen((request) async {
            expect(
              request.headers.value(HttpHeaders.authorizationHeader),
              'Bearer A',
            );
            expect(request.method, 'POST');
            expect(request.uri.path, switch (board) {
              RankingBoard.charm => '/app-api/rankinglist/charmrank',
              RankingBoard.wealth => '/app-api/rankinglist/wealthrank',
              RankingBoard.room => '/app-api/dfrank/queryRoomDfRank',
              RankingBoard.contribution =>
                '/app-api/rankinglist/contribuitonrank',
            });
            calls.add(jsonDecode(await utf8.decoder.bind(request).join()));
            await reply(
              request,
              rankingWire(
                board: board,
                period: period,
                page: 2,
                size: 1,
                total: 2,
                score: '184467440737095516150',
              ),
            );
          });
          final repository = BackendDynamicRepository(
            apiClient: client(server),
            routes: const BackendRouteCatalog(),
            currentUserIdProvider: () => 10001,
          );
          final result = await repository.fetchRanking(
            board: board,
            period: period,
            page: 2,
            pageSize: 1,
          );
          expect(calls.single, {
            'pageNum': 2,
            'pageSize': 1,
            if (board.isGiftValue) 'period': period.backendValue,
          });
          expect(result.entries.single.rank, 2);
          if (board.isGiftValue)
            expect(
              result.entries.single.displayValue,
              '1844674407370955161.50 元',
            );
          else
            expect(result.entries.single.value, 700);
        },
      );
    }
  }
  test(
    'malformed HTTP response does not become an empty or mock success',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        await reply(request, {...rankingWire(), 'scoreUnit': 'COINS'});
      });
      final repository = BackendDynamicRepository(
        apiClient: client(server),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );
      await expectLater(
        repository.fetchRanking(
          board: RankingBoard.charm,
          period: RankingPeriod.day,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'late A success is rejected after A→B→A generation, with no reused Future',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final started = Completer<void>(), release = Completer<void>();
      var actor = 10001, generation = 1, calls = 0;
      final headers = <String?>[];
      server.listen((request) async {
        headers.add(request.headers.value(HttpHeaders.authorizationHeader));
        await request.drain<void>();
        if (++calls == 1) {
          started.complete();
          await release.future;
        }
        await reply(request, rankingWire(total: 0));
      });
      final repository = BackendDynamicRepository(
        apiClient: client(server, auth: () => 'Bearer $actor'),
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => actor,
        identityGeneration: () => generation,
      );
      final old = expectLater(
        repository.fetchRanking(
          board: RankingBoard.charm,
          period: RankingPeriod.day,
        ),
        throwsA(isA<ApiException>()),
      );
      await started.future;
      actor = 20002;
      generation++;
      await repository.fetchRanking(
        board: RankingBoard.charm,
        period: RankingPeriod.day,
      );
      actor = 10001;
      generation++;
      await repository.fetchRanking(
        board: RankingBoard.charm,
        period: RankingPeriod.day,
      );
      release.complete();
      await old;
      expect(headers, ['Bearer 10001', 'Bearer 20002', 'Bearer 10001']);
    },
  );
  test('delayed openUrl cannot send A query with B Authorization', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var calls = 0, actor = 10001, generation = 1;
    server.listen((request) async {
      calls++;
      await request.drain<void>();
      await reply(request, rankingWire(total: 0));
    });
    final transport = DelayedRankingClient();
    addTearDown(() => transport.close(force: true));
    final repository = BackendDynamicRepository(
      apiClient: client(
        server,
        auth: () => 'Bearer $actor',
        transport: transport,
      ),
      routes: const BackendRouteCatalog(),
      currentUserIdProvider: () => actor,
      identityGeneration: () => generation,
    );
    final result = expectLater(
      repository.fetchRanking(
        board: RankingBoard.charm,
        period: RankingPeriod.day,
      ),
      throwsA(isA<ApiException>()),
    );
    await transport.started.future;
    actor = 20002;
    generation++;
    transport.release.complete();
    await result;
    expect(calls, 0);
  });
  for (final switchIdentity in [true, false]) {
    test(
      '401 recovery ${switchIdentity ? "rejects switched identity" : "allows same identity refresh"}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var actor = 10001, generation = 1, calls = 0;
        var auth = 'Bearer A-old';
        final headers = <String?>[];
        server.listen((request) async {
          headers.add(request.headers.value(HttpHeaders.authorizationHeader));
          await request.drain<void>();
          if (++calls == 1) {
            request.response.statusCode = 401;
            await reply(request, null, code: 40101);
          } else
            await reply(request, rankingWire(total: 0));
        });
        final api = client(server, auth: () => auth)
          ..setUnauthorizedRecovery(() async {
            if (switchIdentity) {
              actor = 20002;
              generation++;
              auth = 'Bearer B';
            } else
              auth = 'Bearer A-new';
            return true;
          });
        final repository = BackendDynamicRepository(
          apiClient: api,
          routes: const BackendRouteCatalog(),
          currentUserIdProvider: () => actor,
          identityGeneration: () => generation,
        );
        final result = repository.fetchRanking(
          board: RankingBoard.charm,
          period: RankingPeriod.day,
        );
        if (switchIdentity) {
          await expectLater(result, throwsA(isA<ApiException>()));
          expect(headers, ['Bearer A-old']);
        } else {
          await result;
          expect(headers, ['Bearer A-old', 'Bearer A-new']);
        }
      },
    );
  }
  test(
    'S16 sends the confirmed period contract instead of legacy aliases',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      Object? sent;
      server.listen((request) async {
        sent = jsonDecode(await utf8.decoder.bind(request).join());
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'code': 200,
            'data': {
              'list': <Object?>[],
              'records': <Object?>[],
              'current': 1,
              'pageSize': 20,
              'total': 0,
              'pages': 0,
              'metric': 'CHARM',
              'serverAuthoritative': true,
              'period': 'WEEK',
              'timezone': 'Asia/Shanghai',
              'startInclusive': '2026-09-06T16:00:00Z',
              'endExclusive': '2026-09-13T16:00:00Z',
              'serverNow': '2026-09-09T04:00:00Z',
              'scoreUnit': 'CNY_FEN',
              'scoreEncoding': 'DECIMAL_STRING',
              'valueBasis': 'GIFT_VALUE',
              'excludedUnvaluedTransfers': 0,
            },
          }),
        );
        await request.response.close();
      });
      final client = ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'android',
        clientInnerVersion: 'test',
        authorizationProvider: () => 'Bearer contract-test-token',
      );
      final repository = BackendDynamicRepository(
        apiClient: client,
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => 10001,
      );
      await repository.fetchRanking(
        board: RankingBoard.charm,
        period: RankingPeriod.week,
      );
      expect(sent, {'period': 'WEEK', 'pageNum': 1, 'pageSize': 20});
    },
  );
}

ApiClient client(
  HttpServer server, {
  String Function()? auth,
  HttpClient? transport,
}) => ApiClient(
  baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
  clientType: 'android',
  clientInnerVersion: 'test',
  authorizationProvider: auth ?? () => 'Bearer A',
  httpClient: transport,
);
Future<void> reply(HttpRequest request, Object? data, {int code = 200}) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(
    jsonEncode({'code': code, 'message': 'test', 'data': data}),
  );
  await request.response.close();
}

class DelayedRankingClient implements HttpClient {
  final delegate = HttpClient();
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    started.complete();
    await release.future;
    return delegate.openUrl(method, url);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
