import 'package:flutter/foundation.dart';

const bool _qaConsoleRequested = bool.fromEnvironment(
  'ENABLE_QA_CONSOLE',
  defaultValue: false,
);

bool get qaConsoleEnabled => kDebugMode && _qaConsoleRequested;
