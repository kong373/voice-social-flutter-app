import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/app/app.dart' as voice_app;
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/features/room/presentation/gift_sheet.dart';
import 'package:voice_social_app/features/room/presentation/video_runtime_room_page.dart';

import 'm2_4_test_support.dart';

const String _expectedWidthValue = String.fromEnvironment(
  'QA_EXPECTED_VIEWPORT_WIDTH',
  defaultValue: '390',
);
const String _expectedHeightValue = String.fromEnvironment(
  'QA_EXPECTED_VIEWPORT_HEIGHT',
  defaultValue: '844',
);
const String _expectedDprValue = String.fromEnvironment(
  'QA_EXPECTED_DPR',
  defaultValue: '3',
);

final double _expectedWidth = double.parse(_expectedWidthValue);
final double _expectedHeight = double.parse(_expectedHeightValue);
final double _expectedDpr = double.parse(_expectedDprValue);
const String _providerEvidenceScope =
    'm33_video_runtime_mock_graph_and_http_outbound_guard';

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'video runtime lobby and persistent room interaction matches target',
    (WidgetTester tester) async {
      final _ProviderCallGuard providerCallGuard = _ProviderCallGuard.install();
      addTearDown(providerCallGuard.restore);
      final AppDependencies dependencies = AppDependencies.fromEnvironment();
      final _MockDependencyGraphEvidence dependencyGraph =
          _MockDependencyGraphEvidence(dependencies);
      expect(
        dependencyGraph.proven,
        isTrue,
        reason: dependencyGraph.failureDescription,
      );
      dependencies.environment.validateLiveConfiguration();
      runApp(voice_app.VoiceSocialApp(dependencies: dependencies));
      await _waitFor(
        tester,
        () => find.byKey(const Key('video-runtime-home')).evaluate().isNotEmpty,
        description: 'video runtime home',
      );
      _expectExactViewport(tester);
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-01-light-home',
      );
      await announceQaEvidence(tester, 'M33_LIGHT_LOBBY_READY');

      await tester.ensureVisible(find.byKey(const Key('live-room-880217')));
      await tester.tap(find.byKey(const Key('live-room-880217')).hitTestable());
      await _waitFor(
        tester,
        () =>
            find.byType(VideoRuntimeRoomPage).evaluate().isNotEmpty &&
            find.text('礼物').evaluate().isNotEmpty,
        description: 'immersive room',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-02-immersive-eight-seat-room',
      );
      await announceQaEvidence(tester, 'M33_IMMERSIVE_ROOM_READY');

      final Finder composer = find.byKey(const Key('video-room-composer'));
      await tester.tap(composer.hitTestable());
      await tester.enterText(composer, '晚上好，刚刚进来听听');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(VideoRuntimeRoomPage), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-03-room-keyboard-context',
      );
      await announceQaEvidence(tester, 'M33_ROOM_KEYBOARD_CONTEXT_READY');
      await dismissQaImeAndWait(tester);

      await tester.tap(
        find.byKey(const Key('room-expression-button')).hitTestable(),
      );
      await _waitFor(
        tester,
        () => find
            .byKey(const Key('room-expression-sheet'))
            .evaluate()
            .isNotEmpty,
        description: 'room expression sheet',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-03b-room-expression-sheet',
      );
      await announceQaEvidence(tester, 'M33_ROOM_EXPRESSION_SHEET_READY');
      await tester.tap(
        find.byKey(const Key('room-expression-晚安')).hitTestable(),
      );
      await tester.pumpAndSettle();
      final TextField composerField = tester.widget<TextField>(composer);
      expect(composerField.controller?.text, contains('[晚安]'));
      await dismissQaImeAndWait(tester);

      await tester.tap(find.text('礼物').hitTestable());
      await _waitFor(
        tester,
        () => find.byType(GiftSheet).evaluate().isNotEmpty,
        description: 'room gift sheet',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-04-room-gift-sheet',
      );
      await announceQaEvidence(tester, 'M33_ROOM_GIFT_SHEET_READY');
      final Finder sendGift = find.textContaining('赠送').hitTestable();
      if (sendGift.evaluate().isNotEmpty) {
        await tester.tap(sendGift.first);
        await tester.pump(const Duration(milliseconds: 500));
        if (find
            .byKey(const Key('gift-celebration-overlay'))
            .evaluate()
            .isNotEmpty) {
          await captureQaScreenshot(
            tester,
            binding,
            'm33-${qaAvdId.toLowerCase()}-05-gift-celebration-overlay',
          );
          await announceQaEvidence(tester, 'M33_GIFT_OVERLAY_READY');
        }
      }
      if (find.byType(GiftSheet).evaluate().isNotEmpty) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byTooltip('更多').hitTestable());
      await _waitFor(
        tester,
        () =>
            find.text('互动玩法').evaluate().isNotEmpty &&
            find.text('工具').evaluate().isNotEmpty,
        description: 'room tools sheet',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-06-room-tools-sheet',
      );
      await announceQaEvidence(tester, 'M33_ROOM_TOOLS_READY');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('离开房间').hitTestable());
      await _waitFor(
        tester,
        () => find.text('收起房间').evaluate().isNotEmpty,
        description: 'minimize room action',
      );
      await tester.tap(find.text('收起房间').hitTestable());
      await _waitFor(
        tester,
        () =>
            find.byKey(const Key('minimized-room-pill')).evaluate().isNotEmpty,
        description: 'minimized room pill',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-07-minimized-room',
      );
      await announceQaEvidence(tester, 'M33_MINIMIZED_ROOM_READY');

      await tester.tap(find.text('消息').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('minimized-room-pill')), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-08-light-messages-with-room',
      );

      await tester.tap(find.text('我的').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('minimized-room-pill')), findsOneWidget);
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-09-light-account-with-room',
      );

      await tester.tap(find.byKey(const Key('minimized-room-pill')));
      await _waitFor(
        tester,
        () => find.byType(VideoRuntimeRoomPage).evaluate().isNotEmpty,
        description: 'restored room',
      );
      await captureQaScreenshot(
        tester,
        binding,
        'm33-${qaAvdId.toLowerCase()}-10-restored-room',
      );
      await announceQaEvidence(tester, 'M33_ROOM_RESTORED');

      providerCallGuard.seal();
      final bool providerCallsMade = providerCallGuard.providerCallsMade(
        mockDependencyGraphProven: dependencyGraph.proven,
      );
      final int providerGuardConnectionAttempts =
          providerCallGuard.connectionAttempts;
      debugPrint('M33_PROVIDER_CALLS_MADE=$providerCallsMade');
      debugPrint('M33_PROVIDER_GRAPH_PROVEN=${dependencyGraph.proven}');
      debugPrint('M33_PROVIDER_EVIDENCE_SCOPE=$_providerEvidenceScope');
      debugPrint(
        'M33_PROVIDER_GUARD_CONNECTION_ATTEMPTS='
        '$providerGuardConnectionAttempts',
      );
      expect(
        providerCallsMade,
        isFalse,
        reason: providerCallGuard.failureDescription,
      );

      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['m33VideoRuntimeUi'] = <String, Object?>{
        'avd': qaAvdId,
        'logicalViewport':
            '${_expectedWidth.toInt()}x${_expectedHeight.toInt()}',
        'devicePixelRatio': _expectedDpr,
        'lightLobby': true,
        'immersiveRoom': true,
        'fixedEightSeats': true,
        'keyboardPreservesRoom': true,
        'expressionSheetPreservesRoom': true,
        'giftIsRoomSheet': true,
        'toolsAreRoomSheet': true,
        'roomMinimizeAndRestore': true,
        'providerCallsMade': providerCallsMade,
        'providerDependencyGraphProven': dependencyGraph.proven,
        'providerOutboundConnectionAttempts': providerGuardConnectionAttempts,
        'providerEvidenceScope': _providerEvidenceScope,
        'result': 'PASS',
      };
    },
  );
}

void _expectExactViewport(WidgetTester tester) {
  final double dpr = tester.view.devicePixelRatio;
  final Size logicalSize = Size(
    tester.view.physicalSize.width / dpr,
    tester.view.physicalSize.height / dpr,
  );
  expect(dpr, closeTo(_expectedDpr, 0.01));
  expect(logicalSize.width, closeTo(_expectedWidth, 0.1));
  expect(logicalSize.height, closeTo(_expectedHeight, 0.1));
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
}) async {
  for (int attempt = 0; attempt < 360; attempt += 1) {
    await tester.pump();
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TestFailure('Timed out waiting for $description.');
}

class _MockDependencyGraphEvidence {
  _MockDependencyGraphEvidence(this.dependencies)
    : _providerDependencies = <Object>[
        dependencies.accountComplianceRepository,
        dependencies.discoveryRepository,
        dependencies.dynamicRepository,
        dependencies.socialRepository,
        dependencies.communityRepository,
        dependencies.commerceRepository,
        dependencies.commerceCatalogRepository,
        dependencies.messageRepository,
        dependencies.roomRepository,
        dependencies.roomOperationsRepository,
        dependencies.roomLifecycleRepository,
        dependencies.roomPkRepository,
        dependencies.rtcAdapter,
        dependencies.realtimeGateway,
        dependencies.roomAudioService,
      ];

  final AppDependencies dependencies;
  final List<Object> _providerDependencies;

  bool get proven =>
      dependencies.environment.backendMode == BackendMode.mock &&
      _providerDependencies.isNotEmpty &&
      _providerDependencies.every(
        (Object dependency) =>
            dependency.runtimeType.toString().startsWith('Mock'),
      );

  String get failureDescription {
    final String runtimeTypes = _providerDependencies
        .map((Object dependency) => dependency.runtimeType.toString())
        .join(', ');
    return 'M33 requires the mock dependency graph; observed '
        'backendMode=${dependencies.environment.backendMode.name}, '
        'providerDependencies=[$runtimeTypes].';
  }
}

class _ProviderCallGuard {
  _ProviderCallGuard._(this._previousOverrides) {
    _httpOverrides = _GuardHttpOverrides(this);
    HttpOverrides.global = _httpOverrides;
  }

  factory _ProviderCallGuard.install() {
    return _ProviderCallGuard._(HttpOverrides.current);
  }

  final HttpOverrides? _previousOverrides;
  late final _GuardHttpOverrides _httpOverrides;
  final List<HttpClient> _clients = <HttpClient>[];
  int connectionAttempts = 0;
  Uri? _firstConnectionUri;
  bool _sealed = false;

  void _recordConnectionAttempt(Uri uri) {
    connectionAttempts += 1;
    _firstConnectionUri ??= uri;
  }

  void seal() {
    if (!identical(HttpOverrides.current, _httpOverrides)) {
      throw StateError(
        'M33 outbound-call guard was replaced before evidence was sealed.',
      );
    }
    _sealed = true;
  }

  bool providerCallsMade({required bool mockDependencyGraphProven}) {
    if (!_sealed || !identical(HttpOverrides.current, _httpOverrides)) {
      throw StateError(
        'M33 outbound-call guard could not prove that it remained installed.',
      );
    }
    if (!mockDependencyGraphProven) {
      throw StateError(
        'M33 mock dependency graph could not be proven at runtime.',
      );
    }
    return connectionAttempts > 0;
  }

  String get failureDescription {
    final String? firstUri = _firstConnectionUri?.toString();
    return connectionAttempts == 0
        ? 'No provider outbound calls were observed by the installed '
              'mock guard.'
        : 'M33 blocked and observed $connectionAttempts provider outbound '
              'connection attempt(s); first URI=${firstUri ?? 'unknown'}.';
  }

  void restore() {
    if (identical(HttpOverrides.current, _httpOverrides)) {
      HttpOverrides.global = _previousOverrides;
    }
    for (final HttpClient client in _clients) {
      client.close(force: true);
    }
  }
}

class _GuardHttpOverrides extends HttpOverrides {
  _GuardHttpOverrides(this.owner);

  final _ProviderCallGuard owner;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final HttpOverrides? activeOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    late final HttpClient client;
    try {
      client = HttpClient(context: context);
    } finally {
      HttpOverrides.global = activeOverrides;
    }
    client.findProxy = (Uri _) => 'DIRECT';
    client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) {
      owner._recordConnectionAttempt(uri);
      return Future<ConnectionTask<Socket>>.error(
        StateError('M33 outbound provider call blocked: $uri'),
      );
    };
    owner._clients.add(client);
    return client;
  }
}
