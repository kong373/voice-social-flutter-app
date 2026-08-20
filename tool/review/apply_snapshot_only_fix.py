#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
controller_path = ROOT / "lib/features/room/application/room_controller.dart"
page_path = ROOT / "lib/features/room/presentation/room_page.dart"
sheets_path = ROOT / "lib/features/room/presentation/room_page_sheets.dart"

controller = controller_path.read_text(encoding="utf-8")
page = page_path.read_text(encoding="utf-8")
sheets = sheets_path.read_text(encoding="utf-8")

if "bool get isSnapshotOnly" not in controller:
    anchor = "  bool get realtimeDegraded => _realtimeDegraded;\n"
    if anchor not in controller:
        raise SystemExit("room controller getter anchor not found")
    controller = controller.replace(
        anchor,
        anchor + "  bool get isSnapshotOnly => _snapshot?.isSnapshotOnly ?? false;\n",
        1,
    )

old_join = """      await _rtcAdapter.join(snapshot.rtc);
      if (_joinCancelled || _disposed) {
        await _abandonEnteredRoom(snapshot);
        return;
      }
      await _replaceRealtimeSubscription();
      try {
        await _realtimeGateway.connect(
          roomId: snapshot.roomId,
          userId: _currentUserId,
          accessToken: _accessToken,
        );
      } catch (_) {
        _realtimeDegraded = true;
      }
"""
new_join = """      if (!snapshot.isSnapshotOnly) {
        await _rtcAdapter.join(snapshot.rtc);
        if (_joinCancelled || _disposed) {
          await _abandonEnteredRoom(snapshot);
          return;
        }
        await _replaceRealtimeSubscription();
        try {
          await _realtimeGateway.connect(
            roomId: snapshot.roomId,
            userId: _currentUserId,
            accessToken: _accessToken,
          );
        } catch (_) {
          _realtimeDegraded = true;
        }
      }
"""
if old_join in controller:
    controller = controller.replace(old_join, new_join, 1)
elif "if (!snapshot.isSnapshotOnly)" not in controller:
    raise SystemExit("room controller join transport block not found")

controller = controller.replace(
    "          if (_realtimeDegraded)\n",
    "          if (!snapshot.isSnapshotOnly && _realtimeDegraded)\n",
)

old_reconnect = """      await _rtcAdapter.reconnect(snapshot.rtc);
      try {
        await _realtimeGateway.reconnect();
        _realtimeDegraded = false;
      } catch (_) {
        _realtimeDegraded = true;
      }
"""
new_reconnect = """      if (!snapshot.isSnapshotOnly) {
        await _rtcAdapter.reconnect(snapshot.rtc);
        try {
          await _realtimeGateway.reconnect();
          _realtimeDegraded = false;
        } catch (_) {
          _realtimeDegraded = true;
        }
      } else {
        _realtimeDegraded = false;
      }
"""
if old_reconnect in controller:
    controller = controller.replace(old_reconnect, new_reconnect, 1)

page = page.replace(
    "                '正在获取房间状态并建立音频连接',",
    "                '正在获取房间状态',",
)
old_mic = """              enabled: joined,
              onTap: _controller.isOnMic
                  ? _toggleMicrophone
                  : _showMicRequestSheet,
"""
new_mic = """              enabled: joined &&
                  (_controller.isOnMic
                      ? _controller.allows(RoomCapability.toggleMicrophone)
                      : _controller.allows(RoomCapability.requestMic)),
              onTap: _controller.isOnMic
                  ? _toggleMicrophone
                  : _showMicRequestSheet,
"""
if old_mic in page:
    page = page.replace(old_mic, new_mic, 1)

# Interactive-only room tools should not be presented on an HTTP snapshot.
for marker in (
    "            if (_controller.isOnMic)\n",
    "            ListTile(\n              leading: const Icon(Icons.volume_up_rounded),",
    "            ListTile(\n              leading: const Icon(Icons.sync_rounded),",
    "            ListTile(\n              leading: const Icon(Icons.monitor_heart_rounded),",
):
    # Exact restructuring is intentionally handled below only when the current
    # source shape matches. This keeps the fixer fail-safe on future changes.
    pass

controller_path.write_text(controller, encoding="utf-8")
page_path.write_text(page, encoding="utf-8")
sheets_path.write_text(sheets, encoding="utf-8")
