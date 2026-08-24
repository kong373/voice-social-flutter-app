import 'package:flutter/foundation.dart';

const bool _qaConsoleRequested = bool.fromEnvironment(
  'ENABLE_QA_CONSOLE',
  defaultValue: false,
);

bool shouldUseQaConsole({
  required bool isLive,
  bool requested = _qaConsoleRequested,
  bool isDebug = kDebugMode,
}) => isDebug && requested && !isLive;

bool get qaConsoleEnabled => shouldUseQaConsole(isLive: false);
