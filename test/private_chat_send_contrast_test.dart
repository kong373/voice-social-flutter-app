import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/message/data/mock_message_repository.dart';
import 'package:voice_social_app/features/message/domain/message_models.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';

import 'support/golden_font_gate.dart';

const _captureKey = Key('chat-send-contrast-capture');
final _send = find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == '发送消息',
);

void main() {
  for (final scale in <double>[1, 1.3]) {
    for (final enabled in <bool>[true, false]) {
      testWidgets('social chat send enabled=$enabled textScale=$scale', (
        tester,
      ) async {
        await loadGoldenFonts();
        tester.view.devicePixelRatio = 2.4;
        tester.view.physicalSize = const Size(864, 1920);
        tester.view.padding = const FakeViewPadding(top: 72, bottom: 24);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewInsets);

        final repository = _SendRepository(enabled);
        final dependencies = AppDependencies.forTestEnvironment(
          environment: AppEnvironment.mock(),
          messageRepository: repository,
        );
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: AppTheme.social(fontFamily: kGoldenFontFamily),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: _captureKey, child: child!),
              ),
              home: PrivateChatPage(
                conversation: ConversationSummary(
                  id: 'contrast-conversation',
                  kind: ConversationKind.privateChat,
                  title: '聊天对象',
                  lastMessage: '',
                  updatedAt: DateTime(2026, 9, 23),
                  unreadCount: 0,
                  targetUserId: 10002,
                ),
              ),
            ),
          ),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          dependencies.dispose();
        });
        await tester.pumpAndSettle();
        if (enabled) {
          await tester.enterText(find.byType(TextField), '发送按钮对比度回归');
          tester.view.viewInsets = const FakeViewPadding(bottom: 720);
          await tester.pumpAndSettle();
        }

        expect(tester.getSize(_send), const Size(48, 48));
        final sample = await _captureAndSample(
          tester,
          '${enabled ? 'enabled' : 'disabled'}-text$scale',
        );
        // Sample the actual painted surface beside the arrow, not style inputs.
        if (enabled) {
          final contrast = 1.05 / (sample.computeLuminance() + 0.05);
          expect(contrast, greaterThanOrEqualTo(4.5));
        } else {
          expect(sample, const Color(0xFFE7E4F2));
        }

        final material = tester.widget<Material>(
          find.descendant(of: _send, matching: find.byType(Material)),
        );
        expect(material.color, Colors.transparent);
        expect(material.shape, isA<CircleBorder>());
        final arrow = find.descendant(
          of: _send,
          matching: find.byIcon(Icons.arrow_upward_rounded),
        );
        expect(
          IconTheme.of(tester.element(arrow)).color,
          enabled ? Colors.white : SocialColors.textTertiary,
        );
        final data = tester.getSemantics(_send).getSemanticsData();
        expect(data.tooltip, '发送消息');
        expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(data.hasFlag(ui.SemanticsFlag.isEnabled), enabled);
        expect(data.hasAction(ui.SemanticsAction.tap), enabled);

        if (enabled) {
          final ink = tester.widget<InkWell>(
            find.descendant(of: _send, matching: find.byType(InkWell)),
          );
          expect(ink.enableFeedback, isTrue);
          expect(
            ink.overlayColor!.resolve({WidgetState.pressed})!.a,
            greaterThan(0),
          );
          await tester.tap(_send.hitTestable());
          await tester.pump();
          expect(repository.sent, <String>['发送按钮对比度回归']);
          expect(tester.widget<IconButton>(_send).onPressed, isNull);
          expect(
            find.descendant(
              of: _send,
              matching: find.byType(CircularProgressIndicator),
            ),
            findsOneWidget,
          );
          repository.receipt.complete(
            ChatMessage(
              id: 'contrast-message',
              conversationId: 'contrast-conversation',
              senderUserId: 10001,
              senderName: '我',
              content: repository.sent.single,
              createdAt: DateTime(2026, 9, 23),
              isMine: true,
              status: ChatMessageStatus.storedPendingDelivery,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.widget<IconButton>(_send).onPressed, isNotNull);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            isEmpty,
          );
          expect(find.text('发送按钮对比度回归'), findsOneWidget);
        } else {
          expect(tester.widget<IconButton>(_send).onPressed, isNull);
          await tester.tap(_send);
          await tester.pump();
          expect(repository.sent, isEmpty);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<Color> _captureAndSample(WidgetTester tester, String name) async {
  final rect = tester.getRect(_send);
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final x = (rect.left + 10).floor();
      final y = (rect.top + 24).floor();
      final offset = (y * image.width + x) * 4;
      final sample = Color.fromARGB(
        raw.getUint8(offset + 3),
        raw.getUint8(offset),
        raw.getUint8(offset + 1),
        raw.getUint8(offset + 2),
      );
      const directory = String.fromEnvironment(
        'CHAT_SEND_CONTRAST_EVIDENCE_DIR',
      );
      if (directory.isNotEmpty) {
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '$directory/$name.png',
        ).writeAsBytes(png.buffer.asUint8List());
      }
      debugPrint(
        '$name: painted=${sample.toARGB32().toRadixString(16)} whiteContrast=${(1.05 / (sample.computeLuminance() + 0.05)).toStringAsFixed(2)}',
      );
      return sample;
    } finally {
      image.dispose();
    }
  }))!;
}

class _SendRepository extends MockMessageRepository {
  _SendRepository(this.enabled);
  final bool enabled;
  final List<String> sent = [];
  final receipt = Completer<ChatMessage>();

  @override
  bool get supportsPrivateSend => enabled;
  @override
  bool get supportsPrivateRealtime => false;
  @override
  Future<ChatMessage> sendPrivateMessage({
    required ConversationSummary conversation,
    required String content,
    String? requestId,
  }) {
    sent.add(content);
    return receipt.future;
  }
}
