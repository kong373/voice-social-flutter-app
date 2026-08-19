import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_gate.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/replica_components.dart';
import 'package:voice_social_app/debug/qa_console/qa_console_host.dart';
import 'package:voice_social_app/debug/qa_console/qa_gate.dart';

class VoiceSocialApp extends StatelessWidget {
  const VoiceSocialApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Voice Social App',
        theme: AppTheme.dark(),
        builder: (BuildContext context, Widget? child) => ReplicaAppBackdrop(
          child: child ?? const SizedBox.shrink(),
        ),
        home: qaConsoleEnabled
            ? const QaConsoleHost()
            : AppGate(dependencies: dependencies),
      ),
    );
  }
}

class BootstrapFailureApp extends StatelessWidget {
  const BootstrapFailureApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      builder: (BuildContext context, Widget? child) => ReplicaAppBackdrop(
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.settings_suggest_outlined,
                    size: 30,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  '运行配置不完整',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                ReplicaPanel(
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '请补齐安全的 dart-define 参数后重新启动。生产密钥不得写入仓库。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
