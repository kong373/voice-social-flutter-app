import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_gate.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

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
        home: AppGate(dependencies: dependencies),
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
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.settings_suggest_outlined,
                  size: 42,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 20),
                Text(
                  '运行配置不完整',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message),
                const SizedBox(height: 12),
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
