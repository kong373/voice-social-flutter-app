import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';
import 'support/golden_font_gate.dart';

void main() {
  setUpAll(loadGoldenFonts);
  for (final isFeedback in [false, true]) {
    for (final size in const [Size(375, 667), Size(390, 844), Size(402, 874)]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          '${isFeedback ? 'feedback' : 'report'} keeps draft and visible editor across keyboard $size $scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final dependencies = AppDependencies.mock();
            final inset = ValueNotifier<double>(0);
            addTearDown(dependencies.dispose);
            addTearDown(inset.dispose);
            await tester.pumpWidget(
              AppDependencyScope(
                dependencies: dependencies,
                child: MaterialApp(
                  theme: AppTheme.social(fontFamily: kGoldenFontFamily),
                  builder: (context, child) => ValueListenableBuilder<double>(
                    valueListenable: inset,
                    builder: (context, bottom, _) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        viewInsets: EdgeInsets.only(bottom: bottom),
                        disableAnimations: true,
                      ),
                      child: child!,
                    ),
                  ),
                  home: isFeedback
                      ? const HelpCenterPage()
                      : const ReportPage(
                          targetType: ReportTargetType.user,
                          targetId: '20001',
                          targetName: 'Test',
                        ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            for (
              var frame = 0;
              frame < 50 &&
                  find.byType(EditableText).evaluate().length <
                      (isFeedback ? 2 : 1);
              frame++
            ) {
              await tester.pump(const Duration(milliseconds: 35));
            }
            expect(
              find.byType(EditableText),
              isFeedback ? findsNWidgets(2) : findsOneWidget,
            );
            final field = find.byType(EditableText).last;
            const draft = 'Draft remains unchanged when the keyboard appears.';
            await tester.enterText(field, draft);
            inset.value = 280;
            await tester.pumpAndSettle();
            final input = field;
            expect(
              tester.getRect(input).bottom,
              lessThanOrEqualTo(size.height - 280 + 1),
            );
            expect(tester.widget<EditableText>(field).controller.text, draft);
            expect(
              tester.widget<EditableText>(input).minLines,
              isFeedback || size.height < 700 ? 2 : 5,
            );
            inset.value = 0;
            await tester.pumpAndSettle();
            expect(tester.widget<EditableText>(input).minLines, 5);
            expect(tester.widget<EditableText>(field).controller.text, draft);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
