import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'backend_account_compliance_repository_contract_test.dart' as fixture;

void main() {
  for (final id in <Object?>[null, '', '   ', 42, <String>[]]) {
    test(
      'invalid penalty id $id grants no eligibility and prevents POST',
      () async {
        int posts = 0;
        final server = await fixture.startServer((request) async {
          if (request.method == 'POST') posts++;
          await fixture.reply(
            request,
            data: {
              'penalty': {'penaltyId': id},
              'appeal': <String, Object?>{},
            },
          );
        });
        addTearDown(() => server.close(force: true));
        final repo = BackendAccountComplianceRepository(
          apiClient: fixture.client(server),
        );
        expect(
          (await repo.queryAppeal(account: 'user7', reasonType: '1')).canSubmit,
          isFalse,
        );
        await expectLater(
          repo.submitAppeal(
            account: 'user7',
            nickname: '',
            reason: '',
            reasonType: '1',
            explanation: '请平台核对这次处罚的相关证据',
          ),
          throwsA(isA<ApiException>()),
        );
        expect(posts, 0);
      },
    );
  }

  for (final status in ['SUBMITTED', 'APPROVED', 'REJECTED', 'CANCELLED']) {
    for (final relation in ['same', 'different', 'missing', 'no-penalty']) {
      test(
        '$status appeal with $relation penalty retains authoritative record',
        () async {
          final server = await fixture.startServer((request) async {
            await fixture.reply(
              request,
              data: {
                'penalty': relation == 'no-penalty'
                    ? <String, Object?>{}
                    : {'penaltyId': fixture.penaltyId, 'reason': '当前处罚'},
                'appeal': {
                  'appealId': fixture.appealId,
                  'status': status,
                  'reason': '历史原因',
                  'resultMessage': '平台结果',
                  if (relation != 'missing')
                    'penaltyId': relation == 'different'
                        ? 'old-penalty'
                        : fixture.penaltyId,
                },
              },
            );
          });
          addTearDown(() => server.close(force: true));
          final repo = BackendAccountComplianceRepository(
            apiClient: fixture.client(server),
          );
          final value = await repo.queryAppeal(
            account: 'user7',
            reasonType: '1',
          );
          expect(value.canSubmit, relation == 'different');
          final record = value.previousAppeal ?? value;
          expect(record.appealId, fixture.appealId);
          expect(record.state, switch (status) {
            'SUBMITTED' => AppealState.pending,
            'APPROVED' => AppealState.approved,
            'REJECTED' => AppealState.rejected,
            _ => AppealState.cancelled,
          });
          expect(record.reason, '历史原因');
          expect(record.resultText, '平台结果');
          if (relation == 'different') expect(value.reason, '当前处罚');
        },
      );
    }
  }
  test(
    'fresh empty penalty prevents POST even after earlier eligible query',
    () async {
      int gets = 0;
      int posts = 0;
      final server = await fixture.startServer((request) async {
        if (request.method == 'POST') {
          posts++;
          return fixture.reply(
            request,
            data: {'appealId': fixture.appealId, 'status': 'SUBMITTED'},
          );
        }
        gets++;
        return fixture.reply(
          request,
          data: {
            'penalty': gets == 1
                ? {'penaltyId': fixture.penaltyId, 'reason': 'test'}
                : <String, Object?>{},
            'appeal': <String, Object?>{},
          },
        );
      });
      addTearDown(() => server.close(force: true));
      final repo = BackendAccountComplianceRepository(
        apiClient: fixture.client(server),
      );
      await repo.queryAppeal(account: 'user7', reasonType: '1');
      await expectLater(
        repo.submitAppeal(
          account: 'user7',
          nickname: '',
          reason: '',
          reasonType: '1',
          explanation: '请平台核对这次处罚的相关证据',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(posts, 0);
      expect(gets, 2);
    },
  );
}
