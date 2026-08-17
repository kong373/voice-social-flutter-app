import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/debug/qa_console/qa_console_page.dart';
import 'package:voice_social_app/debug/qa_console/qa_fixtures.dart';

class QaConsoleHost extends StatefulWidget {
  const QaConsoleHost({super.key});

  @override
  State<QaConsoleHost> createState() => _QaConsoleHostState();
}

class _QaConsoleHostState extends State<QaConsoleHost> {
  late Future<AppDependencies> _dependencies;

  @override
  void initState() {
    super.initState();
    _dependencies = createQaDependencies();
  }

  Future<void> _reset() async {
    final Future<AppDependencies> dependencies = createQaDependencies();
    setState(() {
      _dependencies = dependencies;
    });
    await dependencies;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDependencies>(
      future: _dependencies,
      builder: (BuildContext context, AsyncSnapshot<AppDependencies> snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('QA Mock 初始化失败：${snapshot.error}')),
          );
        }
        final AppDependencies? dependencies = snapshot.data;
        if (dependencies == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return AppDependencyScope(
          dependencies: dependencies,
          child: QaConsolePage(
            dependencies: dependencies,
            onResetMockData: _reset,
          ),
        );
      },
    );
  }
}
