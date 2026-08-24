import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/backend_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_operations_models.dart';

void main() {
  test(
    'applicant status and cancel preserve the first-party contract',
    () async {
      final _ContractServer server = await _ContractServer.start((request) {
        switch (request.uri.path) {
          case '/app-mini-api/mini/v1/rooms/join-requests/status':
            expect(request.method, 'GET');
            expect(request.uri.queryParameters, <String, String>{
              'roomId': 'room-9527',
              'joinRequestId': 'join-request-1',
            });
            return const _Response(
              data: <String, Object?>{
                'roomId': 'room-9527',
                'joinRequestId': 'join-request-1',
                'status': 'PENDING',
                'roomState': 'OPEN',
                'banned': false,
                'canCancel': true,
                'message': '想和大家一起聊天',
                'createdAt': '2026-08-25T08:00:00Z',
                'resolvedAt': null,
              },
            );
          case '/app-mini-api/mini/v1/rooms/join-requests/cancel':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'roomId': 'room-9527',
              'joinRequestId': 'join-request-1',
            });
            expect(request.body!.containsKey('requestId'), isFalse);
            expect(request.headers.value('X-Request-Id'), 'cancel-001');
            return const _Response(
              data: <String, Object?>{
                'roomId': 'room-9527',
                'joinRequestId': 'join-request-1',
                'status': 'CANCELLED',
                'cancelled': true,
                'alreadyCancelled': false,
                'providerInvocation': false,
              },
            );
          default:
            fail('unexpected applicant route: ${request.uri.path}');
        }
      });
      addTearDown(server.close);

      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);
      final RoomJoinRequestApplicantStatus status = await repository
          .fetchJoinRequestStatus(
            roomId: 'room-9527',
            joinRequestId: 'join-request-1',
          );
      expect(status.roomId, 'room-9527');
      expect(status.joinRequestId, 'join-request-1');
      expect(status.status, RoomJoinRequestStatus.pending);
      expect(status.roomState, 'OPEN');
      expect(status.banned, isFalse);
      expect(status.canCancel, isTrue);
      expect(status.message, '想和大家一起聊天');

      final RoomJoinRequestCancellation cancellation = await repository
          .cancelJoinRequest(
            roomId: 'room-9527',
            joinRequestId: 'join-request-1',
            requestId: 'cancel-001',
          );
      expect(cancellation.roomId, 'room-9527');
      expect(cancellation.joinRequestId, 'join-request-1');
      expect(cancellation.status, RoomJoinRequestStatus.cancelled);
      expect(cancellation.cancelled, isTrue);
      expect(cancellation.alreadyCancelled, isFalse);
    },
  );

  test(
    'applicant status rejects a mismatched response instead of masking it',
    () async {
      final _ContractServer server = await _ContractServer.start((request) {
        return const _Response(
          data: <String, Object?>{
            'roomId': 'another-room',
            'joinRequestId': 'join-request-1',
            'status': 'PENDING',
            'roomState': 'OPEN',
            'banned': false,
            'canCancel': true,
          },
        );
      });
      addTearDown(server.close);

      final BackendRoomOperationsRepository repository =
          BackendRoomOperationsRepository(apiClient: server.client);
      await expectLater(
        repository.fetchJoinRequestStatus(
          roomId: 'room-9527',
          joinRequestId: 'join-request-1',
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    },
  );

  test('applicant status rejects malformed authority booleans', () async {
    final _ContractServer server = await _ContractServer.start((request) {
      return const _Response(
        data: <String, Object?>{
          'roomId': 'room-9527',
          'joinRequestId': 'join-request-1',
          'status': 'PENDING',
          'roomState': 'OPEN',
          'banned': 0,
          'canCancel': true,
        },
      );
    });
    addTearDown(server.close);

    final BackendRoomOperationsRepository repository =
        BackendRoomOperationsRepository(apiClient: server.client);
    await expectLater(
      repository.fetchJoinRequestStatus(roomId: 'room-9527'),
      throwsA(isA<ApiException>()),
    );
  });
}

class _ContractServer {
  _ContractServer._(this.server, this.handler)
    : client = ApiClient(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        clientType: 'contract-test',
        clientInnerVersion: 'contract-test',
        authorizationProvider: () => 'Bearer contract-test',
      );

  final HttpServer server;
  final FutureOr<_Response> Function(_CapturedRequest request) handler;
  final ApiClient client;

  static Future<_ContractServer> start(
    FutureOr<_Response> Function(_CapturedRequest request) handler,
  ) async {
    final HttpServer server = await HttpServer.bind('127.0.0.1', 0);
    final _ContractServer value = _ContractServer._(server, handler);
    server.listen(value._serve);
    return value;
  }

  Future<void> _serve(HttpRequest request) async {
    final String raw = await utf8.decoder.bind(request).join();
    final Object? decoded = raw.trim().isEmpty ? null : jsonDecode(raw);
    final _CapturedRequest captured = _CapturedRequest(
      method: request.method,
      uri: request.uri,
      body: decoded is Map
          ? <String, Object?>{
              for (final MapEntry<Object?, Object?> entry in decoded.entries)
                entry.key.toString(): entry.value,
            }
          : null,
      headers: request.headers,
    );
    final _Response response = await handler(captured);
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode(<String, Object?>{
          'code': 200,
          'message': 'OK',
          'data': response.data,
        }),
      );
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.uri,
    required this.body,
    required this.headers,
  });

  final String method;
  final Uri uri;
  final Map<String, Object?>? body;
  final HttpHeaders headers;
}

class _Response {
  const _Response({required this.data});

  final Map<String, Object?> data;
}
