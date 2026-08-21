import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String contractTestAuthorization = 'Bearer contract-test';

String captureContractAuthorization(HttpRequest request) {
  final String? authorization = request.headers.value(
    HttpHeaders.authorizationHeader,
  );
  expect(
    authorization,
    contractTestAuthorization,
    reason:
        'Expected Authorization header on ${request.method} ${request.uri.path}',
  );
  return authorization ?? '';
}
