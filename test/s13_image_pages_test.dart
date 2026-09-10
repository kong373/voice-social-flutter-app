import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/media/media_models.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/backend_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/media/image_widgets.dart';
import 'package:voice_social_app/features/social/data/backend_social_repository.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';
import 'support/media_http_fakes.dart';
import 's13_image_host_test.dart' show hostStatus, TestImageSelection;
import 's13_image_domain_contract_test.dart'
    show imagePost, imageTicket, imageReference;

class _Dependencies implements AppDependencies {
  _Dependencies(
    this.imageMediaHost,
    this.dynamicRepository,
    this.socialRepository,
  );
  @override
  final AppImageMediaHost imageMediaHost;
  @override
  final DynamicRepository dynamicRepository;
  @override
  final SocialRepository socialRepository;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TestMediaIdentity identity;
  late Directory temp;
  late MediaFakeHttp http;
  late AppImageMediaHost host;
  late _Dependencies dependencies;
  late FutureOr<MediaFakeResponse> Function(MediaFakeRequest) domain;
  setUp(() async {
    identity = TestMediaIdentity();
    temp = await Directory.systemTemp.createTemp('s13-image-widget-test-');
    var purpose = 'DYNAMIC_IMAGE';
    domain = (r) => MediaFakeResponse.json(
      imagePost()..['media'] = [imageReference('DYNAMIC_IMAGE')..['bytes'] = 3],
    );
    http = MediaFakeHttp((r) {
      if (r.uri.path == '/app-api/media/v1/assets') {
        purpose = (jsonDecode(utf8.decode(r.body)) as Map)['purpose'] as String;
        return MediaFakeResponse.json(
          hostStatus('ALLOCATED', 0, purpose: purpose),
        );
      }
      if (r.method == 'PUT')
        return MediaFakeResponse.json(
          hostStatus('UPLOADING', 1, purpose: purpose, bytes: 3),
        );
      if (r.uri.path.endsWith('/complete'))
        return MediaFakeResponse.json(
          hostStatus('READY', 2, purpose: purpose, bytes: 3),
        );
      return domain(r);
    });
    final api = http.api(identity);
    host = AppImageMediaHost(
      api: api,
      userId: () => identity.user,
      generation: () => identity.generation,
      changes: identity,
      picker: TestImageSelection(),
      temporaryParent: () async => temp,
    );
    dependencies = _Dependencies(
      host,
      BackendDynamicRepository(
        apiClient: api,
        routes: const BackendRouteCatalog(),
        currentUserIdProvider: () => identity.user,
        identityGeneration: () => identity.generation,
        commentIdentityChanges: identity,
      ),
      BackendSocialRepository(
        apiClient: api,
        currentUserIdProvider: () => identity.user,
        identityGeneration: () => identity.generation,
      ),
    );
  });
  tearDown(() async {
    identity.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });
  void imageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        host.dispose();
        var done = false;
        final cleanup = host.cleanup.then((_) => done = true);
        for (var i = 0; !done && i < 100; i++) {
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(
          done,
          isTrue,
          reason:
              'owned file cleanup must finish inside the widget FakeAsync scope',
        );
        await cleanup;
      }
    });
  }

  Future<void> mount(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      AppDependencyScope(
        dependencies: dependencies,
        child: MaterialApp(home: page),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> waitForAsyncUi(
    WidgetTester tester,
    bool Function() reached,
    String reason,
  ) async {
    for (var i = 0; !reached() && i < 200; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(reached(), isTrue, reason: reason);
  }

  Future<void> click(WidgetTester tester, Finder finder) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    if (finder.evaluate().isEmpty)
      await tester.scrollUntilVisible(
        finder,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickAndUpload(WidgetTester tester, ImageDraft draft) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('media-pick-images')).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('media-pick-images')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.byKey(const ValueKey('media-pick-images')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('media-pick-images')));
      for (var i = 0; draft.picking && i < 1000; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    });
    await tester.pumpAndSettle();
    expect(draft.images.length, 1);
    await Scrollable.ensureVisible(
      tester.element(find.text('上传图片')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('上传图片'));
      await draft.images.single.flight;
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('已上传'), findsOneWidget);
  }

  imageTest(
    'pure-image publishing requires READY and sends only asset IDs through real repository',
    (tester) async {
      await mount(tester, const PublishDynamicPage());
      final draft = host.draft('dynamic:publish', MediaPurpose.dynamicImage);
      await pickAndUpload(tester, draft);
      await click(tester, find.widgetWithText(FilledButton, '发布动态'));
      final writes = http.requests
          .where((r) => r.uri.path.endsWith('/dynamic/publish'))
          .toList();
      expect(writes.length, 1);
      expect(jsonDecode(utf8.decode(writes.single.body)), {
        'content': '',
        'category': 'LIFE',
        'topic': '',
        'location': '',
        'mediaAssetIds': [
          draft.images.isEmpty
              ? '11111111-2222-4333-8444-555555555555'
              : draft.images.single.status!.assetId,
        ],
      });
      expect(http.requests.where((r) => r.method == 'PUT').length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  imageTest(
    'unknown publish survives unmount; A B A clears UI and restores original body/key',
    (tester) async {
      var fail = true;
      domain = (r) => fail
          ? MediaFakeResponse.json(null, status: 409, code: 40901)
          : MediaFakeResponse.json(imagePost(content: 'A原文')..['media'] = []);
      await mount(tester, const PublishDynamicPage());
      await tester.enterText(find.byType(TextFormField), 'A原文');
      await click(tester, find.widgetWithText(FilledButton, '发布动态'));
      expect(find.textContaining('已保留原内容'), findsOneWidget);
      identity.change(2);
      await tester.pumpAndSettle();
      expect(find.text('A原文'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mount(tester, const PublishDynamicPage());
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '',
      );
      identity.change(1);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await mount(tester, const PublishDynamicPage());
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'A原文',
      );
      fail = false;
      await click(tester, find.widgetWithText(FilledButton, '发布动态'));
      final writes = http.requests
          .where((r) => r.uri.path.endsWith('/dynamic/publish'))
          .toList();
      expect(writes.length, 2);
      expect(writes[0].body, writes[1].body);
      expect(
        writes[0].headers.value('X-Request-Id'),
        writes[1].headers.value('X-Request-Id'),
      );
      expect(writes[0].headers.value('Authorization'), 'Bearer contract-A-old');
      expect(writes[1].headers.value('Authorization'), 'Bearer contract-1');
      await tester.pumpWidget(const SizedBox());
    },
  );
  imageTest(
    'support reply requires text, three-image selection is event-scoped, history preview available',
    (tester) async {
      domain = (r) => MediaFakeResponse.json(
        imageTicket(reply: r.method == 'POST')
          ..['events'] = [
            ...(imageTicket(reply: r.method == 'POST')['events'] as List).map(
              (e) => (e as Map<String, Object?>)
                ..['media'] = [imageReference('SUPPORT_IMAGE')..['bytes'] = 3],
            ),
          ],
      );
      final initial = SupportTicket(
        id: 'ticket-1',
        subject: '主题',
        content: '描述',
        status: SupportTicketStatus.processing,
        statusText: '处理中',
        createdAt: DateTime.utc(2026),
        progressAvailable: true,
      );
      await mount(tester, SupportTicketPage(initialTicket: initial));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(ListView),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      await tester.scrollUntilVisible(
        find.text('查看图片'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('查看图片'), findsOneWidget);
      final draft = host.draft(
        'support:reply:ticket-1',
        MediaPurpose.supportImage,
      );
      await pickAndUpload(tester, draft);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('support-reply-submit')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('support-reply-input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('support-reply-input')),
        '补充',
      );
      await click(tester, find.byKey(const ValueKey('support-reply-submit')));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      final write = http.requests.singleWhere(
        (r) => r.uri.path.endsWith('/replies'),
      );
      expect(jsonDecode(utf8.decode(write.body)), {
        'message': '补充',
        'mediaAssetIds': ['11111111-2222-4333-8444-555555555555'],
      });
      expect(find.text('补充内容已提交'), findsOneWidget);
      identity.change(2);
      await tester.pumpAndSettle();
      expect(find.text('查看图片'), findsNothing);
      expect(find.text('描述'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  imageTest(
    'controlled preview shows permission errors, never external URLs, and fences late identity',
    (tester) async {
      final denied = Completer<MediaFakeResponse>();
      domain = (r) => denied.future;
      final media = MediaReference.fromJson(imageReference('DYNAMIC_IMAGE'));
      await mount(tester, Scaffold(body: ControlledImages(media: [media])));
      await tester.tap(find.text('查看图片'));
      await waitForAsyncUi(
        tester,
        () => http.requests.length == 1,
        'controlled GET must start before completing its permission response',
      );
      expect(find.text('读取图片…'), findsOneWidget);
      denied.complete(MediaFakeResponse.json(null, status: 403, code: 40301));
      await waitForAsyncUi(
        tester,
        () => find.text('重试读取图片').evaluate().length == 1,
        'await file cleanup and the permission error UI, not a fixed 20ms sleep',
      );
      expect(find.text('重试读取图片'), findsOneWidget);
      expect(
        http.requests.single.uri.path,
        '/app-api/media/v1/assets/11111111-2222-4333-8444-555555555555/content',
      );
      final gate = Completer<MediaFakeResponse>();
      domain = (_) => gate.future;
      await tester.tap(find.text('重试读取图片'));
      await waitForAsyncUi(
        tester,
        () => http.requests.length == 2,
        'retry must reach HTTP before the identity changes',
      );
      identity.change(2);
      identity.change(1);
      await tester.pumpAndSettle();
      gate.complete(
        MediaFakeResponse(
          200,
          Stream.value(List.filled(12, 1)),
          contentLength: 12,
          type: 'image/png',
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('账号已变化'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  imageTest(
    'support create keeps mandatory text with images and displays authoritative event attachments',
    (tester) async {
      domain = (r) {
        if (r.uri.path.endsWith('getCustomerServiceDetail'))
          return MediaFakeResponse.json({'accid': 'support'});
        final ticket = imageTicket();
        ticket['events'] = [
          (ticket['events'] as List).single as Map<String, Object?>
            ..['media'] = [imageReference('SUPPORT_IMAGE')..['bytes'] = 3],
        ];
        return MediaFakeResponse.json(ticket);
      };
      await mount(tester, const HelpCenterPage());
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(ListView),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      final draft = host.draft('support:create', MediaPurpose.supportImage);
      await pickAndUpload(tester, draft);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, '提交反馈'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交反馈'))
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(TextField, '问题描述'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.widgetWithText(TextField, '问题描述'), '描述');
      await tester.enterText(find.widgetWithText(TextField, '问题主题'), '主题');
      await click(tester, find.widgetWithText(FilledButton, '提交反馈'));
      final request = http.requests.singleWhere(
        (r) => r.uri.path.endsWith('/saveSugggestion'),
      );
      expect(jsonDecode(utf8.decode(request.body)), {
        'subject': '主题',
        'content': '描述',
        'mediaAssetIds': ['11111111-2222-4333-8444-555555555555'],
      });
      expect(find.text('工单详情与处理进度'), findsOneWidget);
    },
  );
  imageTest(
    'controlled binary preview renders real PNG then clears decoded image on logout',
    (tester) async {
      final bytes = (await tester.runAsync(
        () => File('assets/runtime/avatar-copper.png').readAsBytes(),
      ))!;
      domain = (r) => MediaFakeResponse(
        200,
        Stream.value(bytes),
        contentLength: bytes.length,
        type: 'image/png',
      );
      final media = MediaReference.fromJson(
        imageReference('DYNAMIC_IMAGE')..['bytes'] = bytes.length,
      );
      await mount(tester, Scaffold(body: ControlledImages(media: [media])));
      await click(tester, find.text('查看图片'));
      for (var i = 0; find.byType(Image).evaluate().isEmpty && i < 20; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pumpAndSettle();
      }
      expect(find.byType(Image), findsOneWidget);
      for (
        var i = 0;
        i < 20 &&
            (find.byType(RawImage).evaluate().isEmpty ||
                tester.widget<RawImage>(find.byType(RawImage)).image == null);
        i++
      ) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pumpAndSettle();
      }
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
      identity.change(0);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('账号已变化'), findsOneWidget);
      expect(http.requests.length, 1);
    },
  );
  imageTest('selected but unready image cannot reach domain POST', (
    tester,
  ) async {
    final draft = host.draft('dynamic:publish', MediaPurpose.dynamicImage);
    await tester.runAsync(() => host.pick(draft));
    await mount(tester, const PublishDynamicPage());
    await click(tester, find.widgetWithText(FilledButton, '发布动态'));
    expect(http.requests, isEmpty);
    expect(find.textContaining('请先完成每张图片'), findsOneWidget);
  });
  imageTest(
    'late publish success after ABA cannot close old page or become current receipt',
    (tester) async {
      final gate = Completer<MediaFakeResponse>();
      domain = (_) => gate.future;
      await mount(tester, const PublishDynamicPage());
      await tester.enterText(find.byType(TextFormField), 'A原文');
      await click(tester, find.widgetWithText(FilledButton, '发布动态'));
      expect(http.requests.length, 1);
      identity.change(2);
      identity.change(1);
      await tester.pumpAndSettle();
      gate.complete(
        MediaFakeResponse.json(imagePost(content: 'A原文')..['media'] = []),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('账号已变化'), findsOneWidget);
      final draft = host.draft('dynamic:publish', MediaPurpose.dynamicImage);
      expect(draft.receipt, isNull);
      expect(draft.locked, isTrue);
    },
  );
}
