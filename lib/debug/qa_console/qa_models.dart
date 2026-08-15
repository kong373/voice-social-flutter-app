import 'package:flutter/widgets.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/page_manifest.dart';

enum QaRole {
  guest('游客'),
  registeredUser('注册用户'),
  listener('普通听众'),
  speaker('麦上用户'),
  moderator('房管'),
  owner('房主'),
  platformModerator('平台管理角色'),
  guildMember('公会成员'),
  guildAdmin('公会管理员'),
  guildOwner('公会会长'),
  youthMode('青少年模式用户'),
  muted('被禁言用户'),
  banned('被封禁用户'),
  realNameUnverified('实名未认证'),
  realNamePending('实名认证中'),
  realNameVerified('实名已通过');

  const QaRole(this.label);

  final String label;
}

enum QaPageState {
  normal('normal'),
  loading('loading'),
  empty('empty'),
  error('error'),
  offline('offline'),
  permission('permission'),
  permissionDenied('permissionDenied'),
  disabled('disabled'),
  conflict('conflict'),
  submitting('submitting'),
  success('success'),
  expired('expired'),
  unavailable('unavailable'),
  reconnecting('reconnecting'),
  closed('closed'),
  restricted('restricted');

  const QaPageState(this.label);

  final String label;
}

enum QaMockScenario {
  defaultData('default'),
  longContent('longContent'),
  emptyData('empty'),
  errorResponse('error'),
  conflict('conflict');

  const QaMockScenario(this.label);

  final String label;
}

enum QaNetworkScenario {
  normal('normal'),
  offline('offline'),
  highLatency('highLatency'),
  packetLoss('packetLoss');

  const QaNetworkScenario(this.label);

  final String label;
}

class QaScenario {
  const QaScenario({
    required this.role,
    required this.state,
    required this.mockScenario,
    required this.network,
  });

  final QaRole role;
  final QaPageState state;
  final QaMockScenario mockScenario;
  final QaNetworkScenario network;
}

typedef QaWidgetBuilder =
    Widget Function(AppDependencies dependencies, QaScenario scenario);

class QaPageEntry {
  const QaPageEntry({
    required this.id,
    required this.name,
    required this.area,
    required this.widgetClass,
    required this.sourcePath,
    required this.userEntry,
    required this.builder,
    this.requiredStates = const <QaPageState>[QaPageState.normal],
    this.vendorBoundary = '',
  });

  final String id;
  final String name;
  final ProductArea area;
  final String widgetClass;
  final String sourcePath;
  final String userEntry;
  final QaWidgetBuilder builder;
  final List<QaPageState> requiredStates;
  final String vendorBoundary;
}

extension QaProductAreaLabel on ProductArea {
  String get code => switch (this) {
    ProductArea.account => 'AC',
    ProductArea.discovery => 'DS',
    ProductArea.social => 'US',
    ProductArea.room => 'RM',
    ProductArea.message => 'MS',
    ProductArea.commerce => 'CM',
    ProductArea.community => 'SC',
  };
}
