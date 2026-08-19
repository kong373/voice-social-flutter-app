import 'package:flutter/foundation.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';

/// Holds the single active room controller while its page is minimized.
///
/// The coordinator does not create provider credentials or bypass the
/// fail-closed RTC/IM adapters. It only preserves the first-party room session
/// state so the lobby can expose the compact resume control shown in the
/// runtime reference video.
class RoomSessionCoordinator extends ChangeNotifier {
  RoomSessionCoordinator._();

  static final RoomSessionCoordinator instance = RoomSessionCoordinator._();

  RoomController? _controller;
  String? _roomId;
  String? _title;
  bool _minimized = false;

  RoomController? get controller => _controller;
  String? get roomId => _roomId;
  String? get title => _title;
  bool get isMinimized => _minimized && _controller != null;
  bool get hasActiveSession => _controller != null;

  RoomController? controllerFor(String roomId) {
    if (_roomId == roomId) {
      return _controller;
    }
    return null;
  }

  void attach({
    required RoomController controller,
    required String roomId,
    required String title,
  }) {
    if (identical(_controller, controller) && _roomId == roomId) {
      _minimized = false;
      notifyListeners();
      return;
    }
    final RoomController? previous = _controller;
    _controller = controller;
    _roomId = roomId;
    _title = title;
    _minimized = false;
    if (previous != null && !identical(previous, controller)) {
      previous.dispose();
    }
    notifyListeners();
  }

  void minimize() {
    if (_controller == null || _minimized) {
      return;
    }
    _minimized = true;
    notifyListeners();
  }

  void restore() {
    if (_controller == null || !_minimized) {
      return;
    }
    _minimized = false;
    notifyListeners();
  }

  void detach(RoomController controller) {
    if (!identical(_controller, controller)) {
      return;
    }
    _controller = null;
    _roomId = null;
    _title = null;
    _minimized = false;
    notifyListeners();
  }

  Future<void> leaveMinimizedSession() async {
    final RoomController? active = _controller;
    if (active == null) {
      return;
    }
    try {
      await active.leave();
    } finally {
      detach(active);
      active.dispose();
    }
  }
}
