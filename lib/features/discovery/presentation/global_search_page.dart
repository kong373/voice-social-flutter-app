import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/presentation/search_results_page.dart';
import 'package:voice_social_app/features/room/presentation/room_deep_link_page.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<String> _recent = <String>['深夜陪伴', '880217', '南风'];

  bool get _canDirectRoom =>
      RegExp(r'^\d{4,18}$').hasMatch(_controller.text.trim());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('global-search-field'),
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: '搜索房间、用户或房间号',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清空',
                    onPressed: _controller.clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: _controller.text.trim().isEmpty ? null : _search,
            child: const Text('搜索'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: <Widget>[
          if (_canDirectRoom) ...<Widget>[
            Material(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              child: ListTile(
                leading: const Icon(
                  Icons.meeting_room_outlined,
                  color: AppColors.primary,
                ),
                title: Text('直达房间 ${_controller.text.trim()}'),
                subtitle: const Text('校验成功后直接进入，不展示普通中间页'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _openRoomDirect,
              ),
            ),
            const SizedBox(height: 24),
          ],
          Row(
            children: <Widget>[
              Text('最近搜索', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: _recent.isEmpty
                    ? null
                    : () => setState(_recent.clear),
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('暂无搜索记录'),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (final String item in _recent)
                  ActionChip(
                    label: Text(item),
                    onPressed: () {
                      _controller.text = item;
                      _controller.selection = TextSelection.collapsed(
                        offset: item.length,
                      );
                      _search();
                    },
                  ),
              ],
            ),
          const SizedBox(height: 30),
          Text('搜索说明', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const _SearchGuide(
            icon: Icons.graphic_eq_rounded,
            title: '房间',
            description: '按房间名称、话题或房间号查找，点击结果直接进入房间。',
          ),
          const _SearchGuide(
            icon: Icons.person_search_outlined,
            title: '用户',
            description: '按昵称或用户号查找，可查看公开主页和当前所在房间。',
          ),
          const _SearchGuide(
            icon: Icons.shield_outlined,
            title: '结果边界',
            description: '已关闭、被封禁或无权限的房间不会伪装成可进入状态。',
          ),
        ],
      ),
    );
  }

  void _search() {
    final String keyword = _controller.text.trim();
    if (keyword.isEmpty) {
      return;
    }
    setState(() {
      _recent
        ..remove(keyword)
        ..insert(0, keyword);
      if (_recent.length > 8) {
        _recent.removeRange(8, _recent.length);
      }
    });
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => SearchResultsPage(keyword: keyword),
      ),
    );
  }

  void _openRoomDirect() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RoomDeepLinkPage(input: _controller.text.trim()),
      ),
    );
  }
}

class _SearchGuide extends StatelessWidget {
  const _SearchGuide({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
