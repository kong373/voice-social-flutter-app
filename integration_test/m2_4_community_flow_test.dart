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

  testWidgets(
    'FLOW-014 completes guild governance, CP, guardian, task, and activity state',
    (WidgetTester tester) async {
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
      expect(find.text('社交经营与活动'), findsOneWidget);

      // Current-guild daily sign-in is server-authoritative and becomes a
      // disabled repeat action after the repository refreshes the detail.
      await _openCommunityEntry(tester, '公会主页', GuildHomePage);
      await _scrollToText(tester, '晚风陪伴社');
      await tester.tap(find.text('晚风陪伴社'));
      await tester.pumpAndSettle();
      expect(find.byType(GuildDetailPage), findsOneWidget);
      expect(find.text('公会签到'), findsOneWidget);
      await tester.tap(find.text('公会签到'));
      await tester.pumpAndSettle();
      expect(find.text('今日已签到'), findsOneWidget);
      final Finder signedGuildButton = find.widgetWithText(
        FilledButton,
        '今日已签到',
      );
      expect(
        tester.widget<FilledButton>(signedGuildButton).onPressed,
        isNull,
        reason: '公会签到不得重复提交',
      );
      final GuildSummary signedGuild = await _repositoryRead(
        tester,
        () => repository.fetchGuild('guild-1'),
      );
      expect(signedGuild.hasSignedToday, isTrue);

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
      await _openCommunityEntry(tester, '公会加入与成员管理', GuildMembersEntryPage);
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
      final List<GuildApplication> remainingApplications =
          await _repositoryRead(
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

      await tester.tap(find.text('成员'));
      await tester.pumpAndSettle();
      await _scrollToText(tester, '青禾');
      expect(_listTileForText('青禾'), findsOneWidget);

      final Finder ownerTile = _listTileForText('晚星');
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
      await tester.tap(find.text('禁言成员'));
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

      // An existing relation must reject another invitation. A valid outgoing
      // invitation is then sent through UI and checked for repeat eligibility.
      await _openCommunityEntry(tester, 'CP 关系', CpRelationPage);
      final Finder cpUserField = _textFieldWithLabel('对方用户 ID');
      expect(cpUserField, findsOneWidget);
      await tester.enterText(cpUserField, '20009');
      await tester.tap(find.widgetWithText(FilledButton, '邀请'));
      await tester.pumpAndSettle();
      expect(find.text('已经与该用户建立 CP 关系'), findsOneWidget);
      await _hideCurrentSnackBar(tester, CpRelationPage);

      await tester.enterText(cpUserField, '20011');
      await tester.tap(find.widgetWithText(FilledButton, '邀请'));
      await tester.pumpAndSettle();
      expect(find.text('CP 邀请已发送，等待对方确认'), findsOneWidget);
      final CpEligibility repeatedOutgoingEligibility = await _repositoryRead(
        tester,
        () => repository.checkCpEligibility(20011),
      );
      expect(repeatedOutgoingEligibility.allowed, isFalse);
      expect(repeatedOutgoingEligibility.message, '已向该用户发送 CP 邀请，请等待对方确认');
      await _hideCurrentSnackBar(tester, CpRelationPage);
      await tester.enterText(cpUserField, '20011');
      await tester.tap(find.widgetWithText(FilledButton, '邀请'));
      await tester.pumpAndSettle();
      expect(find.text('已向该用户发送 CP 邀请，请等待对方确认'), findsOneWidget);
      expect(find.text('CP 邀请已发送，等待对方确认'), findsNothing);
      _dismissKeyboard();
      await _hideCurrentSnackBar(tester, CpRelationPage);

      final List<CpInvitation> initialCpInvitations = await _repositoryRead(
        tester,
        repository.fetchPendingCpInvitations,
      );
      expect(initialCpInvitations, hasLength(2));
      expect(
        initialCpInvitations.map(
          (CpInvitation invitation) => invitation.nickname,
        ),
        <String>['白露', '星遥'],
      );
      await _scrollToText(tester, '白露');
      final Finder baiLuInvitation = _listTileForText('白露');
      expect(
        find.descendant(
          of: baiLuInvitation,
          matching: find.widgetWithText(TextButton, '拒绝'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: baiLuInvitation,
          matching: find.widgetWithText(FilledButton, '接受'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: baiLuInvitation,
          matching: find.widgetWithText(FilledButton, '接受'),
        ),
      );
      await tester.pumpAndSettle();
      List<CpInvitation> pendingCpInvitations = await _repositoryRead(
        tester,
        repository.fetchPendingCpInvitations,
      );
      List<CpRelation> cpRelations = await _repositoryRead(
        tester,
        repository.fetchCpRelations,
      );
      expect(pendingCpInvitations, hasLength(1));
      expect(pendingCpInvitations.single.nickname, '星遥');
      final CpRelation acceptedRelation = cpRelations.singleWhere(
        (CpRelation relation) => relation.userId == 20010,
      );
      expect(acceptedRelation.nickname, '白露');
      expect(acceptedRelation.days, 1);
      expect(acceptedRelation.boundAt, '今天');
      expect(find.text('已相伴 1 天 · 今天'), findsOneWidget);

      // Reject the independent invitation and prove that it disappears
      // without creating a relationship.
      final int relationCountBeforeReject = cpRelations.length;
      await _scrollToText(tester, '星遥');
      final Finder xingYaoInvitation = _listTileForText('星遥');
      expect(
        find.descendant(
          of: xingYaoInvitation,
          matching: find.widgetWithText(TextButton, '拒绝'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: xingYaoInvitation,
          matching: find.widgetWithText(TextButton, '拒绝'),
        ),
      );
      await tester.pumpAndSettle();
      pendingCpInvitations = await _repositoryRead(
        tester,
        repository.fetchPendingCpInvitations,
      );
      cpRelations = await _repositoryRead(tester, repository.fetchCpRelations);
      expect(pendingCpInvitations, isEmpty);
      expect(cpRelations, hasLength(relationCountBeforeReject));
      expect(
        cpRelations.where((CpRelation relation) => relation.userId == 20012),
        isEmpty,
        reason: '拒绝星遥不得建立 CP 关系',
      );
      expect(find.text('星遥'), findsNothing);
      expect(find.text('当前没有待处理邀请。'), findsOneWidget);

      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-014-cp-authoritative-state-$qaAvdId',
      );
      await _returnToCommunityHub(tester);

      // Use a fresh anchor in the same repository so both guard purchase and
      // first-time fan-team join are real state transitions rather than smoke.
      await _openCommunityEntry(tester, '守护与粉团', GuardianFanPage);
      final Finder anchorField = _textFieldWithLabel('主播用户 ID');
      await tester.enterText(anchorField, '20011');
      await tester.tap(find.widgetWithText(FilledButton, '查询'));
      await tester.pumpAndSettle();
      _dismissKeyboard();
      expect(find.text('用户 20011'), findsOneWidget);
      expect(find.text('当前未开通守护'), findsOneWidget);

      await _scrollToText(tester, '七日守护');
      final Finder sevenDayGuardian = _listTileForText('七日守护');
      await tester.tap(
        find.descendant(
          of: sevenDayGuardian,
          matching: find.widgetWithText(FilledButton, '开通'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('开通七日守护？'), findsOneWidget);
      expect(find.text('将按服务端规则扣除 660 礼物币，守护 用户 20011 7 天。'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认开通'));
      await tester.pumpAndSettle();
      GuardianFanSnapshot guardian = await _repositoryRead(
        tester,
        () => repository.fetchGuardianFan(20011),
      );
      expect(guardian.currentGuardianLevel?.id, 'guard-7');
      expect(guardian.currentGuardianLevel?.durationDays, 7);

      await _scrollToText(tester, '加入粉团');
      await tester.tap(find.widgetWithText(FilledButton, '加入粉团'));
      await tester.pumpAndSettle();
      expect(find.text('已加入'), findsOneWidget);
      expect(find.text('粉团等级 1 · 亲密值 10'), findsOneWidget);
      final Finder joinedFansButton = find.widgetWithText(FilledButton, '已加入');
      expect(
        tester.widget<FilledButton>(joinedFansButton).onPressed,
        isNull,
        reason: '加入粉团后必须阻止重复加入',
      );
      guardian = await _repositoryRead(
        tester,
        () => repository.fetchGuardianFan(20011),
      );
      expect(guardian.joinedFansTeam, isTrue);
      expect(guardian.fansLevel, 1);
      expect(guardian.intimacy, 10);

      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-014-guardian-fans-authoritative-state-$qaAvdId',
      );
      await _returnToCommunityHub(tester);

      // Platform check-in and claim use returned snapshots, then replace their
      // actions with disabled/claimed states to stop duplicate rewards.
      await _openCommunityEntry(tester, '任务与签到', TaskCheckInPage);
      expect(find.text('连续签到 3 天'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '签到'));
      await tester.pumpAndSettle();
      expect(find.text('连续签到 4 天'), findsOneWidget);
      expect(find.text('今天已经签到'), findsOneWidget);
      final Finder signedTaskButton = find.widgetWithText(FilledButton, '已签到');
      expect(
        tester.widget<FilledButton>(signedTaskButton).onPressed,
        isNull,
        reason: '每日签到不得重复领取',
      );
      TaskCenterSnapshot taskCenter = await _repositoryRead(
        tester,
        repository.fetchTaskCenter,
      );
      expect(taskCenter.signedToday, isTrue);
      expect(taskCenter.continuousDays, 4);
      expect(
        taskCenter.checkInDays
            .singleWhere((CheckInDay day) => day.today)
            .completed,
        isTrue,
      );

      await _scrollToText(tester, '进入一个正在发生的语音房');
      final Finder claimableTask = _listTileForText('进入一个正在发生的语音房');
      final Finder claimButton = find.descendant(
        of: claimableTask,
        matching: find.widgetWithText(FilledButton, '领取'),
      );
      expect(claimButton, findsOneWidget);
      await tester.tap(claimButton);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: claimableTask, matching: find.text('已领取')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: claimableTask,
          matching: find.widgetWithText(FilledButton, '领取'),
        ),
        findsNothing,
        reason: '任务领取后不得保留重复领取按钮',
      );
      taskCenter = await _repositoryRead(tester, repository.fetchTaskCenter);
      expect(
        taskCenter.tasks
            .singleWhere((TaskItem task) => task.id == 'task-1')
            .state,
        TaskState.claimed,
      );

      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-014-check-in-task-claimed-$qaAvdId',
      );
      await _returnToCommunityHub(tester);

      // Finish at the service-backed activity catalog and verify both status
      // variants, rules, and the real room route offered by the active item.
      await _openCommunityEntry(tester, '主题活动中心', ActivityCenterPage);
      final List<ThemeActivity> activities = await _repositoryRead(
        tester,
        repository.fetchActivities,
      );
      expect(activities, hasLength(2));
      expect(activities[0].status, ThemeActivityStatus.active);
      expect(activities[0].routeTarget, '880217');
      expect(activities[1].status, ThemeActivityStatus.upcoming);
      await _scrollToText(tester, '周末陪伴主题房');
      expect(find.text('进行中'), findsOneWidget);
      expect(find.text('有效房间入口直接进入语音房'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '进入活动房间'), findsOneWidget);
      await _scrollToText(tester, '城市夜谈计划');
      expect(find.text('即将开始'), findsOneWidget);
      expect(find.text('不提供基于位置或偶遇的推荐'), findsOneWidget);
      expectNoRetiredFeatureText(reason: 'FLOW-014 activity catalog');

      await captureQaScreenshot(
        tester,
        binding,
        'FLOW-014-authoritative-activity-catalog-$qaAvdId',
      );
    },
  );
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

Finder _textFieldWithLabel(String labelText) => find.byWidgetPredicate(
  (Widget widget) =>
      widget is TextField && widget.decoration?.labelText == labelText,
  description: 'text field with label "$labelText"',
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

Future<void> _hideCurrentSnackBar(WidgetTester tester, Type pageType) async {
  ScaffoldMessenger.of(
    tester.element(find.byType(pageType)),
  ).hideCurrentSnackBar();
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
