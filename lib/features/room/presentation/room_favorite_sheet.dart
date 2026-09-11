import 'dart:async';
import 'package:flutter/material.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_repository.dart';
import 'package:voice_social_app/features/room/application/room_controller.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

/// Reads the existing authoritative collection before offering an explicit
/// mutation. A pending write never becomes an optimistic local favorite.
class RoomFavoriteSheet extends StatefulWidget {
  const RoomFavoriteSheet({
    required this.controller,
    required this.repository,
    super.key,
  });
  final RoomController controller;
  final DiscoveryRepository repository;

  @override
  State<RoomFavoriteSheet> createState() => _RoomFavoriteSheetState();
}

class _RoomFavoriteSheetState extends State<RoomFavoriteSheet> {
  bool? _favorite;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _generation = 0;

  bool get _active =>
      widget.controller.isEntryIdentityCurrent &&
      widget.controller.status == RoomSessionStatus.joined;
  bool _current(int generation) =>
      mounted && _active && generation == _generation;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_roomChanged);
    unawaited(_load());
  }

  void _roomChanged() {
    if (!mounted || _active) return;
    _generation++;
    setState(() {
      _favorite = null;
      _loading = false;
      _saving = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _generation++;
    widget.controller.removeListener(_roomChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_active || _saving) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final collections = await widget.repository.fetchRoomCollections();
      if (!_current(generation)) return;
      setState(() {
        _favorite = collections.favorites.any(
          (room) => room.id == widget.controller.roomId,
        );
      });
    } catch (error) {
      if (!_current(generation)) return;
      setState(
        () => _error = error is ApiException ? error.message : '收藏状态暂时无法加载，请重试',
      );
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    if (!_active || _loading || _saving || _favorite == null) return;
    final generation = ++_generation;
    final desired = !_favorite!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final confirmed = await widget.repository.setFavorite(
        roomId: widget.controller.roomId,
        favorite: desired,
      );
      if (!_current(generation)) return;
      if (confirmed != desired) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '收藏状态尚未确认，请重新加载',
        );
      }
      setState(() => _favorite = confirmed);
    } catch (error) {
      if (!_current(generation)) return;
      setState(
        () => _error = error is ApiException ? error.message : '收藏保存失败，请重试',
      );
    } finally {
      if (_current(generation)) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '收藏房间',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '关闭收藏面板',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_active)
            const Text('房间会话已结束，请重新进入后操作')
          else if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            if (_favorite != null) Text(_favorite! ? '已收藏此房间' : '尚未收藏此房间'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!),
              ),
            const SizedBox(height: 16),
            if (_favorite == null)
              FilledButton(onPressed: _load, child: const Text('重新加载'))
            else
              FilledButton.icon(
                onPressed: _saving ? null : _toggle,
                icon: Icon(
                  _favorite!
                      ? Icons.bookmark_remove_outlined
                      : Icons.bookmark_add_outlined,
                ),
                label: Text(
                  _saving ? '正在保存' : (_favorite! ? '取消收藏' : '收藏当前房间'),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
