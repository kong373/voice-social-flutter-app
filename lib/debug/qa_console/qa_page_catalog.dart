import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_gate.dart';
import 'package:voice_social_app/app/page_manifest.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';
import 'package:voice_social_app/debug/qa_console/qa_models.dart';
import 'package:voice_social_app/features/account/compliance/presentation/account_status_pages.dart';
import 'package:voice_social_app/features/account/compliance/presentation/system_permission_pages.dart';
import 'package:voice_social_app/features/account/presentation/consent_page.dart';
import 'package:voice_social_app/features/account/presentation/login_page.dart';
import 'package:voice_social_app/features/account/presentation/registration_page.dart';
import 'package:voice_social_app/features/account/presentation/third_party_authorization_page.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';
import 'package:voice_social_app/features/discovery/home_page.dart';
import 'package:voice_social_app/features/discovery/presentation/global_search_page.dart';
import 'package:voice_social_app/features/discovery/presentation/saved_rooms_page.dart';
import 'package:voice_social_app/features/discovery/presentation/search_results_page.dart';
import 'package:voice_social_app/features/message/presentation/message_pages.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';
import 'package:voice_social_app/features/room/presentation/create_room_page.dart';
import 'package:voice_social_app/features/room/presentation/edit_room_page.dart';
import 'package:voice_social_app/features/room/presentation/room_audio_page.dart';
import 'package:voice_social_app/features/room/presentation/room_deep_link_page.dart';
import 'package:voice_social_app/features/room/presentation/room_diagnostics_page.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';
import 'package:voice_social_app/features/room/presentation/room_members_page.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';
import 'package:voice_social_app/features/room/presentation/room_recovery_page.dart';
import 'package:voice_social_app/features/room/presentation/room_share_page.dart';
import 'package:voice_social_app/features/room/presentation/room_topic_page.dart';
import 'package:voice_social_app/features/social/domain/social_models.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

const List<QaPageState> _formStates = <QaPageState>[
  QaPageState.normal,
  QaPageState.permissionDenied,
  QaPageState.submitting,
  QaPageState.error,
];

const List<QaPageState> _repositoryStates = <QaPageState>[
  QaPageState.normal,
  QaPageState.loading,
  QaPageState.empty,
  QaPageState.error,
  QaPageState.offline,
];

final List<QaPageEntry> qaPageCatalog = <QaPageEntry>[
  QaPageEntry(
    id: 'AC-001',
    name: '启动与会话恢复',
    area: ProductArea.account,
    widgetClass: 'SessionRestorePage / AppGate',
    sourcePath: 'lib/app/app_gate.dart',
    userEntry: '应用冷启动 → 会话恢复',
    requiredStates: const <QaPageState>[
      QaPageState.loading,
      QaPageState.success,
      QaPageState.error,
    ],
    builder: (_, __) => const SessionRestorePage(),
  ),
  QaPageEntry(
    id: 'AC-002',
    name: '协议与隐私同意',
    area: ProductArea.account,
    widgetClass: 'ConsentPage',
    sourcePath: 'lib/features/account/presentation/consent_page.dart',
    userEntry: '首次启动 → 协议与隐私同意',
    builder: (_, __) => ConsentPage(onAccept: () async {}),
  ),
  QaPageEntry(
    id: 'AC-003',
    name: '手机注册登录',
    area: ProductArea.account,
    widgetClass: 'LoginPage / RegistrationPage',
    sourcePath: 'lib/features/account/presentation/',
    userEntry: '协议同意 → 手机号登录 → 注册资料',
    requiredStates: _formStates,
    builder: (AppDependencies dependencies, QaScenario scenario) =>
        scenario.state == QaPageState.success
        ? RegistrationPage(controller: dependencies.authController)
        : LoginPage(controller: dependencies.authController),
  ),
  QaPageEntry(
    id: 'AC-004',
    name: '第三方账号绑定与分享授权',
    area: ProductArea.account,
    widgetClass: 'ThirdPartyAuthorizationPage',
    sourcePath:
        'lib/features/account/presentation/third_party_authorization_page.dart',
    userEntry: '我的 → 账号与安全 → 第三方账号绑定与分享授权',
    vendorBoundary: '第三方账号及原生分享 SDK 未接入',
    builder: (_, __) => const ThirdPartyAuthorizationPage(),
  ),
  QaPageEntry(
    id: 'AC-005',
    name: '系统权限中心',
    area: ProductArea.account,
    widgetClass: 'SystemPermissionCenterPage',
    sourcePath:
        'lib/features/account/compliance/presentation/system_permission_pages.dart',
    userEntry: '我的 → 账号与安全 → 系统权限中心',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.permission,
      QaPageState.permissionDenied,
      QaPageState.unavailable,
    ],
    vendorBoundary: '第一方 Android/iOS 系统权限桥；未注册原生 host 时显示不可用',
    builder: (_, __) => const SystemPermissionCenterPage(
      account: '13800138000',
      currentVersion: 5,
      platformType: 1,
    ),
  ),
  QaPageEntry(
    id: 'AC-006',
    name: '实名认证',
    area: ProductArea.account,
    widgetClass: 'RealNamePage',
    sourcePath:
        'lib/features/account/compliance/presentation/system_permission_pages.dart',
    userEntry: '我的 → 账号与安全 → 实名认证',
    requiredStates: _formStates,
    vendorBoundary: '第一方人工审核；状态由服务端返回 PENDING/APPROVED/REJECTED',
    builder: (_, __) => const RealNamePage(
      account: '13800138000',
      currentVersion: 5,
      platformType: 1,
    ),
  ),
  QaPageEntry(
    id: 'AC-007',
    name: '登录设备与会话管理',
    area: ProductArea.account,
    widgetClass: 'DeviceSessionsPage',
    sourcePath:
        'lib/features/account/compliance/presentation/system_permission_pages.dart',
    userEntry: '我的 → 账号与安全 → 登录设备与会话',
    requiredStates: _repositoryStates,
    vendorBoundary: '原生设备会话驱动未接入',
    builder: (_, __) => const DeviceSessionsPage(
      account: '13800138000',
      currentVersion: 5,
      platformType: 1,
    ),
  ),
  QaPageEntry(
    id: 'AC-008',
    name: '账号封禁拦截',
    area: ProductArea.account,
    widgetClass: 'AccountRestrictionPage',
    sourcePath:
        'lib/features/account/compliance/presentation/account_status_pages.dart',
    userEntry: '登录/恢复会话 → 账号限制拦截；我的 → 账号状态',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.restricted,
      QaPageState.error,
    ],
    builder: (_, __) => const AccountRestrictionPage(
      account: '13800138000',
      currentVersion: 5,
      platformType: 1,
    ),
  ),
  QaPageEntry(
    id: 'AC-009',
    name: '处罚申诉',
    area: ProductArea.account,
    widgetClass: 'AccountAppealPage',
    sourcePath:
        'lib/features/account/compliance/presentation/account_status_pages.dart',
    userEntry: '我的 → 账号与安全 → 处罚申诉',
    requiredStates: _formStates,
    builder: (_, __) => const AccountAppealPage(account: '13800138000'),
  ),
  QaPageEntry(
    id: 'AC-010',
    name: '账号注销申请与进度',
    area: ProductArea.account,
    widgetClass: 'AccountCancellationPage',
    sourcePath:
        'lib/features/account/compliance/presentation/account_status_pages.dart',
    userEntry: '我的 → 账号与安全 → 账号注销',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.submitting,
      QaPageState.conflict,
      QaPageState.success,
    ],
    builder: (_, __) => const AccountCancellationPage(
      account: '13800138000',
      currentVersion: 5,
      platformType: 1,
    ),
  ),
  QaPageEntry(
    id: 'AC-011',
    name: '版本升级',
    area: ProductArea.account,
    widgetClass: 'VersionUpgradePage',
    sourcePath:
        'lib/features/account/compliance/presentation/account_status_pages.dart',
    userEntry: '我的 → 账号与安全 → 版本升级',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.success,
      QaPageState.error,
    ],
    builder: (_, __) =>
        const VersionUpgradePage(currentVersion: 5, platformType: 1),
  ),
  QaPageEntry(
    id: 'AC-012',
    name: '青少年模式',
    area: ProductArea.account,
    widgetClass: 'YouthModePage',
    sourcePath:
        'lib/features/account/compliance/presentation/account_status_pages.dart',
    userEntry: '我的 → 账号与安全 → 青少年模式',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.restricted,
      QaPageState.success,
    ],
    builder: (_, __) => const YouthModePage(
      account: '13800138000',
      currentVersion: 5,
      platformType: 1,
    ),
  ),
  QaPageEntry(
    id: 'DS-001',
    name: '首页房间发现',
    area: ProductArea.discovery,
    widgetClass: 'HomePage',
    sourcePath: 'lib/features/discovery/home_page.dart',
    userEntry: '根导航 → 首页',
    requiredStates: _repositoryStates,
    builder: (_, __) => const Scaffold(body: HomePage()),
  ),
  QaPageEntry(
    id: 'DS-002',
    name: '全局搜索',
    area: ProductArea.discovery,
    widgetClass: 'GlobalSearchPage',
    sourcePath: 'lib/features/discovery/presentation/global_search_page.dart',
    userEntry: '首页 → 搜索',
    requiredStates: _formStates,
    builder: (_, __) => const GlobalSearchPage(
      initialRecent: <String>['深夜陪伴', '880217', '南风'],
      suggestions: <String>['深夜陪伴', '音乐点唱', '轻松闲聊', '新朋友'],
    ),
  ),
  QaPageEntry(
    id: 'DS-003',
    name: '搜索结果',
    area: ProductArea.discovery,
    widgetClass: 'SearchResultsPage',
    sourcePath: 'lib/features/discovery/presentation/search_results_page.dart',
    userEntry: '全局搜索 → 提交关键词',
    requiredStates: _repositoryStates,
    builder: (_, __) => const SearchResultsPage(keyword: '深夜'),
  ),
  QaPageEntry(
    id: 'DS-004',
    name: '发现动态流',
    area: ProductArea.discovery,
    widgetClass: 'DiscoveryFeedPage',
    sourcePath:
        'lib/features/discovery/dynamic/presentation/dynamic_pages.dart',
    userEntry: '根导航 → 发现',
    requiredStates: _repositoryStates,
    builder: (_, __) => const DiscoveryFeedPage(),
  ),
  QaPageEntry(
    id: 'DS-005',
    name: '动态详情与评论',
    area: ProductArea.discovery,
    widgetClass: 'DynamicDetailPage',
    sourcePath:
        'lib/features/discovery/dynamic/presentation/dynamic_pages.dart',
    userEntry: '发现动态流 → 动态正文',
    requiredStates: _repositoryStates,
    builder: (_, __) => const DynamicDetailPage(postId: 'dynamic-1001'),
  ),
  QaPageEntry(
    id: 'DS-006',
    name: '发布动态',
    area: ProductArea.discovery,
    widgetClass: 'PublishDynamicPage',
    sourcePath:
        'lib/features/discovery/dynamic/presentation/dynamic_pages.dart',
    userEntry: '发现 → 发布动态',
    requiredStates: _formStates,
    vendorBoundary: '图片对象存储未接入；文字动态可验收',
    builder: (_, __) => const PublishDynamicPage(),
  ),
  QaPageEntry(
    id: 'DS-007',
    name: '用户与房间排行榜',
    area: ProductArea.discovery,
    widgetClass: 'RankingPage',
    sourcePath:
        'lib/features/discovery/dynamic/presentation/dynamic_pages.dart',
    userEntry: '发现 → 排行榜',
    requiredStates: _repositoryStates,
    builder: (_, __) => const RankingPage(),
  ),
  QaPageEntry(
    id: 'DS-008',
    name: '收藏与我的房间',
    area: ProductArea.discovery,
    widgetClass: 'SavedRoomsPage',
    sourcePath: 'lib/features/discovery/presentation/saved_rooms_page.dart',
    userEntry: '首页 → 收藏与我的房间',
    requiredStates: _repositoryStates,
    builder: (_, __) => const SavedRoomsPage(),
  ),
  QaPageEntry(
    id: 'US-001',
    name: '个人中心',
    area: ProductArea.social,
    widgetClass: 'PersonalCenterPage',
    sourcePath: 'lib/features/social/presentation/social_profile_pages.dart',
    userEntry: '根导航 → 我的',
    requiredStates: _repositoryStates,
    builder: (AppDependencies dependencies, _) => Scaffold(
      body: PersonalCenterPage(
        session: dependencies.sessionManager.session,
        onSignOut: () async {},
      ),
    ),
  ),
  QaPageEntry(
    id: 'US-002',
    name: '编辑个人资料',
    area: ProductArea.social,
    widgetClass: 'EditProfilePage',
    sourcePath: 'lib/features/social/presentation/social_profile_pages.dart',
    userEntry: '我的 → 编辑个人资料',
    requiredStates: _formStates,
    builder: (_, __) => const EditProfilePage(initialProfile: qaSocialProfile),
  ),
  QaPageEntry(
    id: 'US-003',
    name: '他人公开主页',
    area: ProductArea.social,
    widgetClass: 'PublicProfilePage',
    sourcePath: 'lib/features/social/presentation/social_profile_pages.dart',
    userEntry: '搜索结果/成员/榜单 → 用户',
    requiredStates: _repositoryStates,
    builder: (_, __) => const PublicProfilePage(userId: 20001),
  ),
  QaPageEntry(
    id: 'US-004',
    name: '关注、粉丝与好友列表',
    area: ProductArea.social,
    widgetClass: 'RelationsPage',
    sourcePath: 'lib/features/social/presentation/social_relation_pages.dart',
    userEntry: '我的 → 关注、粉丝与好友',
    requiredStates: _repositoryStates,
    builder: (_, __) => const RelationsPage(),
  ),
  QaPageEntry(
    id: 'US-005',
    name: '好友请求',
    area: ProductArea.social,
    widgetClass: 'FriendRequestsPage',
    sourcePath: 'lib/features/social/presentation/social_relation_pages.dart',
    userEntry: '我的 → 好友请求',
    requiredStates: _repositoryStates,
    builder: (_, __) => const FriendRequestsPage(),
  ),
  QaPageEntry(
    id: 'US-006',
    name: '访客记录',
    area: ProductArea.social,
    widgetClass: 'VisitorRecordsPage',
    sourcePath: 'lib/features/social/presentation/social_relation_pages.dart',
    userEntry: '我的 → 访客记录',
    requiredStates: _repositoryStates,
    builder: (_, __) => const VisitorRecordsPage(),
  ),
  QaPageEntry(
    id: 'US-007',
    name: '隐私与黑名单',
    area: ProductArea.social,
    widgetClass: 'PrivacyBlacklistPage',
    sourcePath: 'lib/features/social/presentation/social_relation_pages.dart',
    userEntry: '我的 → 隐私与黑名单',
    requiredStates: _repositoryStates,
    builder: (_, __) => const PrivacyBlacklistPage(),
  ),
  QaPageEntry(
    id: 'US-008',
    name: '举报用户或房间',
    area: ProductArea.social,
    widgetClass: 'ReportPage',
    sourcePath: 'lib/features/social/presentation/social_support_pages.dart',
    userEntry: '用户/房间 → 更多 → 举报',
    requiredStates: _formStates,
    vendorBoundary: '图片证据对象存储未接入；文字证据可提交',
    builder: (_, __) => const ReportPage(
      targetType: ReportTargetType.user,
      targetId: '20001',
      targetName: '晚星',
    ),
  ),
  QaPageEntry(
    id: 'US-009',
    name: '帮助与客服中心',
    area: ProductArea.social,
    widgetClass: 'HelpCenterPage',
    sourcePath: 'lib/features/social/presentation/social_support_pages.dart',
    userEntry: '我的 → 帮助与客服',
    requiredStates: _formStates,
    builder: (_, __) => const HelpCenterPage(),
  ),
  QaPageEntry(
    id: 'US-010',
    name: '工单详情与处理进度',
    area: ProductArea.social,
    widgetClass: 'SupportTicketPage',
    sourcePath: 'lib/features/social/presentation/social_support_pages.dart',
    userEntry: '帮助与客服 → 已提交工单',
    requiredStates: const <QaPageState>[
      QaPageState.loading,
      QaPageState.success,
      QaPageState.unavailable,
    ],
    builder: (AppDependencies dependencies, _) =>
        SupportTicketPage(initialTicket: qaSupportTicket(dependencies)),
  ),
  QaPageEntry(
    id: 'RM-001',
    name: '创建房间',
    area: ProductArea.room,
    widgetClass: 'CreateRoomPage',
    sourcePath: 'lib/features/room/presentation/create_room_page.dart',
    userEntry: '首页 → 创建房间',
    requiredStates: _formStates,
    builder: (_, __) => const CreateRoomPage(),
  ),
  QaPageEntry(
    id: 'RM-002',
    name: '编辑与关闭房间',
    area: ProductArea.room,
    widgetClass: 'EditRoomPage',
    sourcePath: 'lib/features/room/presentation/edit_room_page.dart',
    userEntry: '收藏与我的房间 → 我的房间 → 管理',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.conflict,
      QaPageState.submitting,
      QaPageState.closed,
    ],
    builder: (_, __) => const EditRoomPage(roomId: '952700'),
  ),
  QaPageEntry(
    id: 'RM-003',
    name: '房间直达与深链校验别名',
    area: ProductArea.room,
    widgetClass: 'RoomDeepLinkPage',
    sourcePath: 'lib/features/room/presentation/room_deep_link_page.dart',
    userEntry: '搜索/分享/通知深链 → 校验 → 有效目标直接 RM-004',
    requiredStates: const <QaPageState>[
      QaPageState.loading,
      QaPageState.unavailable,
      QaPageState.closed,
      QaPageState.error,
    ],
    builder: (_, __) => const RoomDeepLinkPage(input: 'not-a-room'),
  ),
  QaPageEntry(
    id: 'RM-004',
    name: '语音房主界面',
    area: ProductArea.room,
    widgetClass: 'RoomPage',
    sourcePath: 'lib/features/room/presentation/room_page.dart',
    userEntry: '首页/搜索/榜单/通知有效房间入口 → 语音房',
    requiredStates: const <QaPageState>[
      QaPageState.loading,
      QaPageState.normal,
      QaPageState.offline,
      QaPageState.reconnecting,
      QaPageState.closed,
    ],
    vendorBoundary: 'RTC 与实时消息供应商未接入',
    builder: (AppDependencies dependencies, _) {
      seedQaRoomEntryRole(dependencies, RoomRole.owner);
      return const RoomPage(roomId: '880217', title: '深夜温柔陪伴');
    },
  ),
  QaPageEntry(
    id: 'RM-005',
    name: '上麦申请与麦位选择',
    area: ProductArea.room,
    widgetClass: '_MicRequestSheet (via RoomPage)',
    sourcePath: 'lib/features/room/presentation/room_page_sheets.dart',
    userEntry: 'RM-004 → 申请上麦',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.submitting,
      QaPageState.conflict,
      QaPageState.success,
    ],
    builder: (_, __) => const RoomPage(roomId: '880217', title: '深夜温柔陪伴'),
  ),
  QaPageEntry(
    id: 'RM-006',
    name: '在线成员与听众席',
    area: ProductArea.room,
    widgetClass: 'RoomMembersPage',
    sourcePath: 'lib/features/room/presentation/room_members_page.dart',
    userEntry: 'RM-004 → 成员',
    requiredStates: _repositoryStates,
    builder: (_, QaScenario scenario) => RoomMembersPage(
      roomId: '880217',
      currentUserId: 10001,
      currentRole: _roomRole(scenario.role),
      seats: qaEightSeats,
      roomTitle: '深夜温柔陪伴',
    ),
  ),
  QaPageEntry(
    id: 'RM-007',
    name: '房主管理与处罚',
    area: ProductArea.room,
    widgetClass: 'RoomManagementPage',
    sourcePath: 'lib/features/room/presentation/room_management_page.dart',
    userEntry: 'RM-004 → 更多 → 房间管理',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.permissionDenied,
      QaPageState.conflict,
      QaPageState.success,
    ],
    builder: (_, QaScenario scenario) => RoomManagementPage(
      roomId: '880217',
      currentUserId: 10001,
      currentRole: _managementRole(scenario.role),
      seats: qaEightSeats,
      roomTitle: '深夜温柔陪伴',
    ),
  ),
  QaPageEntry(
    id: 'RM-008',
    name: '房间公告编辑',
    area: ProductArea.room,
    widgetClass: 'RoomTopicPage',
    sourcePath: 'lib/features/room/presentation/room_topic_page.dart',
    userEntry: 'RM-004 → 公告',
    requiredStates: _formStates,
    builder: (_, QaScenario scenario) => RoomTopicPage(
      roomId: '880217',
      canEdit:
          scenario.role == QaRole.owner ||
          scenario.role == QaRole.moderator ||
          scenario.role == QaRole.platformModerator,
      roomTitle: '深夜温柔陪伴',
    ),
  ),
  QaPageEntry(
    id: 'RM-009',
    name: '房间分享',
    area: ProductArea.room,
    widgetClass: 'RoomSharePage',
    sourcePath: 'lib/features/room/presentation/room_share_page.dart',
    userEntry: 'RM-004 → 分享',
    vendorBoundary: '原生渠道分享适配器未接入；复制邀请可验收',
    builder: (_, __) => const RoomSharePage(
      roomId: '880217',
      roomCode: '880217',
      roomTitle: '深夜温柔陪伴',
    ),
  ),
  QaPageEntry(
    id: 'RM-010',
    name: '音频路由与麦克风控制',
    area: ProductArea.room,
    widgetClass: 'RoomAudioPage',
    sourcePath: 'lib/features/room/presentation/room_audio_page.dart',
    userEntry: 'RM-004 → 更多 → 音频与麦克风',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.permissionDenied,
      QaPageState.unavailable,
    ],
    vendorBoundary: '原生音频路由与 RTC 未接入',
    builder: (_, QaScenario scenario) => RoomAudioPage(
      isOnMic:
          scenario.role == QaRole.speaker ||
          scenario.role == QaRole.owner ||
          scenario.role == QaRole.moderator,
      roomTitle: '深夜温柔陪伴',
    ),
  ),
  QaPageEntry(
    id: 'RM-011',
    name: '弱网重连与会话恢复',
    area: ProductArea.room,
    widgetClass: 'RoomRecoveryPage',
    sourcePath: 'lib/features/room/presentation/room_recovery_page.dart',
    userEntry: 'RM-004 → 更多 → 弱网重连与会话恢复',
    requiredStates: const <QaPageState>[
      QaPageState.offline,
      QaPageState.reconnecting,
      QaPageState.success,
      QaPageState.error,
    ],
    vendorBoundary: 'RTC 与实时消息供应商未接入',
    builder: (AppDependencies dependencies, _) => _QaControllerPage(
      dependencies: dependencies,
      childBuilder: (RoomController controller) =>
          RoomRecoveryPage(controller: controller, roomTitle: '深夜温柔陪伴'),
    ),
  ),
  QaPageEntry(
    id: 'RM-012',
    name: '房间质量诊断',
    area: ProductArea.room,
    widgetClass: 'RoomDiagnosticsPage',
    sourcePath: 'lib/features/room/presentation/room_diagnostics_page.dart',
    userEntry: 'RM-004 → 更多 → 房间质量诊断',
    requiredStates: const <QaPageState>[
      QaPageState.loading,
      QaPageState.normal,
      QaPageState.unavailable,
    ],
    vendorBoundary: '真实 RTC 遥测未接入',
    builder: (AppDependencies dependencies, _) => _QaControllerPage(
      dependencies: dependencies,
      childBuilder: (RoomController controller) =>
          RoomDiagnosticsPage(controller: controller, roomTitle: '深夜温柔陪伴'),
    ),
  ),
  QaPageEntry(
    id: 'RM-013',
    name: 'PK 邀请与准备',
    area: ProductArea.room,
    widgetClass: 'RoomPkPreparationPage',
    sourcePath: 'lib/features/room/pk/presentation/room_pk_pages.dart',
    userEntry: 'RM-004 → 更多 → 房间 PK',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.submitting,
      QaPageState.expired,
      QaPageState.conflict,
    ],
    builder: (_, __) =>
        const RoomPkPreparationPage(roomId: '880217', roomTitle: '深夜温柔陪伴'),
  ),
  QaPageEntry(
    id: 'RM-014',
    name: 'PK 对战与结算',
    area: ProductArea.room,
    widgetClass: 'RoomPkBattlePage',
    sourcePath: 'lib/features/room/pk/presentation/room_pk_pages.dart',
    userEntry: 'PK 邀请接受 → 对战 → 服务端结算',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.submitting,
      QaPageState.success,
      QaPageState.expired,
    ],
    vendorBoundary: '实时比分通道未接入；Mock 使用服务端轮询语义',
    builder: (AppDependencies dependencies, QaScenario scenario) =>
        RoomPkBattlePage(
          roomId: '880217',
          initialBattle: qaRoomPkBattle(
            dependencies,
            completed: scenario.state == QaPageState.success,
          ),
        ),
  ),
  QaPageEntry(
    id: 'MS-001',
    name: '会话列表',
    area: ProductArea.message,
    widgetClass: 'MessageCenterPage',
    sourcePath: 'lib/features/message/presentation/message_center_page.dart',
    userEntry: '根导航 → 消息',
    requiredStates: _repositoryStates,
    vendorBoundary: '腾讯 IM 未接入；Mock 会话可验收',
    builder: (_, __) => const MessageCenterPage(),
  ),
  QaPageEntry(
    id: 'MS-002',
    name: '私聊会话',
    area: ProductArea.message,
    widgetClass: 'PrivateChatPage',
    sourcePath: 'lib/features/message/presentation/private_chat_page.dart',
    userEntry: '消息列表/成员 → 私聊会话',
    requiredStates: _repositoryStates,
    vendorBoundary: '腾讯 IM 未接入；Live 发送保持失败关闭',
    builder: (_, __) => PrivateChatPage(conversation: qaConversation()),
  ),
  QaPageEntry(
    id: 'MS-003',
    name: '系统与互动通知',
    area: ProductArea.message,
    widgetClass: 'NotificationCenterPage',
    sourcePath: 'lib/features/message/presentation/notification_pages.dart',
    userEntry: '消息 → 系统与互动通知',
    requiredStates: _repositoryStates,
    vendorBoundary: '推送供应商未接入；服务端列表可验收',
    builder: (_, __) => const NotificationCenterPage(),
  ),
  QaPageEntry(
    id: 'MS-004',
    name: '通知详情',
    area: ProductArea.message,
    widgetClass: 'NotificationDetailPage',
    sourcePath: 'lib/features/message/presentation/notification_pages.dart',
    userEntry: '通知中心 → 通知',
    requiredStates: _repositoryStates,
    builder: (_, __) =>
        const NotificationDetailPage(notificationId: 'notification-room-1'),
  ),
  QaPageEntry(
    id: 'MS-005',
    name: '通知目标不可用',
    area: ProductArea.message,
    widgetClass: 'NotificationTargetUnavailablePage',
    sourcePath: 'lib/features/message/presentation/notification_pages.dart',
    userEntry: '通知详情 → 已删除/关闭/失效目标',
    requiredStates: const <QaPageState>[
      QaPageState.unavailable,
      QaPageState.expired,
      QaPageState.closed,
    ],
    builder: (_, __) =>
        const NotificationTargetUnavailablePage(reason: '动态已删除或不可见'),
  ),
  QaPageEntry(
    id: 'MS-006',
    name: '通知权限与消息恢复',
    area: ProductArea.message,
    widgetClass: 'MessagePermissionRecoveryPage',
    sourcePath: 'lib/features/message/presentation/message_recovery_page.dart',
    userEntry: '消息 → 通知权限与消息恢复',
    requiredStates: const <QaPageState>[
      QaPageState.permission,
      QaPageState.permissionDenied,
      QaPageState.offline,
      QaPageState.success,
    ],
    vendorBoundary: '腾讯 IM 与原生推送权限适配器未接入',
    builder: (_, __) => const MessagePermissionRecoveryPage(),
  ),
  QaPageEntry(
    id: 'CM-001',
    name: '钱包与流水',
    area: ProductArea.commerce,
    widgetClass: 'WalletPage',
    sourcePath: 'lib/features/commerce/presentation/commerce_wallet_pages.dart',
    userEntry: '我的 → 钱包、订单与收益 → 钱包与流水',
    requiredStates: _repositoryStates,
    builder: (_, __) => const WalletPage(),
  ),
  QaPageEntry(
    id: 'CM-002',
    name: '充值商品目录',
    area: ProductArea.commerce,
    widgetClass: 'RechargeCatalogPage',
    sourcePath:
        'lib/features/commerce/presentation/commerce_catalog_pages.dart',
    userEntry: '钱包/礼物余额不足 → 充值商品目录',
    requiredStates: _repositoryStates,
    builder: (_, __) => const RechargeCatalogPage(),
  ),
  QaPageEntry(
    id: 'CM-003',
    name: '支付方式与提交中',
    area: ProductArea.commerce,
    widgetClass: 'PaymentSubmissionPage',
    sourcePath:
        'lib/features/commerce/presentation/commerce_catalog_pages.dart',
    userEntry: '充值商品目录 → 选择商品',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.submitting,
      QaPageState.restricted,
      QaPageState.unavailable,
    ],
    vendorBoundary: '微信支付与支付宝 SDK 未接入',
    builder: (_, QaScenario scenario) => PaymentSubmissionPage(
      product: qaRechargeProduct,
      platform: ClientStorePlatform.android,
      youthModeEnabled: scenario.role == QaRole.youthMode,
    ),
  ),
  QaPageEntry(
    id: 'CM-004',
    name: '支付返回与结果',
    area: ProductArea.commerce,
    widgetClass: 'PaymentResultPage',
    sourcePath:
        'lib/features/commerce/presentation/commerce_catalog_pages.dart',
    userEntry: '支付返回 → 服务端订单状态确认',
    requiredStates: const <QaPageState>[
      QaPageState.submitting,
      QaPageState.success,
      QaPageState.error,
      QaPageState.unavailable,
    ],
    vendorBoundary: '支付供应商回调未接入；结果只认服务端',
    builder: (AppDependencies dependencies, QaScenario scenario) =>
        PaymentResultPage(
          order: qaRechargeOrder(
            dependencies,
            succeeded: scenario.state == QaPageState.success,
          ),
        ),
  ),
  QaPageEntry(
    id: 'CM-005',
    name: '订单列表',
    area: ProductArea.commerce,
    widgetClass: 'OrdersPage',
    sourcePath: 'lib/features/commerce/presentation/commerce_order_pages.dart',
    userEntry: '钱包、订单与收益 → 充值订单',
    requiredStates: _repositoryStates,
    builder: (_, __) => const OrdersPage(),
  ),
  QaPageEntry(
    id: 'CM-006',
    name: '订单详情与补单',
    area: ProductArea.commerce,
    widgetClass: 'OrderDetailPage',
    sourcePath: 'lib/features/commerce/presentation/commerce_order_pages.dart',
    userEntry: '订单列表 → 订单',
    requiredStates: const <QaPageState>[
      QaPageState.loading,
      QaPageState.normal,
      QaPageState.success,
      QaPageState.error,
    ],
    builder: (AppDependencies dependencies, _) =>
        OrderDetailPage(order: qaPaymentOrder(dependencies)),
  ),
  QaPageEntry(
    id: 'CM-007',
    name: '退款申请列表',
    area: ProductArea.commerce,
    widgetClass: 'RefundListPage',
    sourcePath: 'lib/features/commerce/presentation/commerce_refund_pages.dart',
    userEntry: '钱包、订单与收益 → 退款申请',
    requiredStates: _repositoryStates,
    builder: (_, __) => const RefundListPage(account: '13800138000'),
  ),
  QaPageEntry(
    id: 'CM-008',
    name: '退款申请与结果',
    area: ProductArea.commerce,
    widgetClass: 'RefundApplicationPage / RefundResultPage',
    sourcePath: 'lib/features/commerce/presentation/commerce_refund_pages.dart',
    userEntry: '退款申请列表 → 新申请/历史结果',
    requiredStates: _formStates,
    builder: (AppDependencies dependencies, QaScenario scenario) =>
        scenario.state == QaPageState.success
        ? RefundResultPage(application: qaRefundApplication(dependencies))
        : const RefundApplicationPage(account: '13800138000'),
  ),
  QaPageEntry(
    id: 'CM-009',
    name: '礼物目录与赠送面板',
    area: ProductArea.commerce,
    widgetClass: 'GiftCatalogPage / GiftSheet',
    sourcePath:
        'lib/features/commerce/presentation/commerce_catalog_pages.dart',
    userEntry: 'RM-004 → 礼物 Bottom Sheet；钱包 → 礼物目录',
    requiredStates: _repositoryStates,
    builder: (_, __) =>
        const GiftCatalogPage(initialGifts: qaReviewedPopularGiftCatalog),
  ),
  QaPageEntry(
    id: 'CM-010',
    name: '装扮中心',
    area: ProductArea.commerce,
    widgetClass: 'DecorationPage',
    sourcePath:
        'lib/features/commerce/presentation/commerce_catalog_pages.dart',
    userEntry: '我的 → 装扮；钱包与商业化 → 装扮中心',
    requiredStates: _repositoryStates,
    builder: (_, __) => const DecorationPage(),
  ),
  QaPageEntry(
    id: 'CM-011',
    name: '主播收益',
    area: ProductArea.commerce,
    widgetClass: 'EarningsPage',
    sourcePath:
        'lib/features/commerce/presentation/commerce_earnings_pages.dart',
    userEntry: '钱包、订单与收益 → 主播收益',
    requiredStates: _repositoryStates,
    builder: (_, __) => const EarningsPage(),
  ),
  QaPageEntry(
    id: 'CM-012',
    name: '结算与提现',
    area: ProductArea.commerce,
    widgetClass: 'WithdrawalPage',
    sourcePath:
        'lib/features/commerce/presentation/commerce_earnings_pages.dart',
    userEntry: '主播收益/钱包 → 结算与提现',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.permissionDenied,
      QaPageState.submitting,
      QaPageState.success,
      QaPageState.error,
    ],
    builder: (_, __) => const WithdrawalPage(),
  ),
  QaPageEntry(
    id: 'SC-001',
    name: '公会主页',
    area: ProductArea.community,
    widgetClass: 'GuildHomePage',
    sourcePath: 'lib/features/community/presentation/guild_home_pages.dart',
    userEntry: '发现 → 社交经营 → 公会主页',
    requiredStates: _repositoryStates,
    builder: (_, __) => const GuildHomePage(),
  ),
  QaPageEntry(
    id: 'SC-002',
    name: '公会加入与成员管理',
    area: ProductArea.community,
    widgetClass: 'GuildMembersEntryPage',
    sourcePath: 'lib/features/community/presentation/guild_members_pages.dart',
    userEntry: '社交经营 → 公会加入与成员管理',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.permissionDenied,
      QaPageState.submitting,
      QaPageState.conflict,
    ],
    builder: (_, __) => const GuildMembersEntryPage(),
  ),
  QaPageEntry(
    id: 'SC-003',
    name: '邀请与渠道归属',
    area: ProductArea.community,
    widgetClass: 'InviteAttributionPage',
    sourcePath: 'lib/features/community/presentation/invite_cp_pages.dart',
    userEntry: '社交经营 → 邀请与渠道归属',
    requiredStates: _repositoryStates,
    builder: (_, __) => const InviteAttributionPage(),
  ),
  QaPageEntry(
    id: 'SC-004',
    name: 'CP 关系',
    area: ProductArea.community,
    widgetClass: 'CpRelationPage',
    sourcePath: 'lib/features/community/presentation/invite_cp_pages.dart',
    userEntry: '社交经营 → CP 关系',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.submitting,
      QaPageState.conflict,
      QaPageState.expired,
    ],
    builder: (_, __) => const CpRelationPage(),
  ),
  QaPageEntry(
    id: 'SC-005',
    name: '守护与粉团',
    area: ProductArea.community,
    widgetClass: 'GuardianFanPage',
    sourcePath: 'lib/features/community/presentation/guardian_fan_page.dart',
    userEntry: '社交经营 → 守护与粉团',
    requiredStates: _repositoryStates,
    builder: (_, __) => const GuardianFanPage(),
  ),
  QaPageEntry(
    id: 'SC-006',
    name: '任务与签到',
    area: ProductArea.community,
    widgetClass: 'TaskCheckInPage',
    sourcePath: 'lib/features/community/presentation/task_check_in_page.dart',
    userEntry: '社交经营 → 任务与签到',
    requiredStates: const <QaPageState>[
      QaPageState.normal,
      QaPageState.submitting,
      QaPageState.success,
      QaPageState.conflict,
    ],
    builder: (_, __) => const TaskCheckInPage(),
  ),
  QaPageEntry(
    id: 'SC-007',
    name: '主题活动中心',
    area: ProductArea.community,
    widgetClass: 'ActivityCenterPage',
    sourcePath: 'lib/features/community/presentation/activity_center_page.dart',
    userEntry: '社交经营 → 主题活动中心',
    requiredStates: _repositoryStates,
    builder: (_, __) => const ActivityCenterPage(),
  ),
];

RoomRole _roomRole(QaRole role) => switch (role) {
  QaRole.owner || QaRole.guildOwner => RoomRole.owner,
  QaRole.moderator || QaRole.guildAdmin => RoomRole.moderator,
  QaRole.platformModerator => RoomRole.platformModerator,
  QaRole.speaker => RoomRole.speaker,
  QaRole.guest => RoomRole.guest,
  _ => RoomRole.listener,
};

RoomRole _managementRole(QaRole role) {
  final RoomRole mapped = _roomRole(role);
  return mapped == RoomRole.owner ||
          mapped == RoomRole.moderator ||
          mapped == RoomRole.platformModerator
      ? mapped
      : RoomRole.owner;
}

typedef _ControllerChildBuilder = Widget Function(RoomController controller);

class _QaControllerPage extends StatefulWidget {
  const _QaControllerPage({
    required this.dependencies,
    required this.childBuilder,
  });

  final AppDependencies dependencies;
  final _ControllerChildBuilder childBuilder;

  @override
  State<_QaControllerPage> createState() => _QaControllerPageState();
}

class _QaControllerPageState extends State<_QaControllerPage> {
  late final RoomController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.dependencies.createRoomController(
      roomId: '880217',
      title: '深夜温柔陪伴',
    );
    _controller.join();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.childBuilder(_controller);
}
