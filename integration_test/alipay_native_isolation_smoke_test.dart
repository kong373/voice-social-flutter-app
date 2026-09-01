import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/features/account/application/auth_controller.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/alipay_focused_smoke_selection.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/infrastructure/alipay_app_pay_adapter.dart';

const String _runId = String.fromEnvironment(
  'QA_ALIPAY_NATIVE_ISOLATION_RUN_ID',
);
const String _probeInvocationId = String.fromEnvironment(
  'QA_ALIPAY_PROBE_INVOCATION_ID',
);
const String _payloadName = 'm5-alipay-native-isolation.json';
const String _resultName = 'm5-alipay-native-isolation-result.json';
const bool _negativeOnly = bool.fromEnvironment(
  'QA_ALIPAY_NATIVE_ISOLATION_NEGATIVE_ONLY',
);
const Duration _nativeResultTimeout = Duration(seconds: 150);
final RegExp _runIdPattern = RegExp(r'^[a-f0-9]{32}$');
const MethodChannel _nativeIsolationChannel = MethodChannel(
  'voice_social_app/alipay_app_pay',
);

void _marker(String stage, String result) {
  debugPrint('M5_ALIPAY_NATIVE_ISOLATION::$stage::$result');
}

void _focusedMarker(String stage, String result) {
  debugPrint('M5_ALIPAY_FOCUSED::$stage::$result');
}

void _probeMarker(String stage) {
  debugPrint('M5_ALIPAY_PROBE_INVOCATION::$stage::$_probeInvocationId');
}

Future<Directory> _privateFilesDirectory() async {
  final String? path = await _nativeIsolationChannel.invokeMethod<String>(
    'nativeIsolationFilesDirectory',
    <String, Object>{'runId': _runId},
  );
  if (path == null || path.trim() != path || !path.startsWith('/')) {
    throw const FileSystemException('Android private files directory missing.');
  }
  final Directory canonicalFiles = Directory(
    await Directory(path).resolveSymbolicLinks(),
  );
  final List<String> segments = canonicalFiles.path.split(
    Platform.pathSeparator,
  );
  if (segments.length < 3 ||
      segments.last != 'files' ||
      segments[segments.length - 2] != 'com.kong373.voice_social_app') {
    throw const FileSystemException('Android private files path escaped.');
  }
  return canonicalFiles;
}

Future<void> _deleteIfPresent(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

Future<void> _stagePayload({
  required Directory files,
  required String orderString,
}) async {
  if (orderString.isEmpty ||
      orderString.length > 64 * 1024 ||
      orderString.trim() != orderString ||
      orderString.runes.any((int value) => value < 0x20 || value == 0x7f)) {
    throw const FormatException('Invalid signed order payload.');
  }
  final File payload = File('${files.path}/$_payloadName');
  final File result = File('${files.path}/$_resultName');
  final File temporary = File('${files.path}/$_payloadName.tmp-$_runId');
  await _deleteIfPresent(payload);
  await _deleteIfPresent(result);
  await _deleteIfPresent(temporary);
  final String encoded = jsonEncode(<String, Object>{
    'runId': _runId,
    'sandbox': true,
    'orderStr': orderString,
  });
  await temporary.writeAsString(encoded, flush: true);
  await temporary.rename(payload.path);
}

Future<void> _launchNativeIsolation({bool expectRejected = false}) async {
  _marker('LAUNCH_CALL', _runId);
  bool? launched;
  try {
    launched = await _nativeIsolationChannel
        .invokeMethod<bool>('launchNativeIsolation', <String, Object>{
          'runId': _runId,
        })
        .timeout(const Duration(seconds: 10));
  } on PlatformException catch (error) {
    if (expectRejected && error.code == 'debug_unavailable') {
      _marker('LAUNCH_REJECTED', _runId);
      return;
    }
    rethrow;
  }
  if (expectRejected) {
    throw TestFailure(
      'Native isolation unexpectedly accepted missing payload.',
    );
  }
  if (launched != true) {
    throw TestFailure('Native isolation launcher unavailable.');
  }
  _marker('LAUNCH_RETURN', _runId);
}

Future<AlipayAppPayResult> _waitForNativeResult(Directory files) async {
  final File resultFile = File('${files.path}/$_resultName');
  final DateTime deadline = DateTime.now().add(_nativeResultTimeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await resultFile.exists()) {
      final int length = await resultFile.length();
      if (length < 2 || length > 1024) {
        throw const FormatException('Native result file length invalid.');
      }
      final Object? decoded = jsonDecode(await resultFile.readAsString());
      await resultFile.delete();
      if (decoded is! Map<String, Object?> ||
          decoded.keys.toSet().difference(<String>{
            'runId',
            'sdkCompleted',
            'resultStatus',
            'bridgeOutcome',
          }).isNotEmpty ||
          decoded.length != 4 ||
          decoded['runId'] != _runId ||
          decoded['sdkCompleted'] is! bool ||
          decoded['resultStatus'] is! String ||
          decoded['bridgeOutcome'] is! String) {
        throw const FormatException('Native result contract invalid.');
      }
      final bool sdkCompleted = decoded['sdkCompleted']! as bool;
      final String resultStatus = decoded['resultStatus']! as String;
      final String bridgeOutcome = decoded['bridgeOutcome']! as String;
      const Set<String> allowedStatuses = <String>{
        '9000',
        '8000',
        '6004',
        '6002',
        '6001',
        '4000',
        'none',
      };
      const Set<String> allowedOutcomes = <String>{
        'pay_task_returned',
        'native_watchdog_timeout',
        'native_exception',
        'native_unavailable',
      };
      if (!allowedStatuses.contains(resultStatus) ||
          !allowedOutcomes.contains(bridgeOutcome) ||
          sdkCompleted != (resultStatus == '9000') ||
          (bridgeOutcome != 'pay_task_returned' && resultStatus != 'none')) {
        throw const FormatException('Native result values invalid.');
      }
      final AlipayAppPayBridgeOutcome? provenance =
          AlipayAppPayBridgeOutcome.fromWire(bridgeOutcome);
      if (provenance == null) {
        throw const FormatException('Native result provenance invalid.');
      }
      return switch (resultStatus) {
        '9000' => AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.sdkCompleted,
          reason: AlipayAppPayReason.processing,
          sdkCompleted: true,
          resultStatus: resultStatus,
          bridgeOutcome: provenance,
        ),
        '6001' => AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.userCanceled,
          reason: AlipayAppPayReason.userCanceled,
          sdkCompleted: false,
          resultStatus: resultStatus,
          bridgeOutcome: provenance,
        ),
        '8000' || '6004' => AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.processing,
          reason: AlipayAppPayReason.processing,
          sdkCompleted: false,
          resultStatus: resultStatus,
          bridgeOutcome: provenance,
        ),
        '6002' => AlipayAppPayResult(
          outcome: AlipayAppPayOutcome.networkError,
          reason: AlipayAppPayReason.network,
          sdkCompleted: false,
          resultStatus: resultStatus,
          bridgeOutcome: provenance,
        ),
        _ => AlipayAppPayResult(
          outcome: bridgeOutcome == 'native_watchdog_timeout'
              ? AlipayAppPayOutcome.processing
              : AlipayAppPayOutcome.failed,
          reason: switch (bridgeOutcome) {
            'native_watchdog_timeout' => AlipayAppPayReason.timeout,
            'native_unavailable' => AlipayAppPayReason.nativeUnavailable,
            _ => AlipayAppPayReason.vendorFailed,
          },
          sdkCompleted: false,
          resultStatus: resultStatus == 'none' ? null : resultStatus,
          bridgeOutcome: provenance,
        ),
      };
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return const AlipayAppPayResult(
    outcome: AlipayAppPayOutcome.processing,
    reason: AlipayAppPayReason.timeout,
    sdkCompleted: false,
    bridgeOutcome: AlipayAppPayBridgeOutcome.dartWatchdogTimeout,
  );
}

Future<void> _cleanupPrivateFiles(Directory? files) async {
  if (files == null) {
    return;
  }
  for (final String name in <String>[
    _payloadName,
    _resultName,
    '$_payloadName.tmp-$_runId',
    '$_resultName.tmp',
  ]) {
    try {
      await _deleteIfPresent(File('${files.path}/$name'));
    } catch (_) {
      // Cleanup is best effort; never print a path or payload.
    }
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'same-application native PayTask isolation remains cancel-only',
    (WidgetTester tester) async {
      final AppDependencies dependencies = AppDependencies.fromEnvironment();
      Directory? privateFiles;
      RechargeOrder? createdOrder;
      AlipayAppPayResult? nativeResult;
      String failureStage = 'startup';
      try {
        _marker('ENTER_TEST', _runId);
        failureStage = 'config';
        if (!Platform.isAndroid ||
            !_runIdPattern.hasMatch(_runId) ||
            !_runIdPattern.hasMatch(_probeInvocationId) ||
            !dependencies.environment.isLive ||
            !dependencies.environment.enableAlipayAppPay ||
            !dependencies.environment.useAlipaySandbox) {
          throw TestFailure('Native isolation configuration invalid.');
        }
        failureStage = 'files';
        privateFiles = await _privateFilesDirectory();
        await _cleanupPrivateFiles(privateFiles);

        if (_negativeOnly) {
          failureStage = 'negative_launch';
          await _launchNativeIsolation(expectRejected: true);
          failureStage = 'negative_settle';
          await Future<void>.delayed(const Duration(seconds: 2));
          failureStage = 'negative_check';
          final bool payloadExists = await File(
            '${privateFiles.path}/$_payloadName',
          ).exists();
          final bool resultExists = await File(
            '${privateFiles.path}/$_resultName',
          ).exists();
          if (payloadExists || resultExists) {
            throw TestFailure('Native isolation negative gate failed.');
          }
          _marker('NEGATIVE_GATE', 'PASS');
          await tester.pump();
          return;
        }

        await dependencies.authController.initialize();
        if (dependencies.authController.stage != AuthFlowStage.signedIn ||
            dependencies.authController.session == null) {
          throw TestFailure('Persisted authenticated session required.');
        }
        final session = dependencies.authController.session!;
        if (session.mobile.trim().isEmpty) {
          throw TestFailure('Persisted account identity missing.');
        }

        final repository = dependencies.commerceCatalogRepository;
        final List<RechargeProduct> products = await repository
            .fetchRechargeProducts(platform: ClientStorePlatform.android);
        final RechargeProduct? product =
            selectLowestPositiveEnabledRechargeProduct(products);
        if (product == null || !repository.supportsPaymentChannelInvocation) {
          throw TestFailure('Alipay catalog not ready.');
        }
        _focusedMarker('catalog', 'PASS');
        createdOrder = await repository.createRechargeOrder(
          account: session.mobile,
          product: product,
          channel: PaymentChannelType.alipay,
          platform: ClientStorePlatform.android,
          youthModeEnabled: false,
        );
        final String? orderString = createdOrder.paymentOrderString;
        if (createdOrder.orderNo.trim().isEmpty ||
            orderString == null ||
            orderString.isEmpty) {
          throw TestFailure('Server order unavailable.');
        }
        _focusedMarker('order', 'PASS');

        _probeMarker('START');
        failureStage = 'payload_stage';
        await _stagePayload(files: privateFiles, orderString: orderString);
        _marker('PAYLOAD_STAGED', _runId);
        _focusedMarker('native_launcher', 'START');
        failureStage = 'native_launch';
        await _launchNativeIsolation();
        failureStage = 'native_wait';
        nativeResult = await _waitForNativeResult(privateFiles);
        _probeMarker('RETURN');
        debugPrint(
          'M5_ALIPAY_NATIVE_RESULT::sdkCompleted=${nativeResult.sdkCompleted ? 1 : 0}::'
          'resultStatus=${nativeResult.resultStatus ?? 'none'}',
        );
        debugPrint(
          'M5_ALIPAY_NATIVE_BRIDGE_OUTCOME::'
          '${nativeResult.bridgeOutcome?.wireName ?? 'none'}',
        );

        final RechargeOrder provisional = createdOrder
            .copyWith(state: RechargeOrderState.confirming)
            .withNativeBridgeResult(
              sdkCompleted: nativeResult.sdkCompleted,
              resultStatus: nativeResult.resultStatus,
              outcome: nativeResult.outcome.name,
              reason: nativeResult.reason.name,
              bridgeOutcome: nativeResult.bridgeOutcome?.wireName,
            );
        final bool trustedCancellation =
            !nativeResult.sdkCompleted &&
            nativeResult.resultStatus == '6001' &&
            nativeResult.outcome == AlipayAppPayOutcome.userCanceled &&
            nativeResult.reason == AlipayAppPayReason.userCanceled &&
            nativeResult.bridgeOutcome ==
                AlipayAppPayBridgeOutcome.payTaskReturned;
        if (!trustedCancellation) {
          failureStage = 'authoritative_reconcile';
          if (!nativeResult.sdkCompleted &&
              nativeResult.resultStatus != '9000') {
            try {
              await repository.queryRechargeOrder(provisional);
              _focusedMarker('query_reconcile', 'PASS');
            } catch (_) {
              _focusedMarker('query_reconcile', 'FAIL');
            }
          }
          throw TestFailure('Native isolation cancellation not proven.');
        }
        _focusedMarker('native_launcher', 'PASS');
        final RechargeOrder authoritative = await repository.queryRechargeOrder(
          provisional,
        );
        if (authoritative.state != RechargeOrderState.canceled) {
          throw TestFailure('First-party cancellation not authoritative.');
        }
        _focusedMarker('query_reconcile', 'PASS');
        _focusedMarker('complete', 'PASS');
        await tester.pump();
      } catch (_) {
        _marker('FAIL_STAGE', failureStage);
        _focusedMarker('complete', 'FAIL');
        throw TestFailure('Native Alipay isolation evidence incomplete.');
      } finally {
        await _cleanupPrivateFiles(privateFiles);
        dependencies.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
    skip: !Platform.isAndroid,
  );
}
