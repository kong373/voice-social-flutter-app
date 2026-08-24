import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/discovery/presentation/search_results_page.dart';
import 'package:voice_social_app/features/room/presentation/room_deep_link_page.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({
    super.key,
    this.initialRecent = const <String>[],
    this.suggestions = const <String>[],
  });

  /// Mock/QA callers may provide an explicit fixture. Production and live
  /// callers default to an empty list and only retain searches made this run.
  final List<String> initialRecent;

  /// Suggestions are server-owned content. Production and live callers keep
  /// this empty until the backend supplies an approved list; QA may pass a
  /// visual fixture explicitly.
  final List<String> suggestions;

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final List<String> _recent = <String>[];

  bool get _canDirectRoom =>
      RegExp(r'^\d{4,18}$').hasMatch(_controller.text.trim());

  @override
  void initState() {
    super.initState();
    _recent.addAll(widget.initialRecent);
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
    return SocialPageScaffold(
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          const _SearchDiscoveryHero(),
          const SizedBox(height: 18),
          if (_canDirectRoom) ...<Widget>[
            SocialCard(
              padding: EdgeInsets.zero,
              radius: 18,
              onTap: _openRoomDirect,
              color: const Color(0xFFF0ECFF),
              child: ListTile(
                leading: const Icon(
                  Icons.meeting_room_outlined,
                  color: AppColors.primary,
                ),
                title: Text('直达房间 ${_controller.text.trim()}'),
                subtitle: const Text('校验成功后直接进入，不展示普通中间页'),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
            const SizedBox(height: 18),
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
          if (widget.suggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            Text('你可能想找', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String item in widget.suggestions)
                  SocialPill(
                    label: item,
                    icon: Icons.auto_awesome_rounded,
                    onTap: () {
                      _controller.text = item;
                      _search();
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text('搜索范围', style: Theme.of(context).textTheme.titleMedium),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: SocialColors.brandGradient,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchDiscoveryHero extends StatelessWidget {
  const _SearchDiscoveryHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF7768F4),
            Color(0xFF9B78F4),
            Color(0xFFFF99BE),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x305E4ACD),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: const Stack(
        children: <Widget>[
          Positioned(
            right: -4,
            top: -10,
            child: Icon(
              Icons.travel_explore_rounded,
              size: 92,
              color: Color(0x29FFFFFF),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '找到此刻同频的人',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                '搜索房间、用户或输入房间号直达',
                style: TextStyle(color: Color(0xE8FFFFFF), fontSize: 11),
              ),
              Spacer(),
              Row(
                children: <Widget>[
                  Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 15),
                  SizedBox(width: 5),
                  Text(
                    '实时房间正在发生',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
