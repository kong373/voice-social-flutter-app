import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';

void main() {
  const List<_Viewport> viewports = <_Viewport>[
    _Viewport('390x844', Size(390, 844), 1),
    _Viewport('360x800', Size(360, 800), 1),
    _Viewport('360x800 at 1.3x', Size(360, 800), 1.3),
    _Viewport('390x844 at 1.3x', Size(390, 844), 1.3),
  ];
  for (final _Viewport viewport in viewports) {
    for (final _CommunityTestPage entry in _communityPages) {
      testWidgets('${entry.id} fits ${viewport.label}', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = viewport.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final AppDependencies dependencies = await createQaDependencies();
        await tester.pumpWidget(
          AppDependencyScope(
            dependencies: dependencies,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.social(),
              builder: (BuildContext context, Widget? child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(viewport.textScale)),
                child: child!,
              ),
              home: entry.builder(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: entry.id);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 200));
      });
    }
  }
}

const List<_CommunityTestPage> _communityPages = <_CommunityTestPage>[
  _CommunityTestPage('SC-HUB', CommunityHubPage.new),
  _CommunityTestPage('SC-001', GuildHomePage.new),
  _CommunityTestPage('SC-002', GuildMembersEntryPage.new),
  _CommunityTestPage('SC-003', InviteAttributionPage.new),
  _CommunityTestPage('SC-004', CpRelationPage.new),
  _CommunityTestPage('SC-005', GuardianFanPage.new),
  _CommunityTestPage('SC-006', TaskCheckInPage.new),
  _CommunityTestPage('SC-007', ActivityCenterPage.new),
];

class _CommunityTestPage {
  const _CommunityTestPage(this.id, this.builder);

  final String id;
  final Widget Function() builder;
}

class _Viewport {
  const _Viewport(this.label, this.size, this.textScale);

  final String label;
  final Size size;
  final double textScale;
}
