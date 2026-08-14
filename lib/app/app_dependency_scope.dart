import 'package:flutter/widgets.dart';
import 'package:voice_social_app/app/app_dependencies.dart';

class AppDependencyScope extends InheritedWidget {
  const AppDependencyScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final AppDependencyScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppDependencyScope>();
    if (scope == null) {
      throw StateError('AppDependencyScope is missing above this route');
    }
    return scope.dependencies;
  }

  @override
  bool updateShouldNotify(AppDependencyScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}
