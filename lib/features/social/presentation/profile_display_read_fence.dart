import 'package:flutter/widgets.dart';
import '../../../app/app_dependencies.dart';
import '../../../app/app_dependency_scope.dart';

/// View-only profile read isolation; no authentication or mutation behavior.
mixin ProfileDisplayReadFence<T extends StatefulWidget> on State<T> {
  AppDependencies? _displayDependencies;
  (int?, int)? _viewer;
  int _displayRead = 0;
  bool _identityChanged = false;
  bool profileDisplayReadStarted = false;
  void clearProfileDisplay();
  Future<void> reloadProfileDisplay();
  AppDependencies get profileDisplayDependencies =>
      AppDependencyScope.of(context);
  (int?, int) get _currentViewer {
    final session = profileDisplayDependencies.sessionManager;
    return (session.session?.userId, session.identityGeneration);
  }

  bool get profileDisplayAuthenticated => _currentViewer.$1 != null;
  bool get profileDisplayReadAllowed =>
      profileDisplayAuthenticated ||
      (!_identityChanged && !profileDisplayDependencies.environment.isLive);
  (int, (int?, int)) beginProfileDisplayRead() {
    profileDisplayReadStarted = true;
    return (++_displayRead, _currentViewer);
  }

  bool acceptsProfileDisplayRead((int, (int?, int)) ticket) =>
      mounted && ticket.$1 == _displayRead && ticket.$2 == _currentViewer;
  void resetProfileDisplayRead() {
    _displayRead++;
    profileDisplayReadStarted = false;
    clearProfileDisplay();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deps = profileDisplayDependencies;
    if (identical(deps, _displayDependencies)) return;
    _displayDependencies?.sessionManager.removeListener(_changed);
    if (_displayDependencies != null) resetProfileDisplayRead();
    _displayDependencies = deps;
    _viewer = _currentViewer;
    deps.sessionManager.addListener(_changed);
  }

  void _changed() {
    if (!mounted || _viewer == _currentViewer) return;
    _viewer = _currentViewer;
    _identityChanged = true;
    setState(resetProfileDisplayRead);
    if (profileDisplayAuthenticated) reloadProfileDisplay();
  }

  @override
  void dispose() {
    _displayRead++;
    _displayDependencies?.sessionManager.removeListener(_changed);
    super.dispose();
  }
}
