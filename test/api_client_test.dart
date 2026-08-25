import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';

void main() {
  test(
    'api client injects required headers and parses the result envelope',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final Completer<void> handled = Completer<void>();

      server.listen((HttpRequest request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/contract');
        expect(request.headers.value('Client-Type'), 'Android');
        expect(request.headers.value('Client-Inner-Version'), '42');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test',
        );
        final String body = await utf8.decoder.bind(request).join();
        expect(jsonDecode(body), <String, Object?>{'hello': 'world'});

        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': '操作成功',
            'data': <String, Object?>{'accepted': true},
          }),
        );
        await request.response.close();
        handled.complete();
      });

      final ApiClient client = ApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '42',
        authorizationProvider: () => 'Bearer test',
      );
      final ApiResponse response = await client.post(
        '/contract',
        body: <String, Object?>{'hello': 'world'},
      );

      await handled.future;
      expect(response.isSuccess, isTrue);
      expect(response.data, <String, Object?>{'accepted': true});
    },
  );

  test(
    'auth retry reuses the caller supplied idempotency request id',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<String?> requestIds = <String?>[];
      var attempts = 0;

      server.listen((HttpRequest request) async {
        requestIds.add(request.headers.value('X-Request-Id'));
        attempts += 1;
        request.response.headers.contentType = ContentType.json;
        if (attempts == 1) {
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.write(
            jsonEncode(<String, Object?>{
              'code': 401,
              'message': '登录已过期',
              'data': null,
            }),
          );
        } else {
          request.response.write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': '操作成功',
              'data': <String, Object?>{'accepted': true},
            }),
          );
        }
        await request.response.close();
      });

      final ApiClient client = ApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '42',
        authorizationProvider: () => 'Bearer test',
      );
      client.setUnauthorizedRecovery(() async => true);

      final ApiResponse response = await client.post(
        '/contract',
        headers: <String, String>{'X-Request-Id': 'stable-request-1'},
        body: <String, Object?>{'hello': 'world'},
      );

      expect(response.isSuccess, isTrue);
      expect(requestIds, <String?>['stable-request-1', 'stable-request-1']);
    },
  );

  test(
    'auth retry reuses the generated request id when caller omits one',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final List<String?> requestIds = <String?>[];
      var attempts = 0;

      server.listen((HttpRequest request) async {
        requestIds.add(request.headers.value('X-Request-Id'));
        attempts += 1;
        request.response.headers.contentType = ContentType.json;
        if (attempts == 1) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..write(
              jsonEncode(<String, Object?>{
                'code': 401,
                'message': '登录已过期',
                'data': null,
              }),
            );
        } else {
          request.response.write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': '操作成功',
              'data': <String, Object?>{'accepted': true},
            }),
          );
        }
        await request.response.close();
      });

      final ApiClient client = ApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '42',
        authorizationProvider: () => 'Bearer test',
      );
      client.setUnauthorizedRecovery(() async => true);

      final ApiResponse response = await client.post('/contract');

      expect(response.isSuccess, isTrue);
      expect(requestIds, hasLength(2));
      expect(requestIds.first, isNotNull);
      expect(requestIds.first, isNotEmpty);
      expect(requestIds[1], requestIds.first);
    },
  );

  test('401 replay is attempted at most once for a request', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    var attempts = 0;
    server.listen((HttpRequest request) async {
      attempts += 1;
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': 401,
            'message': '登录已过期',
            'data': null,
          }),
        );
      await request.response.close();
    });

    var recoveryCalls = 0;
    final ApiClient client = ApiClient(
      baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '42',
      authorizationProvider: () => 'Bearer test',
    );
    client.setUnauthorizedRecovery(() async {
      recoveryCalls += 1;
      return true;
    });

    ApiException? failure;
    try {
      await client.get('/contract');
    } on ApiException catch (error) {
      failure = error;
    }

    expect(failure?.kind, ApiFailureKind.unauthorized);
    expect(failure?.httpStatus, HttpStatus.unauthorized);
    expect(attempts, 2);
    expect(recoveryCalls, 1);
  });

  test('401 recovery returning false does not replay the request', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    var attempts = 0;
    server.listen((HttpRequest request) async {
      attempts += 1;
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'code': 401,
            'message': '登录已过期',
            'data': null,
          }),
        );
      await request.response.close();
    });

    var recoveryCalls = 0;
    final ApiClient client = ApiClient(
      baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '42',
      authorizationProvider: () => 'Bearer test',
    );
    client.setUnauthorizedRecovery(() async {
      recoveryCalls += 1;
      return false;
    });

    ApiException? failure;
    try {
      await client.get('/contract');
    } on ApiException catch (error) {
      failure = error;
    }

    expect(failure?.kind, ApiFailureKind.unauthorized);
    expect(attempts, 1);
    expect(recoveryCalls, 1);
  });

  test('concurrent 401 responses share one recovery flight', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final Completer<void> recoveryStarted = Completer<void>();
    final Completer<void> secondUnauthorized = Completer<void>();
    final Completer<bool> releaseRecovery = Completer<bool>();
    var requests = 0;
    server.listen((HttpRequest request) async {
      requests += 1;
      request.response.headers.contentType = ContentType.json;
      if (requests <= 2) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write(
            jsonEncode(<String, Object?>{
              'code': 401,
              'message': '登录已过期',
              'data': null,
            }),
          );
        if (requests == 2 && !secondUnauthorized.isCompleted) {
          secondUnauthorized.complete();
        }
      } else {
        request.response.write(
          jsonEncode(<String, Object?>{
            'code': 200,
            'message': 'OK',
            'data': <String, Object?>{'accepted': true},
          }),
        );
      }
      await request.response.close();
    });

    var recoveryCalls = 0;
    final ApiClient client = ApiClient(
      baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '42',
      authorizationProvider: () => 'Bearer test',
    );
    client.setUnauthorizedRecovery(() async {
      recoveryCalls += 1;
      if (!recoveryStarted.isCompleted) {
        recoveryStarted.complete();
      }
      return releaseRecovery.future;
    });

    final Future<ApiResponse> first = client.get('/contract');
    await recoveryStarted.future;
    final Future<ApiResponse> second = client.get('/contract');
    await secondUnauthorized.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(recoveryCalls, 1);
    releaseRecovery.complete(true);

    final List<ApiResponse> responses = await Future.wait(<Future<ApiResponse>>[
      first,
      second,
    ]);
    expect(responses, hasLength(2));
    expect(
      responses,
      everyElement(
        predicate<ApiResponse>((ApiResponse value) {
          if (!value.isSuccess || value.data is! Map) {
            return false;
          }
          return (value.data! as Map)['accepted'] == true;
        }),
      ),
    );
    expect(requests, 4);
    expect(recoveryCalls, 1);
  });

  test(
    'late 401 from a request sent with the old token replays without recovery',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final Completer<void> recoveryStarted = Completer<void>();
      final Completer<void> releaseRecovery = Completer<void>();
      final Completer<void> recoveryFinished = Completer<void>();
      final Completer<void> secondRequestSent = Completer<void>();
      final Completer<void> firstReplayObserved = Completer<void>();
      final Completer<void> releaseLateUnauthorized = Completer<void>();
      final List<String?> requestIds = <String?>[];
      final List<String?> authorizations = <String?>[];
      var requests = 0;
      server.listen((HttpRequest request) async {
        requests += 1;
        requestIds.add(request.headers.value('X-Request-Id'));
        authorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        request.response.headers.contentType = ContentType.json;
        if (requests == 1) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..write(
              jsonEncode(<String, Object?>{
                'code': 401,
                'message': '登录已过期',
                'data': null,
              }),
            );
        } else if (requests == 2) {
          if (!secondRequestSent.isCompleted) {
            secondRequestSent.complete();
          }
          await releaseLateUnauthorized.future;
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..write(
              jsonEncode(<String, Object?>{
                'code': 401,
                'message': '登录已过期',
                'data': null,
              }),
            );
        } else {
          request.response.write(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'OK',
              'data': <String, Object?>{'accepted': true},
            }),
          );
          if (requests == 3 && !firstReplayObserved.isCompleted) {
            firstReplayObserved.complete();
          }
        }
        await request.response.close();
      });

      var accessToken = 'old-token';
      var recoveryCalls = 0;
      final ApiClient client = ApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '42',
        authorizationProvider: () => 'Bearer $accessToken',
      );
      client.setUnauthorizedRecovery(() async {
        recoveryCalls += 1;
        if (!recoveryStarted.isCompleted) {
          recoveryStarted.complete();
        }
        await releaseRecovery.future;
        accessToken = 'new-token';
        if (!recoveryFinished.isCompleted) {
          recoveryFinished.complete();
        }
        return true;
      });

      final Future<ApiResponse> first = client.post(
        '/contract',
        headers: <String, String>{'X-Request-Id': 'late-request-a'},
      );
      await recoveryStarted.future;
      final Future<ApiResponse> second = client.post(
        '/contract',
        headers: <String, String>{'X-Request-Id': 'late-request-b'},
      );
      await secondRequestSent.future;
      releaseRecovery.complete();
      await recoveryFinished.future;
      await firstReplayObserved.future;
      releaseLateUnauthorized.complete();

      final List<ApiResponse> responses = await Future.wait(
        <Future<ApiResponse>>[first, second],
      );
      expect(responses, hasLength(2));
      expect(
        responses,
        everyElement(
          predicate<ApiResponse>((ApiResponse value) {
            if (!value.isSuccess || value.data is! Map) {
              return false;
            }
            return (value.data! as Map)['accepted'] == true;
          }),
        ),
      );
      expect(recoveryCalls, 1);
      expect(requests, 4);
      expect(requestIds, <String?>[
        'late-request-a',
        'late-request-b',
        'late-request-a',
        'late-request-b',
      ]);
      expect(authorizations, <String?>[
        'Bearer old-token',
        'Bearer old-token',
        'Bearer new-token',
        'Bearer new-token',
      ]);
    },
  );

  test('network failure does not invoke unauthorized recovery', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final int port = server.port;
    await server.close(force: true);

    var recoveryCalls = 0;
    final ApiClient client = ApiClient(
      baseUri: Uri.parse(
        'http://${InternetAddress.loopbackIPv4.address}:$port/',
      ),
      clientType: 'Android',
      clientInnerVersion: '42',
      authorizationProvider: () => 'Bearer test',
    );
    client.setUnauthorizedRecovery(() async {
      recoveryCalls += 1;
      return true;
    });

    ApiException? failure;
    try {
      await client.get('/contract');
    } on ApiException catch (error) {
      failure = error;
    }

    expect(failure?.kind, ApiFailureKind.network);
    expect(recoveryCalls, 0);
  });

  test('timeout does not invoke unauthorized recovery', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    var recoveryCalls = 0;
    final ApiClient client = ApiClient(
      baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
      clientType: 'Android',
      clientInnerVersion: '42',
      authorizationProvider: () => 'Bearer test',
      timeout: const Duration(milliseconds: 20),
    );
    client.setUnauthorizedRecovery(() async {
      recoveryCalls += 1;
      return true;
    });

    ApiException? failure;
    try {
      await client.get('/contract');
    } on ApiException catch (error) {
      failure = error;
    }

    expect(failure?.kind, ApiFailureKind.timeout);
    expect(recoveryCalls, 0);
  });
}
