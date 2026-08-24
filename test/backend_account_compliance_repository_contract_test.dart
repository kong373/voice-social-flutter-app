import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'contract_test_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';

const String currentSessionId = '11111111-1111-4111-8111-111111111111';
const String oldSessionId = '22222222-2222-4222-8222-222222222222';
const String penaltyId = '33333333-3333-4333-8333-333333333333';
const String appealId = '44444444-4444-4444-8444-444444444444';
const String submittedAppealId = '55555555-5555-4555-8555-555555555555';

void main() {
  test(
    'snapshot uses first-party routes and parses authoritative fields',
    () async {
      final List<RequestRecord> requests = <RequestRecord>[];
      String realNameStatus = 'VERIFIED';
      int realNameStatusCode = 2;
      final HttpServer server = await startServer((
        RequestRecord request,
      ) async {
        requests.add(request);
        switch (request.path) {
          case '/app-api/user/getPersonalData':
            return reply(
              request,
              data: <String, Object?>{
                'loginName': 'user-public-1',
                'nickName': '晚星',
                'forbiddenState': 2,
                'forbiddenReason': '设备风控复核中',
              },
            );
          case '/app-api/user/other/getMatchButtonAndYouthMode':
            return reply(
              request,
              data: <String, Object?>{
                'isYouthMode': 1,
                'youthModeEnabled': true,
              },
            );
          case '/app-mini-api/mini/v1/account/restrictions':
            return reply(
              request,
              data: <String, Object?>{
                'restricted': true,
                'accountUsable': true,
                'total': 1,
                'list': <Object?>[
                  <String, Object?>{
                    'penaltyId': penaltyId,
                    'type': 'DEVICE_BAN',
                    'status': 'ACTIVE',
                    'reason': '设备风控复核中',
                    'endsAt': '2026-08-30T08:00:00Z',
                  },
                ],
              },
            );
          case '/app-api/user/queryUserLogout':
            return reply(
              request,
              data: <String, Object?>{
                'canLogout': true,
                'eligible': true,
                'status': 'NONE',
                'latestRequest': <String, Object?>{},
                'requiresConfirmation': true,
                'immediateDeletion': false,
              },
            );
          case '/app-api/appBase/getVersionInformation':
            expect(request.method, 'GET');
            expect(request.query, <String, String>{
              'type': '1',
              'versionCode': '6',
            });
            return reply(
              request,
              data: <String, Object?>{
                'isUpdate': 1,
                'latest': <String, Object?>{
                  'isForce': 1,
                  'versionName': '6.1.0',
                  'versionInfo': '修复问题',
                  'packageUrl': 'https://example.test/app.apk',
                },
                'providerInvocation': false,
              },
            );
          case '/app-mini-api/mini/v1/account/real-name':
            expect(request.method, 'GET');
            return reply(
              request,
              data: <String, Object?>{
                'status': realNameStatus,
                'statusCode': realNameStatusCode,
                'providerStatus': 'VENDOR_BLOCKED',
                'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
              },
            );
          case '/app-mini-api/mini/v1/account/sessions':
            expect(request.method, 'GET');
            return reply(
              request,
              data: <String, Object?>{
                'total': 2,
                'list': <Object?>[
                  <String, Object?>{
                    'sessionId': currentSessionId,
                    'deviceId': 'pixel-9',
                    'active': true,
                    'lastUsedAt': '2026-08-22T08:00:00Z',
                  },
                  <String, Object?>{
                    'sessionId': oldSessionId,
                    'deviceId': 'iphone',
                    'active': true,
                    'lastUsedAt': '2026-08-20T08:00:00Z',
                  },
                ],
              },
            );
          default:
            return reply(request, status: 404, code: 404, message: 'not found');
        }
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(
            apiClient: client(server),
            currentDeviceIdProvider: () => 'pixel-9',
          );
      final AccountComplianceSnapshot snapshot = await repository.fetchSnapshot(
        account: 'fallback-account',
        currentVersion: 6,
        platformType: 1,
      );

      expect(repository.supportsDeviceSessionManagement, isTrue);
      expect(repository.supportsRealNameSubmission, isTrue);
      expect(snapshot.account, 'user-public-1');
      expect(snapshot.nickname, '晚星');
      expect(snapshot.verificationState, VerificationState.verified);
      expect(snapshot.youthModeEnabled, isTrue);
      expect(snapshot.restriction.kind, RestrictionKind.device);
      expect(snapshot.restriction.reason, '设备风控复核中');
      expect(snapshot.cancellation.allowed, isTrue);
      expect(snapshot.cancellation.requiresSmsCode, isFalse);
      expect(snapshot.versionInfo.hasUpdate, isTrue);
      expect(snapshot.versionInfo.forceUpdate, isTrue);
      expect(snapshot.versionInfo.versionName, '6.1.0');
      expect(snapshot.versionInfo.releaseNotes, '修复问题');
      expect(snapshot.sessions, hasLength(2));
      expect(snapshot.sessions.first.isCurrent, isTrue);
      expect(snapshot.sessions.first.canRevoke, isFalse);
      expect(snapshot.sessions.last.isCurrent, isFalse);
      expect(snapshot.sessions.last.canRevoke, isTrue);

      realNameStatus = 'NOT_SUBMITTED';
      realNameStatusCode = 0;
      final AccountComplianceSnapshot notSubmitted = await repository
          .fetchSnapshot(
            account: 'fallback-account',
            currentVersion: 6,
            platformType: 1,
          );
      expect(notSubmitted.verificationState, VerificationState.unverified);
      expect(
        requests.map((RequestRecord request) => request.path),
        containsAllInOrder(<String>[
          '/app-api/user/getPersonalData',
          '/app-api/user/other/getMatchButtonAndYouthMode',
          '/app-mini-api/mini/v1/account/restrictions',
          '/app-api/user/queryUserLogout',
          '/app-api/appBase/getVersionInformation',
          '/app-mini-api/mini/v1/account/real-name',
          '/app-mini-api/mini/v1/account/sessions',
        ]),
      );
    },
  );

  test(
    'malformed device sessions fail closed without local ids or timestamps',
    () async {
      final HttpServer server = await startServer((
        RequestRecord request,
      ) async {
        switch (request.path) {
          case '/app-api/user/getPersonalData':
            return reply(
              request,
              data: <String, Object?>{'loginName': 'user-1', 'nickName': '用户'},
            );
          case '/app-api/user/other/getMatchButtonAndYouthMode':
            return reply(
              request,
              data: <String, Object?>{
                'isYouthMode': 0,
                'youthModeEnabled': false,
              },
            );
          case '/app-mini-api/mini/v1/account/restrictions':
            return reply(
              request,
              data: <String, Object?>{
                'restricted': false,
                'accountUsable': true,
                'total': 0,
                'list': <Object?>[],
              },
            );
          case '/app-api/user/queryUserLogout':
            return reply(
              request,
              data: <String, Object?>{
                'canLogout': true,
                'eligible': true,
                'status': 'NONE',
                'latestRequest': <String, Object?>{},
                'requiresConfirmation': true,
                'immediateDeletion': false,
              },
            );
          case '/app-api/appBase/getVersionInformation':
            return reply(
              request,
              data: <String, Object?>{
                'isUpdate': 0,
                'latest': <String, Object?>{},
                'providerInvocation': false,
              },
            );
          case '/app-mini-api/mini/v1/account/real-name':
            return reply(
              request,
              data: <String, Object?>{
                'status': 'UNVERIFIED',
                'statusCode': 0,
                'providerStatus': 'VENDOR_BLOCKED',
                'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
              },
            );
          case '/app-mini-api/mini/v1/account/sessions':
            return reply(
              request,
              data: <String, Object?>{
                'total': 1,
                'list': <Object?>[
                  <String, Object?>{
                    'sessionId': currentSessionId,
                    'deviceId': 'pixel-9',
                    'active': true,
                    // No service timestamp: the client must not invent one.
                  },
                ],
              },
            );
          default:
            return reply(request, status: 404, code: 404, message: 'not found');
        }
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(
            apiClient: client(server),
            currentDeviceIdProvider: () => 'pixel-9',
          );

      await expectLater(
        repository.fetchSnapshot(
          account: 'fallback-account',
          currentVersion: 6,
          platformType: 1,
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

  test('device sessions require an explicit boolean active field', () async {
    bool includeActive = false;
    Object? activeValue;
    final HttpServer server = await startServer((RequestRecord request) async {
      switch (request.path) {
        case '/app-api/user/getPersonalData':
          return reply(
            request,
            data: <String, Object?>{'loginName': 'user-1', 'nickName': '用户'},
          );
        case '/app-api/user/other/getMatchButtonAndYouthMode':
          return reply(
            request,
            data: <String, Object?>{
              'isYouthMode': 0,
              'youthModeEnabled': false,
            },
          );
        case '/app-mini-api/mini/v1/account/restrictions':
          return reply(
            request,
            data: <String, Object?>{
              'restricted': false,
              'accountUsable': true,
              'total': 0,
              'list': <Object?>[],
            },
          );
        case '/app-api/user/queryUserLogout':
          return reply(
            request,
            data: <String, Object?>{
              'canLogout': true,
              'eligible': true,
              'status': 'NONE',
              'latestRequest': <String, Object?>{},
              'requiresConfirmation': true,
              'immediateDeletion': false,
            },
          );
        case '/app-api/appBase/getVersionInformation':
          return reply(
            request,
            data: <String, Object?>{
              'isUpdate': 0,
              'latest': <String, Object?>{},
              'providerInvocation': false,
            },
          );
        case '/app-mini-api/mini/v1/account/real-name':
          return reply(
            request,
            data: <String, Object?>{
              'status': 'UNVERIFIED',
              'statusCode': 0,
              'providerStatus': 'VENDOR_BLOCKED',
              'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
            },
          );
        case '/app-mini-api/mini/v1/account/sessions':
          final Map<String, Object?> session = <String, Object?>{
            'sessionId': currentSessionId,
            'deviceId': 'pixel-9',
            'lastUsedAt': '2026-08-22T08:00:00Z',
          };
          if (includeActive) {
            session['active'] = activeValue;
          }
          return reply(
            request,
            data: <String, Object?>{
              'total': 1,
              'list': <Object?>[session],
            },
          );
        default:
          return reply(request, status: 404, code: 404, message: 'not found');
      }
    });
    addTearDown(() => server.close(force: true));

    BackendAccountComplianceRepository repository() =>
        BackendAccountComplianceRepository(
          apiClient: client(server),
          currentDeviceIdProvider: () => 'pixel-9',
        );

    Future<void> expectProtocol() async {
      await expectLater(
        repository().fetchSnapshot(
          account: 'fallback-account',
          currentVersion: 6,
          platformType: 1,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.protocol,
          ),
        ),
      );
    }

    await expectProtocol();
    includeActive = true;
    activeValue = 'true';
    await expectProtocol();
  });

  test(
    'authoritative account status metadata fails closed when malformed',
    () async {
      String malformedPath = '';
      Object? malformedData;
      Map<String, Object?> validData(String path) => switch (path) {
        '/app-api/user/getPersonalData' => <String, Object?>{
          'loginName': 'user-1',
          'nickName': '用户',
        },
        '/app-api/user/other/getMatchButtonAndYouthMode' => <String, Object?>{
          'isYouthMode': 0,
          'youthModeEnabled': false,
        },
        '/app-mini-api/mini/v1/account/restrictions' => <String, Object?>{
          'restricted': false,
          'accountUsable': true,
          'total': 0,
          'list': <Object?>[],
        },
        '/app-api/user/queryUserLogout' => <String, Object?>{
          'canLogout': true,
          'eligible': true,
          'status': 'NONE',
          'latestRequest': <String, Object?>{},
          'requiresConfirmation': true,
          'immediateDeletion': false,
        },
        '/app-api/appBase/getVersionInformation' => <String, Object?>{
          'isUpdate': 0,
          'latest': <String, Object?>{},
          'providerInvocation': false,
        },
        '/app-mini-api/mini/v1/account/real-name' => <String, Object?>{
          'status': 'UNVERIFIED',
          'statusCode': 0,
          'providerStatus': 'VENDOR_BLOCKED',
          'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
        },
        '/app-mini-api/mini/v1/account/sessions' => <String, Object?>{
          'total': 0,
          'list': <Object?>[],
        },
        _ => throw StateError('unexpected path $path'),
      };
      final HttpServer server = await startServer((
        RequestRecord request,
      ) async {
        return reply(
          request,
          data: request.path == malformedPath
              ? malformedData
              : validData(request.path),
        );
      });
      addTearDown(() => server.close(force: true));
      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: client(server));

      final List<(String, Object?)> cases = <(String, Object?)>[
        (
          '/app-api/user/getPersonalData',
          <String, Object?>{'loginName': 'user-1'},
        ),
        (
          '/app-api/user/other/getMatchButtonAndYouthMode',
          <String, Object?>{'isYouthMode': 0},
        ),
        (
          '/app-mini-api/mini/v1/account/restrictions',
          <String, Object?>{
            'restricted': false,
            'accountUsable': true,
            'list': <Object?>[],
          },
        ),
        (
          '/app-api/user/queryUserLogout',
          <String, Object?>{
            'canLogout': true,
            'eligible': 1,
            'status': 'NONE',
            'latestRequest': <String, Object?>{},
            'requiresConfirmation': true,
            'immediateDeletion': false,
          },
        ),
        (
          '/app-api/appBase/getVersionInformation',
          <String, Object?>{'isUpdate': 0, 'latest': <String, Object?>{}},
        ),
        (
          '/app-mini-api/mini/v1/account/real-name',
          <String, Object?>{
            'status': 'VERIFIED',
            'statusCode': 1,
            'providerStatus': 'VENDOR_BLOCKED',
            'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
          },
        ),
        (
          '/app-mini-api/mini/v1/account/sessions',
          <String, Object?>{'total': 1, 'list': <Object?>[]},
        ),
      ];

      for (final (String path, Object? data) in cases) {
        malformedPath = path;
        malformedData = data;
        await expectLater(
          repository.fetchSnapshot(
            account: 'fallback-account',
            currentVersion: 6,
            platformType: 1,
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.kind,
              'kind',
              ApiFailureKind.protocol,
            ),
          ),
          reason: path,
        );
      }
    },
  );

  test(
    'real-name, session, deletion and youth mutations use exact contracts',
    () async {
      final List<RequestRecord> requests = <RequestRecord>[];
      final HttpServer server = await startServer((
        RequestRecord request,
      ) async {
        requests.add(request);
        switch (request.path) {
          case '/app-mini-api/mini/v1/account/real-name':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{
              'legalName': '张三',
              'identityNumber': '42010619960820123X',
            });
            return reply(
              request,
              data: <String, Object?>{
                'status': 'PENDING',
                'statusCode': 1,
                'providerStatus': 'VENDOR_BLOCKED',
                'reviewMode': 'FIRST_PARTY_MANUAL_REVIEW',
              },
            );
          case '/app-mini-api/mini/v1/account/sessions/$oldSessionId':
            expect(request.method, 'DELETE');
            expect(request.body, isNull);
            return reply(
              request,
              data: <String, Object?>{
                'sessionId': oldSessionId,
                'status': 'REVOKED',
                'revoked': true,
              },
            );
          case '/app-register-api/userAccount/v1/delete':
            expect(request.method, 'DELETE');
            expect(request.body, <String, Object?>{
              'confirmation': 'CONFIRM_DELETE',
            });
            expect(request.query, isEmpty);
            return reply(
              request,
              data: <String, Object?>{
                'eligible': false,
                'status': 'COOLING_OFF',
                'canLogout': false,
                'requiresConfirmation': true,
                'immediateDeletion': false,
                'latestRequest': <String, Object?>{
                  'status': 'COOLING_OFF',
                  'coolingEndsAt': '2026-08-29T08:00:00Z',
                },
              },
            );
          case '/app-api/user/openYouthMode':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{'password': '2468'});
            return reply(
              request,
              data: <String, Object?>{
                'isYouthMode': 1,
                'youthModeEnabled': true,
              },
            );
          case '/app-api/user/turnOffYouthMode':
            expect(request.method, 'POST');
            expect(request.body, <String, Object?>{'password': '2468'});
            return reply(
              request,
              data: <String, Object?>{
                'isYouthMode': 0,
                'youthModeEnabled': false,
              },
            );
          default:
            return reply(request, status: 404, code: 404, message: 'not found');
        }
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: client(server));
      await repository.submitRealName(
        realName: '张三',
        idNumber: '42010619960820123X',
      );
      await repository.revokeDeviceSession(oldSessionId);
      await repository.requestCancellation(smsCode: 'must-not-be-sent');
      expect(await repository.setYouthMode(enabled: true, pin: '2468'), isTrue);
      expect(
        await repository.setYouthMode(enabled: false, pin: '2468'),
        isFalse,
      );
      expect(requests, hasLength(5));
    },
  );

  test(
    'cancellation cooling-off state is cancellable and cancel returns server state',
    () async {
      final List<RequestRecord> requests = <RequestRecord>[];
      int eligibilityReads = 0;
      final HttpServer server = await startServer((
        RequestRecord request,
      ) async {
        requests.add(request);
        switch (request.path) {
          case '/app-api/user/queryUserLogout':
            expect(request.method, 'GET');
            eligibilityReads++;
            if (eligibilityReads == 1) {
              return reply(
                request,
                data: <String, Object?>{
                  'canLogout': false,
                  'eligible': false,
                  'status': 'COOLING_OFF',
                  'coolingDays': 7,
                  'requiresConfirmation': true,
                  'immediateDeletion': false,
                  'latestRequest': <String, Object?>{
                    'status': 'COOLING_OFF',
                    'coolingEndsAt': '2026-08-29T08:00:00Z',
                  },
                },
              );
            }
            return reply(
              request,
              data: <String, Object?>{
                'canLogout': true,
                'eligible': true,
                'status': 'NONE',
                'requiresConfirmation': true,
                'immediateDeletion': false,
                'latestRequest': <String, Object?>{
                  'status': 'CANCELLED',
                  'cancelledAt': '2026-08-22T08:00:00Z',
                },
              },
            );
          case '/app-mini-api/mini/v1/account/deletion/cancel':
            expect(request.method, 'POST');
            expect(request.body, isNull);
            expect(request.query, isEmpty);
            return reply(
              request,
              data: <String, Object?>{
                'canLogout': true,
                'eligible': true,
                'status': 'NONE',
                'requiresConfirmation': true,
                'immediateDeletion': false,
                'latestRequest': <String, Object?>{
                  'status': 'CANCELLED',
                  'cancelledAt': '2026-08-22T08:00:00Z',
                },
              },
            );
          default:
            return reply(request, status: 404, code: 404, message: 'not found');
        }
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: client(server));
      final CancellationEligibility cooling = await repository
          .queryCancellationEligibility();
      expect(cooling.status, 'COOLING_OFF');
      expect(cooling.canCancel, isTrue);
      expect(cooling.allowed, isFalse);
      expect(cooling.coolingEndsAt, '2026-08-29T08:00:00Z');

      final CancellationEligibility cancelled = await repository
          .cancelDeletion();
      expect(cancelled.status, 'NONE');
      expect(cancelled.canCancel, isFalse);
      expect(cancelled.allowed, isTrue);

      expect(requests.map((RequestRecord request) => request.path), <String>[
        '/app-api/user/queryUserLogout',
        '/app-mini-api/mini/v1/account/deletion/cancel',
      ]);
    },
  );

  test('cancellation errors preserve recoverable HTTP statuses', () async {
    for (final int status in <int>[403, 409, 422, 500]) {
      final HttpServer server = await startServer((
        RequestRecord request,
      ) async {
        expect(request.method, 'POST');
        expect(request.path, '/app-mini-api/mini/v1/account/deletion/cancel');
        await reply(request, status: status, code: status, message: 'failure');
      });
      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: client(server));

      await expectLater(
        repository.cancelDeletion(),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.httpStatus,
            'httpStatus',
            status,
          ),
        ),
      );
      await server.close(force: true);
    }
  });

  test('appeal envelope and progress are keyed by appealId', () async {
    final List<RequestRecord> requests = <RequestRecord>[];
    int appealInfoRequestCount = 0;
    final HttpServer server = await startServer((RequestRecord request) async {
      requests.add(request);
      switch (request.path) {
        case '/app-api/accappeal/queryAppealInfo':
          expect(request.method, 'GET');
          appealInfoRequestCount++;
          return reply(
            request,
            data: <String, Object?>{
              'penalty': <String, Object?>{
                'penaltyId': penaltyId,
                'type': 'ACCOUNT_BAN',
                'reason': '测试处罚',
              },
              'appeal': <String, Object?>{
                'appealId': appealInfoRequestCount >= 3
                    ? submittedAppealId
                    : appealId,
                'penaltyId': penaltyId,
                'reason': '处罚信息需要复核',
                'status': 'SUBMITTED',
              },
            },
          );
        case '/app-api/accappeal/commitAppeal':
          expect(request.method, 'POST');
          expect(request.body, <String, Object?>{
            'penaltyId': penaltyId,
            'reason': '处罚信息需要复核',
            'evidence': <String, Object?>{
              'explanation': '本人正常使用，请复核。',
              'reasonType': '1',
              'account': 'user-1',
              'nickname': '晚星',
            },
          });
          return reply(
            request,
            data: <String, Object?>{
              'appealId': submittedAppealId,
              'penaltyId': penaltyId,
              'reason': '处罚信息需要复核',
              'status': 'SUBMITTED',
            },
          );
        case '/app-api/accappeal/queryAppealProcess':
          expect(request.method, 'GET');
          expect(request.query, <String, String>{
            'appealId': submittedAppealId,
          });
          return reply(
            request,
            data: <String, Object?>{
              'appealId': submittedAppealId,
              'penaltyId': penaltyId,
              'reason': '处罚信息需要复核',
              'status': 'REVIEWING',
              'resultMessage': '',
            },
          );
        default:
          return reply(request, status: 404, code: 404, message: 'not found');
      }
    });
    addTearDown(() => server.close(force: true));

    final BackendAccountComplianceRepository repository =
        BackendAccountComplianceRepository(apiClient: client(server));
    final AppealCase current = await repository.queryAppeal(
      account: 'user-1',
      reasonType: '1',
    );
    expect(current.state, AppealState.pending);
    expect(current.reason, '处罚信息需要复核');
    final AppealCase submitted = await repository.submitAppeal(
      account: 'user-1',
      nickname: '晚星',
      reason: '处罚信息需要复核',
      reasonType: '1',
      explanation: '本人正常使用，请复核。',
    );
    expect(submitted.state, AppealState.pending);
    final AppealCase progress = await repository.queryAppealProgress('user-1');
    expect(progress.state, AppealState.pending);
    expect(progress.account, 'user-1');
    expect(requests.map((RequestRecord request) => request.path), <String>[
      '/app-api/accappeal/queryAppealInfo',
      '/app-api/accappeal/queryAppealInfo',
      '/app-api/accappeal/commitAppeal',
      '/app-api/accappeal/queryAppealInfo',
      '/app-api/accappeal/queryAppealProcess',
    ]);
  });

  test(
    'appeal progress returns an explicit empty state when no appeal exists',
    () async {
      final List<RequestRecord> requests = <RequestRecord>[];
      final HttpServer server = await startServer((
        RequestRecord request,
      ) async {
        requests.add(request);
        expect(request.path, '/app-api/accappeal/queryAppealInfo');
        return reply(
          request,
          data: <String, Object?>{
            'penalty': <String, Object?>{
              'penaltyId': penaltyId,
              'type': 'ACCOUNT_BAN',
              'reason': '测试处罚',
            },
            'appeal': <String, Object?>{},
          },
        );
      });
      addTearDown(() => server.close(force: true));

      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: client(server));
      final AppealCase progress = await repository.queryAppealProgress(
        'user-1',
      );

      expect(progress.account, 'user-1');
      expect(progress.state, AppealState.none);
      expect(progress.reason, '测试处罚');
      expect(progress.processText, '尚未提交申诉');
      expect(requests, hasLength(1));
    },
  );

  test(
    'HTTP failures are surfaced instead of becoming empty success states',
    () async {
      for (final int status in <int>[400, 403, 409, 422, 500]) {
        final HttpServer server = await startServer((
          RequestRecord request,
        ) async {
          await reply(
            request,
            status: status,
            code: status,
            message: 'failure',
          );
        });
        final BackendAccountComplianceRepository repository =
            BackendAccountComplianceRepository(apiClient: client(server));
        await expectLater(
          repository.checkVersion(currentVersion: 6, platformType: 1),
          throwsA(
            isA<ApiException>().having(
              (ApiException error) => error.httpStatus,
              'httpStatus',
              status,
            ),
          ),
        );
        await server.close(force: true);
      }
    },
  );

  test(
    'a slow first response does not overwrite the later call at repository boundary',
    () async {
      final List<RequestRecord> requests = <RequestRecord>[];
      final Completer<void> releaseFirst = Completer<void>();
      final HttpServer server = await startServer((
        RequestRecord request,
      ) async {
        requests.add(request);
        if (requests.length == 1) {
          await releaseFirst.future;
        }
        return reply(
          request,
          data: <String, Object?>{
            'isUpdate': 0,
            'latest': <String, Object?>{},
            'providerInvocation': false,
          },
        );
      });
      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(apiClient: client(server));
      final Future<VersionUpdateInfo> first = repository.checkVersion(
        currentVersion: 1,
        platformType: 1,
      );
      final Future<VersionUpdateInfo> second = repository.checkVersion(
        currentVersion: 2,
        platformType: 1,
      );
      final VersionUpdateInfo secondResult = await second;
      releaseFirst.complete();
      final VersionUpdateInfo firstResult = await first;
      expect(firstResult.hasUpdate, isFalse);
      expect(secondResult.hasUpdate, isFalse);
      expect(requests, hasLength(2));
      await server.close(force: true);
    },
  );
}

class RequestRecord {
  RequestRecord(HttpRequest request, this.body)
    : httpRequest = request,
      method = request.method,
      path = request.uri.path,
      query = Map<String, String>.from(request.uri.queryParameters),
      authorization = captureContractAuthorization(request);

  final HttpRequest httpRequest;
  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;
  final String authorization;
}

Future<HttpServer> startServer(
  Future<void> Function(RequestRecord request) handler,
) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    final String raw = await utf8.decoder.bind(request).join();
    final Object? body = raw.trim().isEmpty ? null : jsonDecode(raw);
    await handler(RequestRecord(request, body));
  });
  return server;
}

Future<void> reply(
  RequestRecord request, {
  int status = 200,
  int code = 200,
  String message = 'OK',
  Object? data,
}) async {
  await writeReply(
    request.httpRequest,
    status: status,
    code: code,
    message: message,
    data: data,
  );
}

Future<void> writeReply(
  HttpRequest request, {
  int status = 200,
  int code = 200,
  String message = 'OK',
  Object? data,
}) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(
      jsonEncode(<String, Object?>{
        'code': code,
        'message': message,
        'data': data,
      }),
    );
  await request.response.close();
}

ApiClient client(HttpServer server) => ApiClient(
  baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
  clientType: 'Android',
  clientInnerVersion: '6',
  authorizationProvider: () => 'Bearer contract-test',
);
