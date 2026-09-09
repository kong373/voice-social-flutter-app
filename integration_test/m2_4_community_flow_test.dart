import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voice_social_app/features/community/domain/community_models.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';

import 'm2_4_test_support.dart';

const bool _qaCriticalOnly = bool.fromEnvironment('QA_CRITICAL_ONLY');

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'FLOW-009 publishes, likes, comments, replies, reopens, and deletes an own dynamic',
    (WidgetTester tester) async {
      const String postContent = 'FLOW-009 模拟器文字动态：记录今天真实发生的一件小事。';
      const String commentContent = 'FLOW-009 第一条真实评论';
      const String replyContent = 'FLOW-009 对评论的明确回复';

      await launchAndAuthenticate(tester);

      // Enter through the ordinary root navigation. Pumping DiscoveryFeedPage
      // directly would bypass the real user route that this flow accepts.
      await tester.tap(find.text('发现').last);
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryFeedPage), findsOneWidget);
      expect(find.text('发现'), findsWidgets);

      await tester.tap(find.byTooltip('发布动态'));
      await tester.pumpAndSettle();
      expect(find.byType(PublishDynamicPage), findsOneWidget);
      expect(find.text('发布动态'), findsWidgets);
      final Finder imageStorageBoundary = find.text(
        '图片对象存储尚未接入，本阶段只发布真实文字内容，不生成占位图片。',
      );
      await tester.scrollUntilVisible(
        imageStorageBoundary,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(imageStorageBoundary, findsOneWidget);

      // PublishDynamicPage has one form-owned body editor; its two optional
      // metadata editors are plain TextFields. Assert the visible hint as a
      // separate contract because TextFormField does not expose decoration.
      final Finder publishContentField = find.byType(TextFormField);
      expect(publishContentField, findsOneWidget);
      expect(find.text('分享此刻真实发生的事…'), findsOneWidget);
      await tester.enterText(publishContentField, postContent);
      expect(find.text(postContent), findsOneWidget);

      // Use the ordinary app-bar submission action and verify that the route
      // returns the newly-created repository object to the feed.
      await tester.tap(find.widgetWithText(TextButton, '发布'));
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryFeedPage), findsOneWidget);
      expect(find.text(postContent), findsOneWidget);

      final Finder postCard = _postCard(postContent);
      expect(postCard, findsOneWidget);
      final Finder likeAction = find.descendant(
        of: postCard,
        matching: find.byIcon(Icons.favorite_border_rounded),
      );
      expect(likeAction, findsOneWidget);
      await tester.tap(likeAction);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: postCard,
          matching: find.byIcon(Icons.favorite_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: postCard, matching: find.text('1')),
        findsOneWidget,
      );

      final Finder commentAction = find.descendant(
        of: postCard,
        matching: find.byIcon(Icons.chat_bubble_outline_rounded),
      );
      expect(commentAction, findsOneWidget);
      await tester.tap(commentAction);
      await tester.pumpAndSettle();
      expect(find.byType(DynamicDetailPage), findsOneWidget);
      expect(find.text('动态详情'), findsOneWidget);
      expect(find.text(postContent), findsOneWidget);
      expect(find.text('评论 0'), findsOneWidget);
      expect(find.byTooltip('删除动态'), findsOneWidget);

      final Finder commentField = _detailCommentField('说点真实的想法…');
      expect(commentField, findsOneWidget);
      await tester.enterText(commentField, commentContent);
      await tester.tap(find.byTooltip('发送评论'));
      await tester.pumpAndSettle();
      _dismissKeyboard();
      await tester.pumpAndSettle();
      expect(find.text(commentContent), findsOneWidget);
      expect(find.text('评论 1'), findsOneWidget);

      await tester.ensureVisible(find.text(commentContent));
      await tester.tap(find.text(commentContent));
      await tester.pumpAndSettle();
      expect(find.byTooltip('取消回复'), findsOneWidget);

      final Finder replyField = _detailCommentField('回复 我');
      expect(replyField, findsOneWidget);
      await tester.enterText(replyField, replyContent);
      await tester.tap(find.byTooltip('发送评论'));
      await tester.pumpAndSettle();
      _dismissKeyboard();
      await tester.pumpAndSettle();
      expect(find.text('回复 我：$replyContent'), findsOneWidget);
      expect(find.text('评论 2'), findsOneWidget);

      // Leave and enter the detail again through the feed. This proves that
      // comments and replies came from repository state, not transient text.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(DiscoveryFeedPage), findsOneWidget);
      expect(postCard, findsOneWidget);
      expect(
        find.descendant(of: postCard, matching: find.text('2')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: postCard,
          matching: find.byIcon(Icons.chat_bubble_outline_rounded),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DynamicDetailPage), findsOneWidget);
      expect(find.text(commentContent), findsOneWidget);
      expect(find.text('回复 我：$replyContent'), findsOneWidget);
      expect(find.text('评论 2'), findsOneWidget);

      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-009-own-dynamic-comment-reply-detail-$qaAvdId',
      );

      await tester.tap(find.byTooltip('删除动态'));
      await tester.pumpAndSettle();
      expect(find.text('删除动态？'), findsOneWidget);
      expect(find.text('删除后正文和评论入口将不可恢复。'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
      await tester.pumpAndSettle();

      expect(find.byType(DiscoveryFeedPage), findsOneWidget);
      expect(find.text(postContent), findsNothing);
      expect(_postCard(postContent), findsNothing);
      expect(find.byType(DynamicDetailPage), findsNothing);
    },
    skip: _qaCriticalOnly,
  );

  testWidgets('FLOW-014 completes retained guild governance and attribution', (
    WidgetTester tester,
  ) async {
    final dependencies = await launchAndAuthenticate(tester);
    final repository = dependencies.communityRepository;

    // Enter every surface through the real root navigation and the Discovery
    // action. All following routes retain this one repository instance.
    await tester.tap(find.text('发现').last);
    await tester.pumpAndSettle();
    expect(find.byType(DiscoveryFeedPage), findsOneWidget);
    await tester.tap(find.byTooltip('社交经营'));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityHubPage), findsOneWidget);
    expect(find.text('社交经营'), findsOneWidget);

    // Current-guild daily sign-in is server-authoritative and becomes a
    // disabled repeat action after the repository refreshes the detail.
    await _openCommunityEntry(tester, '公会主页', GuildHomePage);
    await _scrollToText(tester, '晚风陪伴社');
    await tester.tap(find.text('晚风陪伴社'));
    await tester.pumpAndSettle();
    expect(find.byType(GuildDetailPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(GuildHomePage), findsOneWidget);

    // Submit an application to a recommended guild and assert both the
    // durable pending bit and the disabled repeat control.
    await _scrollToText(tester, '松弛生活局');
    await tester.tap(find.text('松弛生活局'));
    await tester.pumpAndSettle();
    expect(find.byType(GuildDetailPage), findsOneWidget);
    expect(find.text('申请加入'), findsOneWidget);
    await tester.tap(find.text('申请加入'));
    await tester.pumpAndSettle();
    expect(find.text('申请审核中'), findsOneWidget);
    final Finder pendingApplicationButton = find.widgetWithText(
      FilledButton,
      '申请审核中',
    );
    expect(
      tester.widget<FilledButton>(pendingApplicationButton).onPressed,
      isNull,
      reason: '已提交的入会申请必须阻止重复提交',
    );
    final GuildSummary pendingGuild = await _repositoryRead(
      tester,
      () => repository.fetchGuild('guild-2'),
    );
    expect(pendingGuild.applicationPending, isTrue);
    expect(pendingGuild.joined, isFalse);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(GuildHomePage), findsOneWidget);
    await _returnToCommunityHub(tester);

    // Review two independent applications so accept and reject are both
    // exercised. Then govern exact member records through scoped menus.
    await _openCommunityEntry(tester, '公会加入与主播管理', GuildMembersEntryPage);
    expect(find.byType(GuildMembersPage), findsOneWidget);
    expect(find.text('申请 2'), findsOneWidget);
    await tester.tap(find.text('申请 2'));
    await tester.pumpAndSettle();

    final Finder qingHeApplication = _listTileForText('青禾');
    expect(qingHeApplication, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: qingHeApplication,
        matching: find.widgetWithText(FilledButton, '通过'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('申请 1'), findsOneWidget);
    expect(find.text('青禾'), findsNothing);
    List<GuildMember> members = await _repositoryRead(
      tester,
      () => repository.fetchGuildMembers('guild-1'),
    );
    expect(
      members.where((GuildMember member) => member.userId == 20007),
      hasLength(1),
    );

    final Finder miShengApplication = _listTileForText('弥生');
    expect(miShengApplication, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: miShengApplication,
        matching: find.widgetWithText(TextButton, '拒绝'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前没有待处理的入会申请。'), findsOneWidget);
    final List<GuildApplication> remainingApplications = await _repositoryRead(
      tester,
      () => repository.fetchGuildApplications('guild-1'),
    );
    expect(remainingApplications, isEmpty);
    members = await _repositoryRead(
      tester,
      () => repository.fetchGuildMembers('guild-1'),
    );
    expect(
      members.where((GuildMember member) => member.userId == 20008),
      isEmpty,
      reason: '拒绝申请不得新增成员',
    );

    await tester.tap(find.text('主播'));
    await tester.pumpAndSettle();
    await _scrollToText(tester, '青禾');
    expect(_listTileForText('青禾'), findsOneWidget);

    final Finder ownerTile = _listTileForText('我');
    expect(ownerTile, findsOneWidget);
    expect(
      find.descendant(
        of: ownerTile,
        matching: find.byType(PopupMenuButton<String>),
      ),
      findsNothing,
      reason: '会长不得出现禁言或移出操作',
    );

    await _scrollToText(tester, '南风');
    final Finder nanFengTile = _listTileForText('南风');
    await _openMemberMenu(tester, nanFengTile);
    await tester.tap(find.text('禁言主播'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: nanFengTile, matching: find.text('已禁言')),
      findsOneWidget,
    );
    members = await _repositoryRead(
      tester,
      () => repository.fetchGuildMembers('guild-1'),
    );
    expect(
      members
          .singleWhere((GuildMember member) => member.recordId == 'member-3')
          .isMuted,
      isTrue,
    );

    await _openMemberMenu(tester, nanFengTile);
    await tester.tap(find.text('解除禁言'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: nanFengTile, matching: find.text('已禁言')),
      findsNothing,
    );
    members = await _repositoryRead(
      tester,
      () => repository.fetchGuildMembers('guild-1'),
    );
    expect(
      members
          .singleWhere((GuildMember member) => member.recordId == 'member-3')
          .isMuted,
      isFalse,
    );

    await _scrollToText(tester, '小满');
    final Finder xiaoManTile = _listTileForText('小满');
    await _openMemberMenu(tester, xiaoManTile);
    await tester.tap(find.text('移出公会'));
    await tester.pumpAndSettle();
    expect(find.text('移出 小满？'), findsOneWidget);
    expect(find.text('移出后，该用户的公会身份和相关权限会立即失效。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确认移出'));
    await tester.pumpAndSettle();
    expect(find.text('小满'), findsNothing);
    members = await _repositoryRead(
      tester,
      () => repository.fetchGuildMembers('guild-1'),
    );
    expect(
      members.where((GuildMember member) => member.recordId == 'member-4'),
      isEmpty,
    );

    await captureQaScreenshot(
      tester,
      binding,
      'FLOW-014-guild-application-governance-$qaAvdId',
    );
    await _returnToCommunityHub(tester);

    // Verify immutable invite attribution before entering bilateral CP
    // operations. This page intentionally exposes no client rewrite action.
    await _openCommunityEntry(tester, '邀请与渠道归属', InviteAttributionPage);
    expect(find.text('MELO8K2Q'), findsOneWidget);
    expect(find.text('官方自然邀请'), findsOneWidget);
    expect(find.text('归属由服务端记录，客户端不能自行修改。'), findsOneWidget);
    final InviteAttribution attribution = await _repositoryRead(
      tester,
      repository.fetchInviteAttribution,
    );
    expect(attribution.inviteCode, 'MELO8K2Q');
    expect(attribution.invitedUsers, 7);
    expect(find.byType(TextField), findsNothing);
    await _returnToCommunityHub(tester);

    for (final label in ['CP 关系', '守护与粉团', '任务与签到', '主题活动中心']) {
      expect(find.text(label), findsNothing);
    }
  });
}

Finder _postCard(String content) => find.ancestor(
  of: find.text(content),
  matching: find.byType(DynamicPostCard),
);

Finder _detailCommentField(String hintText) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is TextField && widget.decoration?.hintText == hintText,
  description: 'dynamic detail comment field with hint "$hintText"',
);

Finder _listTileForText(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(ListTile));

Future<void> _openCommunityEntry(
  WidgetTester tester,
  String title,
  Type pageType,
) async {
  expect(find.byType(CommunityHubPage), findsOneWidget);
  await _scrollToText(tester, title);
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  expect(find.byType(pageType), findsOneWidget, reason: title);
}

Future<void> _returnToCommunityHub(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  expect(find.byType(CommunityHubPage), findsOneWidget);
}

Future<void> _scrollToText(WidgetTester tester, String text) async {
  final Finder target = find.text(text);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      220,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(target.first);
  }
  await tester.pumpAndSettle();
  expect(target, findsWidgets, reason: text);
}

Future<void> _openMemberMenu(WidgetTester tester, Finder memberTile) async {
  final Finder menu = find.descendant(
    of: memberTile,
    matching: find.byType(PopupMenuButton<String>),
  );
  expect(menu, findsOneWidget);
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

Future<T> _repositoryRead<T>(
  WidgetTester tester,
  Future<T> Function() read,
) async {
  final T? result = await tester.runAsync<T>(read);
  if (result == null) {
    throw TestFailure('Repository read returned null for $T');
  }
  return result;
}

void _dismissKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
}
