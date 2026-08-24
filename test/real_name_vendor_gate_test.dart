import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/account/compliance/data/backend_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/data/mock_account_compliance_repository.dart';
import 'package:voice_social_app/features/account/compliance/domain/account_compliance.dart';
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';

void main() {
  test(
    'live real-name adapter blocks vendor submission before any request',
    () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      var requests = 0;
      server.listen((HttpRequest request) async {
        requests += 1;
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, Object?>{
              'code': 500,
              'message': 'unexpected request',
            }),
          );
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final ApiClient client = ApiClient(
        baseUri: Uri.parse('http://${server.address.address}:${server.port}/'),
        clientType: 'Android',
        clientInnerVersion: '6',
        authorizationProvider: () => 'Bearer access-token',
        timeout: const Duration(seconds: 1),
      );
      final BackendAccountComplianceRepository repository =
          BackendAccountComplianceRepository(
            apiClient: client,
            supportsRealNameSubmission: false,
          );

      await expectLater(
        repository.submitRealName(
          realName: '张三',
          idNumber: '42010619960820123X',
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException error) => error.kind,
                'kind',
                ApiFailureKind.business,
              )
              .having(
                (ApiException error) => error.message,
                'message',
                contains('VENDOR_BLOCKED'),
              ),
        ),
      );
      expect(repository.supportsRealNameSubmission, isFalse);
      expect(requests, 0);
    },
  );

  testWidgets('blocked live real-name state hides the identity form', (
    WidgetTester tester,
  ) async {
    final AppDependencies dependencies = AppDependencies.forTestEnvironment(
      environment: const AppEnvironment(
        backendMode: BackendMode.live,
        apiBaseUrl: 'https://example.invalid',
        clientType: 'Android',
        clientInnerVersion: '6',
        oauthClientId: 'public-client',
        realtimeEndpoint: '',
        deploymentEnvironment: DeploymentEnvironment.production,
      ),
      accountComplianceRepository: _BlockedRealNameRepository(),
    );
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: const MaterialApp(
          home: RealNamePage(
            account: '13800138000',
            currentVersion: 6,
            platformType: 1,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('VENDOR_BLOCKED'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('提交认证'), findsNothing);
  });
}

class _BlockedRealNameRepository extends MockAccountComplianceRepository {
  @override
  bool get supportsRealNameSubmission => false;

  @override
  Future<AccountComplianceSnapshot> fetchSnapshot({
    required String account,
    required int currentVersion,
    required int platformType,
  }) => super.fetchSnapshot(
    account: account,
    currentVersion: currentVersion,
    platformType: platformType,
  );
}
