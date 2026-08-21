import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_repository.dart';
import 'package:voice_social_app/features/room/presentation/room_deep_link_page.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';

class DiscoveryFeedPage extends StatefulWidget {
  const DiscoveryFeedPage({super.key});

  @override
  State<DiscoveryFeedPage> createState() => _DiscoveryFeedPageState();
}

class _DiscoveryFeedPageState extends State<DiscoveryFeedPage>
    with AutomaticKeepAliveClientMixin<DiscoveryFeedPage> {
  final ScrollController _scrollController = ScrollController();
  final List<DynamicPost> _posts = <DynamicPost>[];
  DynamicCategory _category = DynamicCategory.all;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;
  DynamicRepository? _repositoryInstance;

  DynamicRepository get _repository => _repositoryInstance!;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repositoryInstance != null) {
      return;
    }
    _repositoryInstance = AppDependencyScope.of(context).dynamicRepository;
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 320 &&
        _hasMore &&
        !_loadingMore) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final int requestedPage = reset ? 1 : _page + 1;
      final PagedResult<DynamicPost> result = await _repository.fetchFeed(
        category: _category,
        page: requestedPage,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _posts.clear();
        }
        for (final DynamicPost post in result.items) {
          final int existing = _posts.indexWhere(
            (DynamicPost item) => item.id == post.id,
          );
          if (existing >= 0) {
            _posts[existing] = post;
          } else {
            _posts.add(post);
          }
        }
        _page = requestedPage;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _openPost(DynamicPost post) async {
    final DynamicPost? updated = await Navigator.of(context).push<DynamicPost>(
      MaterialPageRoute<DynamicPost>(
        builder: (BuildContext context) => DynamicDetailPage(postId: post.id),
      ),
    );
    if (!mounted) {
      return;
    }
    if (updated == null) {
      await _load(reset: true);
      return;
    }
    final int index = _posts.indexWhere(
      (DynamicPost item) => item.id == updated.id,
    );
    if (index >= 0) {
      setState(() => _posts[index] = updated);
    }
  }

  Future<void> _publish() async {
    final DynamicPost? post = await Navigator.of(context).push<DynamicPost>(
      MaterialPageRoute<DynamicPost>(
        builder: (BuildContext context) => const PublishDynamicPage(),
      ),
    );
    if (post != null && mounted) {
      setState(() => _posts.insert(0, post));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SocialPageScaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverAppBar(
                floating: true,
                pinned: true,
                title: const Text('发现'),
                actions: <Widget>[
                  IconButton(
                    tooltip: '排行榜',
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => const RankingPage(),
                      ),
                    ),
                    icon: const Icon(Icons.emoji_events_outlined),
                  ),
                  IconButton(
                    tooltip: '社交经营',
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            const CommunityHubPage(),
                      ),
                    ),
                    icon: const Icon(Icons.groups_2_outlined),
                  ),
                  IconButton(
                    tooltip: '发布动态',
                    onPressed: _publish,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(54),
                  child: SizedBox(
                    height: 54,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      itemCount: DynamicCategory.values.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final DynamicCategory category =
                            DynamicCategory.values[index];
                        return ChoiceChip(
                          label: Text(category.label),
                          selected: _category == category,
                          onSelected: (bool selected) {
                            if (!selected || _category == category) {
                              return;
                            }
                            setState(() => _category = category);
                            _load(reset: true);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _posts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _FeedError(
                    message: _error!,
                    onRetry: () => _load(reset: true),
                  ),
                )
              else if (_posts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _FeedEmpty(onPublish: _publish),
                )
              else ...<Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                  sliver: SliverList.separated(
                    itemCount: _posts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (BuildContext context, int index) {
                      final DynamicPost post = _posts[index];
                      return DynamicPostCard(
                        post: post,
                        onOpen: () => _openPost(post),
                        onLike: () async {
                          final DynamicPost updated = await _repository
                              .toggleLike(post.id);
                          if (mounted) {
                            setState(() => _posts[index] = updated);
                          }
                        },
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Center(
                      child: _loadingMore
                          ? const CircularProgressIndicator()
                          : Text(
                              _hasMore ? '继续上滑加载' : '已经看完了',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _publish,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('发布'),
      ),
    );
  }
}

class DynamicDetailPage extends StatefulWidget {
  const DynamicDetailPage({required this.postId, super.key});

  final String postId;

  @override
  State<DynamicDetailPage> createState() => _DynamicDetailPageState();
}

class _DynamicDetailPageState extends State<DynamicDetailPage> {
  final TextEditingController _commentController = TextEditingController();
  DynamicPost? _post;
  final List<DynamicComment> _comments = <DynamicComment>[];
  DynamicComment? _replyingTo;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  DynamicRepository get _repository =>
      AppDependencyScope.of(context).dynamicRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_post == null && _loading) {
      _load();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchPost(widget.postId),
        _repository.fetchComments(dynamicId: widget.postId),
      ]);
      if (!mounted) {
        return;
      }
      final DynamicPost post = result[0] as DynamicPost;
      final PagedResult<DynamicComment> comments =
          result[1] as PagedResult<DynamicComment>;
      setState(() {
        _post = post;
        _comments
          ..clear()
          ..addAll(comments.items);
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _submitComment() async {
    if (_submitting) {
      return;
    }
    final String content = _commentController.text.trim();
    if (content.isEmpty) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final DynamicComment comment = await _repository.addComment(
        dynamicId: widget.postId,
        content: content,
        replyToUserId: _replyingTo?.author.userId,
        replyToCommentId: _replyingTo?.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _comments.insert(0, comment);
        _post = _post?.copyWith(commentCount: (_post?.commentCount ?? 0) + 1);
        _commentController.clear();
        _replyingTo = null;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除动态？'),
        content: const Text('删除后正文和评论入口将不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _repository.deletePost(widget.postId);
      if (mounted) {
        Navigator.of(context).pop<DynamicPost>();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DynamicPost? post = _post;
    final int currentUserId =
        AppDependencyScope.of(context).sessionManager.session?.userId ?? 0;
    return SocialPageScaffold(
      appBar: AppBar(
        title: const Text('动态详情'),
        actions: <Widget>[
          if (post?.author.userId == currentUserId)
            IconButton(
              tooltip: '删除动态',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _FeedError(message: _error!, onRetry: _load)
          : post == null
          ? const Center(child: Text('动态不可用'))
          : Column(
              children: <Widget>[
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                      children: <Widget>[
                        DynamicPostCard(
                          post: post,
                          onOpen: () {},
                          onLike: () async {
                            final DynamicPost updated = await _repository
                                .toggleLike(post.id);
                            if (mounted) {
                              setState(() => _post = updated);
                            }
                          },
                          expanded: true,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '评论 ${post.commentCount}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        if (_comments.isEmpty)
                          const _CommentEmpty()
                        else
                          for (final DynamicComment comment in _comments)
                            _CommentTile(
                              comment: comment,
                              onReply: () => setState(() {
                                _replyingTo = comment;
                                _commentController.selection =
                                    TextSelection.fromPosition(
                                      TextPosition(
                                        offset: _commentController.text.length,
                                      ),
                                    );
                              }),
                            ),
                      ],
                    ),
                  ),
                ),
                Material(
                  color: Colors.white.withValues(alpha: 0.94),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (_replyingTo != null)
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '回复 ${_replyingTo!.author.nickname}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                                IconButton(
                                  tooltip: '取消回复',
                                  onPressed: () =>
                                      setState(() => _replyingTo = null),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  minLines: 1,
                                  maxLines: 4,
                                  maxLength: 200,
                                  decoration: InputDecoration(
                                    hintText: _replyingTo == null
                                        ? '说点真实的想法…'
                                        : '回复 ${_replyingTo!.author.nickname}',
                                    counterText: '',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                tooltip: '发送评论',
                                onPressed: _submitting ? null : _submitComment,
                                icon: _submitting
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class PublishDynamicPage extends StatefulWidget {
  const PublishDynamicPage({super.key});

  @override
  State<PublishDynamicPage> createState() => _PublishDynamicPageState();
}

class _PublishDynamicPageState extends State<PublishDynamicPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  DynamicCategory _category = DynamicCategory.companionship;
  bool _submitting = false;

  @override
  void dispose() {
    _contentController.dispose();
    _topicController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final List<String> topics = _topicController.text
          .split(',')
          .map((String value) => value.trim())
          .where((String value) => value.isNotEmpty)
          .take(3)
          .toList(growable: false);
      final DynamicPost post = await AppDependencyScope.of(context)
          .dynamicRepository
          .publish(
            PublishDynamicRequest(
              content: _contentController.text,
              category: _category,
              topics: topics,
              location: _locationController.text,
            ),
          );
      if (mounted) {
        Navigator.of(context).pop(post);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool supportsImages = AppDependencyScope.of(
      context,
    ).dynamicRepository.supportsImagePublishing;
    return SocialPageScaffold(
      appBar: AppBar(
        title: const Text('发布动态'),
        actions: <Widget>[
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? '发布中…' : '发布'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            TextFormField(
              controller: _contentController,
              autofocus: true,
              minLines: 7,
              maxLines: 12,
              maxLength: 1000,
              decoration: const InputDecoration(
                hintText: '分享此刻真实发生的事…',
                alignLabelWithHint: true,
              ),
              validator: (String? value) {
                final String text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return '请输入动态内容';
                }
                if (text.length > 1000) {
                  return '动态内容不能超过 1000 个字';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            Text('内容类型', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final DynamicCategory category
                    in DynamicCategory.values.where(
                      (DynamicCategory item) => item != DynamicCategory.all,
                    ))
                  ChoiceChip(
                    label: Text(category.label),
                    selected: _category == category,
                    onSelected: (bool selected) {
                      if (selected) {
                        setState(() => _category = category);
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _topicController,
              decoration: const InputDecoration(
                labelText: '话题',
                hintText: '最多 3 个，用英文逗号分隔',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '位置（可选）',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 6),
            _InfoPanel(
              icon: supportsImages
                  ? Icons.photo_library_outlined
                  : Icons.cloud_off_outlined,
              text: supportsImages
                  ? '当前已支持上传原创图片。'
                  : '图片对象存储尚未接入，本阶段只发布真实文字内容，不生成占位图片。',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? '正在发布…' : '发布动态'),
            ),
          ],
        ),
      ),
    );
  }
}

class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  RankingBoard _board = RankingBoard.charm;
  RankingPeriod _period = RankingPeriod.day;
  RankingSnapshot? _snapshot;
  String? _error;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshot == null && _loading) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final RankingSnapshot value = await AppDependencyScope.of(
        context,
      ).dynamicRepository.fetchRanking(board: _board, period: _period);
      if (mounted) {
        setState(() {
          _snapshot = value;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  void _open(RankingEntry entry) {
    if (entry.roomId != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              RoomDeepLinkPage(input: entry.roomId!),
        ),
      );
    } else if (entry.userId != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              PublicProfilePage(userId: entry.userId!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('排行榜')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final RankingBoard board
                      in RankingBoard.values) ...<Widget>[
                    SocialPill(
                      label: board.label,
                      active: _board == board,
                      onTap: () {
                        if (_board == board) return;
                        setState(() => _board = board);
                        _load();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final RankingPeriod period
                      in RankingPeriod.values) ...<Widget>[
                    SocialPill(
                      label: period.label,
                      active: _period == period,
                      onTap: () {
                        if (_period == period) return;
                        setState(() => _period = period);
                        _load();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _FeedError(message: _error!, onRetry: _load)
            else if (_snapshot == null || _snapshot!.entries.isEmpty)
              const _InfoPanel(
                icon: Icons.leaderboard_outlined,
                text: '当前榜单暂无有效数据。',
              )
            else ...<Widget>[
              if (_snapshot!.countdownSeconds > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFFE9E5FF), Color(0xFFFFEAF2)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: SocialColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${_board.label} · 本期剩余 ${_duration(_snapshot!.countdownSeconds)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final RankingEntry entry in _snapshot!.entries)
                _RankingEntryCard(
                  entry: entry,
                  valueLabel: _compact(entry.value),
                  onTap: () => _open(entry),
                ),
              if (_snapshot!.selfEntry != null) ...<Widget>[
                const Divider(height: 28),
                Text('我的排名', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                _RankingEntryCard(
                  entry: _snapshot!.selfEntry!,
                  valueLabel: _compact(_snapshot!.selfEntry!.value),
                  emphasized: true,
                  onTap: () => _open(_snapshot!.selfEntry!),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _RankingEntryCard extends StatelessWidget {
  const _RankingEntryCard({
    required this.entry,
    required this.valueLabel,
    required this.onTap,
    this.emphasized = false,
  });

  final RankingEntry entry;
  final String valueLabel;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final bool podium = entry.rank <= 3;
    final Color accent = switch (entry.rank) {
      1 => const Color(0xFFFFB74F),
      2 => const Color(0xFF8BB8D7),
      3 => const Color(0xFFD79978),
      _ => SocialColors.primary,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SocialCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: podium ? 20 : 17,
        color: emphasized
            ? const Color(0xFFF0EDFF)
            : podium
            ? accent.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.82),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 30,
              child: Text(
                '${entry.rank}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: podium ? 20 : 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            RuntimeAvatar(
              seed: '${entry.userId ?? entry.roomId ?? entry.name}',
              size: podium ? 48 : 42,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (entry.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                valueLabel,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DynamicPostCard extends StatelessWidget {
  const DynamicPostCard({
    required this.post,
    required this.onOpen,
    required this.onLike,
    this.expanded = false,
    super.key,
  });

  final DynamicPost post;
  final VoidCallback onOpen;
  final Future<void> Function() onLike;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return SocialCard(
      padding: EdgeInsets.zero,
      radius: 22,
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                RuntimeAvatar(seed: '${post.author.userId}', size: 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        post.author.nickname,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        <String>[
                          post.createdAt,
                          if (post.location.isNotEmpty) post.location,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (post.tags.isNotEmpty)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(post.tags.first),
                  ),
              ],
            ),
            const SizedBox(height: 13),
            Text(
              post.content,
              maxLines: expanded ? null : 6,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (post.topics.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  for (final String topic in post.topics)
                    Text(
                      '#$topic',
                      style: const TextStyle(color: SocialColors.primary),
                    ),
                ],
              ),
            ],
            if (post.images.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _ImageEvidence(images: post.images),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: onLike,
                  icon: Icon(
                    post.isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: post.isLiked ? SocialColors.secondary : null,
                  ),
                  label: Text('${post.likeCount}'),
                ),
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: Text('${post.commentCount}'),
                ),
                const Spacer(),
                if (post.unlockChat)
                  const Tooltip(
                    message: '互动后可建立后续社交关系',
                    child: Icon(
                      Icons.lock_open_rounded,
                      size: 18,
                      color: SocialColors.success,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageEvidence extends StatelessWidget {
  const _ImageEvidence({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: SocialColors.cardSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Text(
        '该动态包含 ${images.length} 张已发布图片',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onReply});

  final DynamicComment comment;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onReply,
        leading: RuntimeAvatar(seed: '${comment.author.userId}', size: 42),
        title: Row(
          children: <Widget>[
            Expanded(child: Text(comment.author.nickname)),
            Text(
              comment.createdAt,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        subtitle: Text(
          comment.replyToNickname == null
              ? comment.content
              : '回复 ${comment.replyToNickname}：${comment.content}',
        ),
        trailing: const Icon(Icons.reply_rounded, size: 18),
      ),
    );
  }
}

class _CommentEmpty extends StatelessWidget {
  const _CommentEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 34),
      child: Center(child: Text('还没有评论，留下第一条真实回应吧')),
    );
  }
}

class _FeedError extends StatelessWidget {
  const _FeedError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 44),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty({required this.onPublish});

  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.auto_awesome_outlined, size: 46),
            const SizedBox(height: 14),
            const Text('这个分类暂时没有动态'),
            const SizedBox(height: 6),
            Text(
              '发布真实内容后，会按当前分类出现在动态流中。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPublish, child: const Text('发布动态')),
          ],
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SocialColors.card,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: SocialColors.accent),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

String _messageFor(Object error) =>
    error is ApiException ? error.message : '操作失败，请稍后重试';

String _compact(num value) {
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(value % 10000 == 0 ? 0 : 1)}万';
  }
  return value.toString();
}

String _duration(int seconds) {
  final int hours = seconds ~/ 3600;
  final int minutes = (seconds % 3600) ~/ 60;
  return hours > 0 ? '$hours 小时 $minutes 分' : '$minutes 分钟';
}
