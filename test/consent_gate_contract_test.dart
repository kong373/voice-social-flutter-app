import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/storage/key_value_store.dart';
import 'package:voice_social_app/features/account/data/auth_session_manager.dart';
import 'package:voice_social_app/features/account/presentation/consent_page.dart';

void main() {
  test('consent acceptance is bound to the app-owned version', () async {
    final AuthSessionManager oldManager = AuthSessionManager(
      MemoryKeyValueStore(<String, String>{
        AuthSessionManager.consentStorageKey: 'accepted',
      }),
    );
    expect(await oldManager.hasAcceptedConsent(), isFalse);

    final AuthSessionManager manager = AuthSessionManager(
      MemoryKeyValueStore(),
    );
    await manager.acceptConsent();
    expect(await manager.hasAcceptedConsent(), isTrue);
    expect(
      AuthSessionManager.consentStorageValue,
      'accepted:${AuthSessionManager.consentVersion}',
    );
  });

  testWidgets('consent gate requires the end of the document and a check', (
    WidgetTester tester,
  ) async {
    var accepted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ConsentPage(
          onAccept: () async {
            accepted = true;
          },
        ),
      ),
    );

    expect(find.textContaining('App-owned v1'), findsWidgets);
    await tester.tap(find.byKey(const Key('consent-submit')));
    expect(accepted, isFalse);

    await tester.drag(
      find.byKey(const Key('consent-scroll')),
      const Offset(0, -1600),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('consent-agreement-checkbox')),
    );
    final Finder checkbox = find.descendant(
      of: find.byKey(const Key('consent-agreement-checkbox')),
      matching: find.byType(Checkbox),
    );
    await tester.tap(checkbox);
    await tester.pump();
    await tester.tap(find.byKey(const Key('consent-submit')));
    await tester.pump();

    expect(accepted, isTrue);
  });

  testWidgets('consent save failure remains visible and does not advance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ConsentPage(
          onAccept: () async => throw StateError('store unavailable'),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const Key('consent-scroll')),
      const Offset(0, -1600),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('consent-agreement-checkbox')),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('consent-agreement-checkbox')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('consent-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('consent-error')), findsOneWidget);
    expect(find.text('手机号登录'), findsNothing);
  });
}
