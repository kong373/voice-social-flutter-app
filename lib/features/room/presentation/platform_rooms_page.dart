import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/features/room/data/platform_room_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_page.dart';

/// Resolves server authority independently of JWT claims or room roles.
class PlatformRoomsEntry extends StatefulWidget {
  const PlatformRoomsEntry({required this.repository, super.key});
  final PlatformRoomRepository repository;
  @override
  State<PlatformRoomsEntry> createState() => _PlatformRoomsEntryState();
}

class _PlatformRoomsEntryState extends State<PlatformRoomsEntry>
    with WidgetsBindingObserver {
  int _epoch = 0;
  bool _allowed = false;
  @override
  void initState() {
    super.initState();
    widget.repository.identityChanges.addListener(_load);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    final identity = widget.repository.identity;
    if (mounted) setState(() => _allowed = false);
    try {
      final allowed = await widget.repository.authority();
      if (mounted &&
          epoch == _epoch &&
          identity == widget.repository.identity) {
        setState(() => _allowed = allowed);
      }
    } catch (_) {
      /* Authority failure never exposes a private entry. */
    }
  }

  @override
  void dispose() {
    widget.repository.identityChanges.removeListener(_load);
    WidgetsBinding.instance.removeObserver(this);
    ++_epoch;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_allowed
      ? const SizedBox.shrink()
      : ListTile(
          leading: const Icon(Icons.admin_panel_settings_outlined),
          title: const Text('平台房间管理'),
          onTap: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    PlatformRoomsPage(repository: widget.repository),
              ),
            );
            if (mounted) _load();
          },
        );
}

class PlatformRoomsPage extends StatefulWidget {
  const PlatformRoomsPage({this.repository, super.key});
  final PlatformRoomRepository? repository;
  @override
  State<PlatformRoomsPage> createState() => _PlatformRoomsPageState();
}

class _PlatformRoomsPageState extends State<PlatformRoomsPage>
    with WidgetsBindingObserver {
  PlatformRoomRepository? _repository;
  final _search = TextEditingController();
  List<PlatformRoom> _rooms = [];
  String? _error;
  bool _loading = true, _more = false;
  int _page = 1, _epoch = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository != null) return;
    _repository =
        widget.repository ??
        AppDependencyScope.of(context).platformRoomRepository;
    _repository!.identityChanges.addListener(_identityChanged);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _identityChanged() {
    _search.clear();
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load({int page = 1}) async {
    final repository = _repository!;
    final identity = repository.identity;
    final epoch = ++_epoch;
    setState(() {
      _rooms = [];
      _error = null;
      _loading = true;
      _more = false;
    });
    try {
      final result = await repository.list(page: page, keyword: _search.text);
      if (!mounted || epoch != _epoch || identity != repository.identity)
        return;
      setState(() {
        _rooms = result.rooms;
        _page = result.current;
        _more = result.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _epoch || identity != repository.identity)
        return;
      setState(() {
        _loading = false;
        _error = '无法读取平台房间，请确认当前账号权限后重试';
      });
    }
  }

  @override
  void dispose() {
    _repository?.identityChanges.removeListener(_identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    ++_epoch;
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('平台房间管理')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            maxLength: 120,
            decoration: const InputDecoration(labelText: '搜索房间'),
            onSubmitted: (_) => _load(),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        TextButton(
          onPressed: _loading ? null : () => _load(),
          child: const Text('刷新'),
        ),
        Expanded(
          child: ListView(
            children: [
              for (final room in _rooms)
                ListTile(
                  title: Text(room.roomName),
                  subtitle: Text(
                    '${room.roomCode} · ${room.status == 'CLOSED' ? '已关闭' : '开放中'}',
                  ),
                  onTap: () async {
                    final identity = _repository!.identity;
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) =>
                            RoomPage(roomId: room.roomId, title: room.roomName),
                      ),
                    );
                    if (mounted && identity == _repository!.identity)
                      _load(page: _page);
                  },
                ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _loading || _page <= 1
                  ? null
                  : () => _load(page: _page - 1),
              child: const Text('上一页'),
            ),
            TextButton(
              onPressed: _loading || !_more
                  ? null
                  : () => _load(page: _page + 1),
              child: const Text('下一页'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Separate from EditRoomPage: no metadata or member-governance capability.
class PlatformRoomLifecycleButton extends StatefulWidget {
  const PlatformRoomLifecycleButton({
    required this.repository,
    required this.roomId,
    required this.version,
    required this.reopen,
    required this.onCompleted,
    super.key,
  });
  final PlatformRoomRepository repository;
  final String roomId;
  final int version;
  final bool reopen;
  final Future<void> Function() onCompleted;
  @override
  State<PlatformRoomLifecycleButton> createState() =>
      _PlatformRoomLifecycleButtonState();
}

class _PlatformRoomLifecycleButtonState
    extends State<PlatformRoomLifecycleButton> {
  bool _busy = false;
  String? _error;
  late (int, int) _identity;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    _identity = widget.repository.identity;
    widget.repository.identityChanges.addListener(_changed);
  }

  void _changed() {
    if (_identity == widget.repository.identity) return;
    ++_epoch;
    if (mounted)
      setState(() {
        _busy = false;
        _error = null;
      });
    // This room view belongs to the original identity, never retarget it.
  }

  @override
  void dispose() {
    ++_epoch;
    widget.repository.identityChanges.removeListener(_changed);
    super.dispose();
  }

  Future<void> _submit() async {
    final identity = widget.repository.identity;
    if (identity != _identity) return;
    final pending = widget.repository.pending;
    if (pending != null && pending.roomId != widget.roomId) {
      setState(() => _error = '另一个房间操作结果未确认，请返回原房间重试');
      return;
    }
    final roomId = pending?.roomId ?? widget.roomId;
    final version = pending?.expectedVersion ?? widget.version;
    final reopen = pending?.reopen ?? widget.reopen;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          pending != null
              ? '重试原房间操作？'
              : reopen
              ? '重新开放房间？'
              : '关闭房间？',
        ),
        content: Text(
          reopen ? '仅改变房间开放状态；开放后需明确重新进入，不会自动连接语音。' : '确认关闭该房间？当前房间会话将结束。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (!mounted || epoch != _epoch || identity != widget.repository.identity)
      return;
    if (confirm != true) {
      setState(() => _busy = false);
      return;
    }
    try {
      await widget.repository.control(
        roomId: roomId,
        version: version,
        reopen: reopen,
      );
      if (!mounted || epoch != _epoch || identity != widget.repository.identity)
        return;
      await widget.onCompleted();
    } catch (_) {
      if (!mounted || epoch != _epoch || identity != widget.repository.identity)
        return;
      setState(
        () => _error = widget.repository.pending == null
            ? '操作未完成，请刷新房间状态后重新确认'
            : '结果尚未确认，请重试原操作（保留原请求）',
      );
    } finally {
      if (mounted && epoch == _epoch && identity == widget.repository.identity)
        setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_identity != widget.repository.identity) return const SizedBox.shrink();
    final pending = widget.repository.pending;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) Text(_error!),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(
            pending?.roomId == widget.roomId
                ? '重试原房间操作'
                : widget.reopen
                ? '重新开放房间'
                : '关闭房间',
          ),
        ),
      ],
    );
  }
}
