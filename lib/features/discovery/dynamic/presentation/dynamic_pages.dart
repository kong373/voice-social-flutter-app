import 'package:flutter/material.dart';
import '../../../../core/media/media_models.dart';
import '../../../media/image_widgets.dart';
import '../../../media/app_image_media_host.dart';
import '../domain/comment_mutations.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_request_id.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_repository.dart';
import 'package:voice_social_app/features/account/presentation/user_avatar_view.dart';
import 'package:voice_social_app/features/room/presentation/room_deep_link_page.dart';
import 'package:voice_social_app/features/social/presentation/social_pages.dart';
import 'package:voice_social_app/shared/time_format.dart';

class DiscoveryFeedPage extends StatefulWidget {
  const DiscoveryFeedPage({this.repository, super.key});

  @visibleForTesting
  final DynamicRepository? repository;

  @override
  State<DiscoveryFeedPage> createState() => _DiscoveryFeedPageState();
}

class _DiscoveryFeedPageState extends State<DiscoveryFeedPage>
    with AutomaticKeepAliveClientMixin<DiscoveryFeedPage> {
  AppImageMediaHost? _mediaHost;
  (int, int)? _readIdentity;
  void _mediaIdentityChanged() {
    final identity = _mediaHost?.identity;
    if (!mounted || identity == _readIdentity) return;
    _readIdentity = identity;
    _loadRequestId++;
    _publishingRequestId++;
    setState(() {
      _posts.clear();
      _hasMore = false;
      _loading = false;
      _loadingMore = false;
      _publishing = false;
      _likeInFlight.clear();
      _likeRequestIds.clear();
      _pendingLikeIntents.clear();
      _error = '账号已变化，请重新加载动态';
    });
  }

  final ScrollController _scrollController = ScrollController();
  final List<DynamicPost> _posts = <DynamicPost>[];
  DynamicCategory _category = DynamicCategory.all;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _loadRequestId = 0;
  int _publishingRequestId = 0;
  bool _publishing = false;
  String? _error;
  DynamicRepository? _repositoryInstance;
  final Set<String> _likeInFlight = <String>{};
  final Map<String, int> _likeRequestIds = <String, int>{};
  final Map<String, _PendingDynamicLikeIntent> _pendingLikeIntents =
      <String, _PendingDynamicLikeIntent>{};

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
    _repositoryInstance =
        widget.repository ?? AppDependencyScope.of(context).dynamicRepository;
    _mediaHost = imageHostOf(context);
    _readIdentity = _mediaHost?.identity;
    _mediaHost?.addListener(_mediaIdentityChanged);
    _load(reset: true);
  }

  @override
  void dispose() {
    _mediaHost?.removeListener(_mediaIdentityChanged);
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
    final int requestId = ++_loadRequestId;
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
      if (!mounted || requestId != _loadRequestId) {
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
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _toggleLike(DynamicPost post) async {
    if (_likeInFlight.contains(post.id)) {
      return;
    }
    final int feedRequestId = _loadRequestId;
    final _PendingDynamicLikeIntent intent = _resolveLikeIntent(post);
    final int requestId = (_likeRequestIds[post.id] ?? 0) + 1;
    _likeRequestIds[post.id] = requestId;
    _likeInFlight.add(post.id);
    if (mounted) {
      setState(() {});
    }
    try {
      final DynamicPost updated = await _repository.toggleLike(
        post.id,
        liked: intent.desiredLiked,
        requestId: intent.requestId,
      );
      if (!mounted ||
          feedRequestId != _loadRequestId ||
          requestId != _likeRequestIds[post.id]) {
        return;
      }
      final int index = _posts.indexWhere(
        (DynamicPost item) => item.id == post.id,
      );
      if (index >= 0) {
        setState(() => _posts[index] = updated);
      }
      _pendingLikeIntents.remove(post.id);
    } catch (error) {
      if (mounted &&
          feedRequestId == _loadRequestId &&
          requestId == _likeRequestIds[post.id]) {
        if (!shouldRetainDynamicWriteRequest(error)) {
          _pendingLikeIntents.remove(post.id);
        }
        _showOperationError(error);
      }
    } finally {
      if (requestId == _likeRequestIds[post.id]) {
        _likeInFlight.remove(post.id);
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  _PendingDynamicLikeIntent _resolveLikeIntent(DynamicPost post) {
    final bool desiredLiked = !post.isLiked;
    final _PendingDynamicLikeIntent? existing = _pendingLikeIntents[post.id];
    if (existing != null && existing.desiredLiked == desiredLiked) {
      return existing;
    }
    final _PendingDynamicLikeIntent intent = _PendingDynamicLikeIntent(
      desiredLiked: desiredLiked,
      requestId: newDynamicRequestId('dynamic-like'),
    );
    _pendingLikeIntents[post.id] = intent;
    return intent;
  }

  Future<void> _openPost(DynamicPost post) async {
    final int feedRequestId = _loadRequestId;
    final DynamicPost? updated = await Navigator.of(context).push<DynamicPost>(
      MaterialPageRoute<DynamicPost>(
        builder: (BuildContext context) =>
            DynamicDetailPage(postId: post.id, repository: widget.repository),
      ),
    );
    if (!mounted || feedRequestId != _loadRequestId) {
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
    if (_publishing) {
      return;
    }
    final int requestId = ++_publishingRequestId;
    setState(() => _publishing = true);
    try {
      final DynamicPost? post = await Navigator.of(context).push<DynamicPost>(
        MaterialPageRoute<DynamicPost>(
          builder: (BuildContext context) =>
              PublishDynamicPage(repository: widget.repository),
        ),
      );
      if (post != null && mounted && requestId == _publishingRequestId) {
        // Invalidate an older feed response so it cannot erase the newly
        // published server-authoritative item when the page is refreshed.
        _loadRequestId += 1;
        setState(() {
          _posts.insert(0, post);
          // The invalidated load no longer owns either spinner. Leaving
          // _loading true here strands the feed behind a never-completing
          // stale request after a successful publish.
          _loading = false;
          _loadingMore = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && requestId == _publishingRequestId) {
        _showOperationError(error);
      }
    } finally {
      if (mounted && requestId == _publishingRequestId) {
        setState(() => _publishing = false);
      }
    }
  }

  void _showOperationError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_messageFor(error))));
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
                    onPressed: _publishing ? null : _publish,
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
                if (_error != null)
                  SliverToBoxAdapter(
                    child: _FeedError(
                      message: _error!,
                      onRetry: () => _load(reset: true),
                    ),
                  ),
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
                        onLike: () => _toggleLike(post),
                        likeInFlight: _likeInFlight.contains(post.id),
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
        onPressed: _publishing ? null : _publish,
        icon: const Icon(Icons.edit_rounded),
        label: const Text('发布'),
      ),
    );
  }
}

class DynamicDetailPage extends StatefulWidget {
  const DynamicDetailPage({
    required this.postId,
    this.repository,
    this.currentUserId,
    super.key,
  });

  final String postId;

  @visibleForTesting
  final DynamicRepository? repository;

  @visibleForTesting
  final int? currentUserId;

  @override
  State<DynamicDetailPage> createState() => _DynamicDetailPageState();
}

class _DynamicDetailPageState extends State<DynamicDetailPage> {
  CommentActions? _observedActions;
  (int, int)? _observedIdentity;
  BuildContext? _commentDialog;
  bool _commentDeleting = false;
  bool _commentConfirming = false;
  CommentActions? get _actions =>
      _repository is CommentActions ? _repository as CommentActions : null;
  PendingCommentMutation? get _pendingMutation =>
      _actions?.pendingCommentMutation;
  bool get _commentFrozen =>
      _submitting ||
      _commentDeleting ||
      _commentConfirming ||
      _pendingMutation != null;

  void _restoreCommentDraft() {
    final pending = _pendingMutation;
    if (pending?.kind == 'add' && pending?.dynamicId == widget.postId) {
      _commentController.text = pending!.body['content'] as String;
    }
  }

  void _onCommentIdentity() {
    final identity = _actions?.commentIdentity;
    if (!mounted || identity == _observedIdentity) return;
    _observedIdentity = identity;
    final dialog = _commentDialog;
    if (dialog != null &&
        dialog.mounted &&
        ModalRoute.of(dialog)?.isCurrent == true)
      Navigator.of(dialog).pop(false);
    _loadRequestId++;
    _commentRequestId++;
    _likeRequestId++;
    setState(() {
      _post = null;
      _comments.clear();
      _replyingTo = null;
      _commentController.clear();
      _pendingCommentIntent = null;
      _pendingLikeIntent = null;
      _submitting = false;
      _commentDeleting = false;
      _commentConfirming = false;
      _likeInFlight = false;
      _error = null;
      _restoreCommentDraft();
    });
    if (identity != null && identity.$1 > 0) {
      _load();
    } else {
      setState(() {
        _loading = false;
        _error = '请登录后查看评论';
      });
    }
  }

  final TextEditingController _commentController = TextEditingController();
  DynamicPost? _post;
  final List<DynamicComment> _comments = <DynamicComment>[];
  DynamicComment? _replyingTo;
  bool _loading = true;
  bool _submitting = false;
  bool _likeInFlight = false;
  bool _deleteDialogOpen = false;
  bool _deleting = false;
  int _loadRequestId = 0;
  int _likeRequestId = 0;
  int _commentRequestId = 0;
  int _deleteRequestId = 0;
  String? _error;
  _PendingDynamicLikeIntent? _pendingLikeIntent;
  _PendingDynamicWriteIntent? _pendingCommentIntent;

  DynamicRepository get _repository =>
      widget.repository ?? AppDependencyScope.of(context).dynamicRepository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!identical(_observedActions, _actions)) {
      _observedActions?.commentIdentityChanges?.removeListener(
        _onCommentIdentity,
      );
      _observedActions = _actions;
      _observedIdentity = _actions?.commentIdentity;
      _observedActions?.commentIdentityChanges?.addListener(_onCommentIdentity);
      _restoreCommentDraft();
    }
    if (_post == null && _loading) {
      _load();
    }
  }

  @override
  void dispose() {
    _observedActions?.commentIdentityChanges?.removeListener(
      _onCommentIdentity,
    );
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final int requestId = ++_loadRequestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchPost(widget.postId),
        _repository.fetchComments(dynamicId: widget.postId),
      ]);
      if (!mounted || requestId != _loadRequestId) {
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
      if (mounted && requestId == _loadRequestId) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  Future<void> _submitComment() async {
    final pending = _pendingMutation;
    if (_submitting ||
        _commentDeleting ||
        _commentConfirming ||
        (pending != null &&
            (pending.kind != 'add' || pending.dynamicId != widget.postId))) {
      return;
    }
    final String content =
        pending?.body['content'] as String? ?? _commentController.text.trim();
    if (content.isEmpty) {
      return;
    }
    final int loadRequestId = _loadRequestId;
    final int requestId = ++_commentRequestId;
    final _PendingDynamicWriteIntent intent = _resolveCommentIntent(content);
    bool commentPersisted = false;
    setState(() => _submitting = true);
    try {
      await _repository.addComment(
        dynamicId: widget.postId,
        content: content,
        replyToUserId:
            pending?.body['replyToUserId'] as int? ??
            _replyingTo?.author.userId,
        replyToCommentId:
            pending?.body['parentCommentId'] as String? ?? _replyingTo?.id,
        requestId: pending?.requestId ?? intent.requestId,
      );
      if (!mounted ||
          loadRequestId != _loadRequestId ||
          requestId != _commentRequestId) {
        return;
      }
      commentPersisted = true;
      _pendingCommentIntent = null;
      setState(() {
        _commentController.clear();
        _replyingTo = null;
      });

      // The server owns comment order and the aggregate counter. Re-read both
      // resources after a successful write instead of manufacturing a local
      // first-row comment or incrementing a potentially stale counter.
      final List<Object> result = await Future.wait<Object>(<Future<Object>>[
        _repository.fetchPost(widget.postId),
        _repository.fetchComments(dynamicId: widget.postId),
      ]);
      if (!mounted ||
          loadRequestId != _loadRequestId ||
          requestId != _commentRequestId) {
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
      });
    } catch (error) {
      if (mounted &&
          loadRequestId == _loadRequestId &&
          requestId == _commentRequestId) {
        if (commentPersisted) {
          _showOperationError(
            const ApiException(
              kind: ApiFailureKind.network,
              message: '评论已提交，但最新列表刷新失败，请稍后重试',
            ),
          );
        } else {
          if (!shouldRetainDynamicWriteRequest(error)) {
            _pendingCommentIntent = null;
          }
          _showOperationError(error);
        }
      }
    } finally {
      if (mounted && requestId == _commentRequestId) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _deleteComment(DynamicComment? comment) async {
    final actions = _actions;
    final pending = _pendingMutation;
    if (actions == null ||
        _submitting ||
        _commentDeleting ||
        _commentConfirming ||
        (pending != null &&
            (pending.kind != 'delete' || pending.dynamicId != widget.postId)))
      return;
    if (pending == null && (comment == null || !comment.canDelete)) return;
    final identity = actions.commentIdentity;
    final target = pending?.body['commentId'] as String? ?? comment!.id;
    if (pending == null) {
      setState(() => _commentConfirming = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) {
          _commentDialog = dialog;
          return AlertDialog(
            title: const Text('删除这条评论？'),
            content: const Text('仅删除该评论，已有回复会保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('确认删除评论'),
              ),
            ],
          );
        },
      );
      _commentDialog = null;
      if (!mounted || identity != actions.commentIdentity) return;
      setState(() => _commentConfirming = false);
      if (confirmed != true) return;
    }
    setState(() => _commentDeleting = true);
    bool persisted = false;
    try {
      await actions.deleteComment(
        dynamicId: widget.postId,
        commentId: target,
        requestId: pending?.requestId,
      );
      if (!mounted || identity != actions.commentIdentity) return;
      persisted = true;
      _replyingTo = null;
      await _load();
    } catch (error) {
      if (mounted && identity == actions.commentIdentity) {
        _showOperationError(error);
        if (_pendingMutation == null && !persisted) await _load();
      }
    } finally {
      if (mounted && identity == actions.commentIdentity)
        setState(() => _commentDeleting = false);
    }
  }

  Future<void> _toggleLike() async {
    if (_likeInFlight || _post == null) {
      return;
    }
    final int loadRequestId = _loadRequestId;
    final int requestId = ++_likeRequestId;
    final _PendingDynamicLikeIntent intent = _resolveDetailLikeIntent(_post!);
    _likeInFlight = true;
    setState(() {});
    try {
      final DynamicPost updated = await _repository.toggleLike(
        widget.postId,
        liked: intent.desiredLiked,
        requestId: intent.requestId,
      );
      if (!mounted ||
          loadRequestId != _loadRequestId ||
          requestId != _likeRequestId) {
        return;
      }
      _pendingLikeIntent = null;
      setState(() => _post = updated);
    } catch (error) {
      if (mounted &&
          loadRequestId == _loadRequestId &&
          requestId == _likeRequestId) {
        if (!shouldRetainDynamicWriteRequest(error)) {
          _pendingLikeIntent = null;
        }
        _showOperationError(error);
      }
    } finally {
      if (requestId == _likeRequestId) {
        _likeInFlight = false;
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  _PendingDynamicLikeIntent _resolveDetailLikeIntent(DynamicPost post) {
    final bool desiredLiked = !post.isLiked;
    final _PendingDynamicLikeIntent? existing = _pendingLikeIntent;
    if (existing != null && existing.desiredLiked == desiredLiked) {
      return existing;
    }
    final _PendingDynamicLikeIntent intent = _PendingDynamicLikeIntent(
      desiredLiked: desiredLiked,
      requestId: newDynamicRequestId('dynamic-like'),
    );
    _pendingLikeIntent = intent;
    return intent;
  }

  _PendingDynamicWriteIntent _resolveCommentIntent(String content) {
    final _PendingDynamicWriteIntent candidate = _PendingDynamicWriteIntent(
      requestKey:
          '${widget.postId}|${content.trim()}|${_replyingTo?.author.userId ?? ''}|${_replyingTo?.id ?? ''}',
      requestId: '',
    );
    final _PendingDynamicWriteIntent? existing = _pendingCommentIntent;
    if (existing != null && existing.requestKey == candidate.requestKey) {
      return existing;
    }
    final _PendingDynamicWriteIntent intent = _PendingDynamicWriteIntent(
      requestKey: candidate.requestKey,
      requestId: newDynamicRequestId('dynamic-comment'),
    );
    _pendingCommentIntent = intent;
    return intent;
  }

  Future<void> _delete() async {
    if (_deleteDialogOpen || _deleting) {
      return;
    }
    _deleteDialogOpen = true;
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
    _deleteDialogOpen = false;
    if (confirmed != true || !mounted) {
      return;
    }
    final int requestId = ++_deleteRequestId;
    setState(() => _deleting = true);
    try {
      await _repository.deletePost(widget.postId);
      if (mounted && requestId == _deleteRequestId) {
        Navigator.of(context).pop<DynamicPost>();
      }
    } catch (error) {
      if (mounted && requestId == _deleteRequestId) {
        _showOperationError(error);
      }
    } finally {
      if (mounted && requestId == _deleteRequestId) {
        setState(() => _deleting = false);
      }
    }
  }

  void _showOperationError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_messageFor(error))));
  }

  @override
  Widget build(BuildContext context) {
    final DynamicPost? post = _post;
    final int currentUserId =
        widget.currentUserId ??
        AppDependencyScope.of(context).sessionManager.session?.userId ??
        0;
    return SocialPageScaffold(
      appBar: AppBar(
        title: const Text('动态详情'),
        actions: <Widget>[
          if (post?.author.userId == currentUserId)
            IconButton(
              tooltip: '删除动态',
              onPressed: _deleteDialogOpen || _deleting ? null : _delete,
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
                          onLike: _toggleLike,
                          likeInFlight: _likeInFlight,
                          expanded: true,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '评论 ${post.commentCount}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: SocialColors.textPrimary),
                        ),
                        const SizedBox(height: 10),
                        if (_comments.isEmpty)
                          const _CommentEmpty()
                        else
                          for (final DynamicComment comment in _comments)
                            _CommentTile(
                              comment: comment,
                              onDelete:
                                  comment.canDelete &&
                                      !_commentFrozen &&
                                      _actions != null
                                  ? () => _deleteComment(comment)
                                  : null,
                              onReply: !comment.canReply || _commentFrozen
                                  ? null
                                  : () => setState(() {
                                      _replyingTo = comment;
                                      _commentController.selection =
                                          TextSelection.fromPosition(
                                            TextPosition(
                                              offset: _commentController
                                                  .text
                                                  .length,
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
                          if (_pendingMutation != null)
                            Column(
                              children: [
                                const Text('评论操作结果未确认，原请求已保留。请先处理原操作。'),
                                if (_pendingMutation!.dynamicId ==
                                        widget.postId &&
                                    _pendingMutation!.kind == 'delete')
                                  TextButton(
                                    onPressed: _commentDeleting
                                        ? null
                                        : () => _deleteComment(null),
                                    child: const Text('重试原删除'),
                                  ),
                              ],
                            ),
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
                                  onPressed: _commentFrozen
                                      ? null
                                      : () =>
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
                                  enabled: !_commentFrozen,
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
                                onPressed:
                                    _submitting ||
                                        _commentDeleting ||
                                        _commentConfirming ||
                                        (_pendingMutation != null &&
                                            (_pendingMutation!.kind != 'add' ||
                                                _pendingMutation!.dynamicId !=
                                                    widget.postId))
                                    ? null
                                    : _submitComment,
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
  const PublishDynamicPage({this.repository, super.key});

  @visibleForTesting
  final DynamicRepository? repository;

  @override
  State<PublishDynamicPage> createState() => _PublishDynamicPageState();
}

class _PublishDynamicPageState extends State<PublishDynamicPage> {
  ImagePageBinding? _media;
  bool _mediaInitialized = false;
  bool get _identityCurrent => _media?.current ?? true;
  bool get _formLocked => _submitting || (_media?.draft.locked ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mediaInitialized) return;
    _mediaInitialized = true;
    final host = imageHostOf(context);
    if (host == null || !host.enabled || host.identity.$1 <= 0) return;
    _media = ImagePageBinding(
      host,
      'dynamic:publish',
      MediaPurpose.dynamicImage,
    );
    final fields = _media!.draft.fields;
    _contentController.text = fields['content'] ?? '';
    _topicController.text = fields['topics'] ?? '';
    _locationController.text = fields['location'] ?? '';
    _category = DynamicCategory.values.firstWhere(
      (v) => v.name == fields['category'],
      orElse: () => DynamicCategory.companionship,
    );
    _contentController.addListener(_saveMediaDraft);
    _topicController.addListener(_saveMediaDraft);
    _locationController.addListener(_saveMediaDraft);
    _media!.addListener(_mediaChanged);
  }

  void _saveMediaDraft() {
    if (!_identityCurrent || (_media?.draft.locked ?? true)) return;
    _media!.draft.fields.addAll({
      'content': _contentController.text,
      'topics': _topicController.text,
      'location': _locationController.text,
      'category': _category.name,
    });
  }

  void _mediaChanged() {
    if (mounted) setState(() {});
  }

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  DynamicCategory _category = DynamicCategory.companionship;
  bool _submitting = false;
  int _submitRequestId = 0;
  _PendingDynamicWriteIntent? _pendingPublishIntent;

  DynamicRepository get _repository =>
      widget.repository ?? AppDependencyScope.of(context).dynamicRepository;

  @override
  void dispose() {
    _media?.dispose();
    _contentController.dispose();
    _topicController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_identityCurrent ||
        _submitting ||
        !_formKey.currentState!.validate()) {
      return;
    }
    final List<String> topics = _topicController.text
        .split(',')
        .map((String value) => value.trim())
        .where((String value) => value.isNotEmpty)
        .take(3)
        .toList(growable: false);
    final _PendingDynamicWriteIntent intent = _resolvePublishIntent(topics);
    final int requestId = ++_submitRequestId;
    setState(() => _submitting = true);
    try {
      final binding = _media;
      final content = _contentController.text;
      final category = _category;
      final location = _locationController.text;
      Future<DynamicPost> send(String key, List<MediaReference> images) =>
          _repository.publish(
            PublishDynamicRequest(
              content: content,
              category: category,
              topics: topics,
              location: location,
              media: images,
            ),
            requestId: key,
          );
      final post = binding == null
          ? await send(intent.requestId, const [])
          : await binding.host.submit(binding.draft, {
              'content': content.trim(),
              'category': category.name,
              'topics': topics,
              'location': location.trim(),
            }, send);
      if (mounted && _identityCurrent && requestId == _submitRequestId) {
        binding?.host.acknowledge(binding.draft);
        _pendingPublishIntent = null;
        Navigator.of(context).pop(post);
      }
    } catch (error) {
      if (mounted && _identityCurrent) {
        if (!shouldRetainDynamicWriteRequest(error)) {
          _pendingPublishIntent = null;
        }
        _showOperationError(context, error);
      }
    } finally {
      if (mounted && _identityCurrent && requestId == _submitRequestId) {
        setState(() => _submitting = false);
      }
    }
  }

  _PendingDynamicWriteIntent _resolvePublishIntent(List<String> topics) {
    final String requestKey =
        '${_contentController.text.trim()}|${_category.name}|${topics.join(',')}|${_locationController.text.trim()}';
    final _PendingDynamicWriteIntent? existing = _pendingPublishIntent;
    if (existing != null && existing.requestKey == requestKey) {
      return existing;
    }
    final _PendingDynamicWriteIntent intent = _PendingDynamicWriteIntent(
      requestKey: requestKey,
      requestId: newDynamicRequestId('dynamic-publish'),
    );
    _pendingPublishIntent = intent;
    return intent;
  }

  @override
  Widget build(BuildContext context) {
    final bool supportsImages =
        _repository.supportsImagePublishing && _media != null;
    if (!_identityCurrent)
      return SocialPageScaffold(
        appBar: AppBar(title: const Text('发布动态')),
        body: const Center(child: Text('账号已变化，请重新打开页面；原账号未知提交仍保留')),
      );
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
              enabled: !_formLocked,
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
                if (text.isEmpty && (_media?.draft.images.isEmpty ?? true)) {
                  return '请输入动态内容或选择图片';
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
                      if (selected && !_formLocked) {
                        setState(() => _category = category);
                        _saveMediaDraft();
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _topicController,
              enabled: !_formLocked,
              decoration: const InputDecoration(
                labelText: '话题',
                hintText: '最多 3 个，用英文逗号分隔',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              enabled: !_formLocked,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '位置（可选）',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 6),
            if (supportsImages)
              ImageAttachmentEditor(binding: _media!)
            else
              _InfoPanel(
                icon: supportsImages
                    ? Icons.photo_library_outlined
                    : Icons.cloud_off_outlined,
                text: supportsImages ? '图片需由服务端确认就绪。' : '当前环境仅可发布文字，不生成虚假图片回执。',
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
  const RankingPage({this.repository, super.key});

  @visibleForTesting
  final DynamicRepository? repository;

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  final _scrollController = ScrollController();
  RankingBoard _board = RankingBoard.charm;
  RankingPeriod _period = RankingPeriod.day;
  int _page = 1;
  RankingSnapshot? _snapshot;
  String? _error;
  bool _loading = true;
  int _loadRequestId = 0;
  DynamicRepository? _repositoryInstance;
  RankingIdentity? _identity;
  (int, int)? _observedIdentity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(covariant RankingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    final repository =
        widget.repository ?? AppDependencyScope.of(context).dynamicRepository;
    if (identical(repository, _repositoryInstance)) return;
    _identity?.rankingIdentityChanges?.removeListener(_identityChanged);
    _repositoryInstance = repository;
    _identity = repository is RankingIdentity
        ? repository as RankingIdentity
        : null;
    _observedIdentity = _identity?.rankingIdentity;
    _identity?.rankingIdentityChanges?.addListener(_identityChanged);
    _page = 1;
    _load();
  }

  void _identityChanged() {
    final next = _identity?.rankingIdentity;
    if (!mounted || next == _observedIdentity) return;
    _observedIdentity = next;
    _page = 1;
    _load();
  }

  @override
  void dispose() {
    ++_loadRequestId;
    _identity?.rankingIdentityChanges?.removeListener(_identityChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final requestId = ++_loadRequestId;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    final identity = _identity?.rankingIdentity;
    final board = _board, period = _period;
    final page = _page;
    bool current() =>
        mounted &&
        requestId == _loadRequestId &&
        identity == _identity?.rankingIdentity;
    setState(() {
      _loading = true;
      _error = null;
      _snapshot = null;
    });
    try {
      if (identity != null && identity.$1 <= 0) {
        throw const ApiException(
          kind: ApiFailureKind.unauthorized,
          message: '请登录后查看排行榜',
        );
      }
      final value = await _repositoryInstance!.fetchRanking(
        board: board,
        period: period,
        page: page,
      );
      if (!current()) return;
      if (value.board != board ||
          value.period != (board.isGiftValue ? period : null) ||
          value.page != page ||
          value.pageSize != 20 ||
          value.entries.any(
            (entry) => board.isGiftValue
                ? entry.giftValueFen == null
                : entry.giftValueFen != null,
          )) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '排行榜响应与当前选择不一致',
        );
      }
      setState(() {
        _snapshot = value;
        _loading = false;
      });
    } catch (error) {
      if (current())
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
    }
  }

  void _open(RankingEntry entry) {
    if (entry.roomId != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RoomDeepLinkPage(input: entry.roomId!),
        ),
      );
    } else if (entry.userId != null) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PublicProfilePage(userId: entry.userId!),
        ),
      );
    }
  }

  String _beijing(DateTime value) {
    final date = value.toUtc().add(const Duration(hours: 8));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return SocialPageScaffold(
      appBar: AppBar(title: const Text('排行榜')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final board in productRankingBoards) ...[
                    SocialPill(
                      label: board.label,
                      active: _board == board,
                      onTap: () {
                        if (_board == board) return;
                        setState(() {
                          _board = board;
                          _page = 1;
                        });
                        _load();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_board.isGiftValue)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final period in RankingPeriod.values) ...[
                      SocialPill(
                        label: period.label,
                        active: _period == period,
                        onTap: () {
                          if (_period == period) return;
                          setState(() {
                            _period = period;
                            _page = 1;
                          });
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
            else if (snapshot != null) ...[
              if (!snapshot.serverAuthoritative)
                const Text('演示数据 · 非实时榜单', key: ValueKey('ranking-demo'))
              else if (snapshot.startInclusive != null &&
                  snapshot.endExclusive != null) ...[
                Text(
                  '北京时间 ${_beijing(snapshot.startInclusive!)} 至 ${_beijing(snapshot.endExclusive!)}（不含）',
                  key: const ValueKey('ranking-window'),
                ),
                Text('服务端更新：${_beijing(snapshot.serverNow!)} · 礼物总价值（人民币）'),
                const Text('同分先达到者优先 · 无奖励'),
                if (snapshot.excludedUnvaluedTransfers > 0)
                  Text(
                    '本期有 ${snapshot.excludedUnvaluedTransfers} 条历史礼物记录不可估值，未计入榜分',
                  ),
              ],
              const SizedBox(height: 12),
              if (snapshot.entries.isEmpty)
                const _InfoPanel(
                  icon: Icons.leaderboard_outlined,
                  text: '当前榜单暂无有效数据。',
                ),
              for (final entry in snapshot.entries)
                _RankingEntryCard(
                  entry: entry,
                  valueLabel: entry.displayValue,
                  emphasized: entry.isCurrentUser,
                  onTap: () => _open(entry),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    key: const ValueKey('ranking-previous'),
                    onPressed: snapshot.page > 1
                        ? () {
                            _page = snapshot.page - 1;
                            _load();
                          }
                        : null,
                    child: const Text('上一页'),
                  ),
                  Flexible(
                    child: Text(
                      '第 ${snapshot.page} 页 / 共 ${snapshot.pages} 页 · ${snapshot.total} 项',
                      key: const ValueKey('ranking-pagination'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('ranking-next'),
                    onPressed: snapshot.hasMore
                        ? () {
                            _page = snapshot.page + 1;
                            _load();
                          }
                        : null,
                    child: const Text('下一页'),
                  ),
                ],
              ),
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
            Flexible(
              flex: 2,
              child: Container(
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
    this.likeInFlight = false,
    super.key,
  });

  final DynamicPost post;
  final VoidCallback onOpen;
  final Future<void> Function() onLike;
  final bool expanded;
  final bool likeInFlight;

  @override
  Widget build(BuildContext context) {
    final DateTime now = _currentPresentationTime(context);
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
                UserAvatarView(
                  avatar: post.author.avatar,
                  userId: post.author.userId,
                  size: 42,
                  fallback: const _DynamicNeutralAvatar(),
                ),
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
                          formatMessageTimeText(post.createdAt, now),
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
            if (post.media.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              ControlledImages(media: post.media),
            ] else if (post.images.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _ImageEvidence(images: post.images),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: likeInFlight ? null : onLike,
                  icon: Icon(
                    likeInFlight
                        ? Icons.hourglass_top_rounded
                        : post.isLiked
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
  const _CommentTile({
    required this.comment,
    required this.onReply,
    this.onDelete,
  });

  final DynamicComment comment;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final DateTime now = _currentPresentationTime(context);
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onReply,
        leading: UserAvatarView(
          avatar: comment.author.avatar,
          userId: comment.author.userId,
          size: 42,
          fallback: const _DynamicNeutralAvatar(),
        ),
        title: Row(
          children: <Widget>[
            Expanded(child: Text(comment.author.nickname)),
            Text(
              formatMessageTimeText(comment.createdAt, now),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (comment.parentCommentPlaceholder.isNotEmpty)
              Text(comment.parentCommentPlaceholder),
            Text(
              comment.status != 'PUBLISHED'
                  ? ''
                  : comment.replyToNickname == null ||
                        comment.parentCommentPlaceholder.isNotEmpty
                  ? comment.content
                  : '回复 ${comment.replyToNickname}：${comment.content}',
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (comment.canReply)
              IconButton(
                tooltip: '回复评论',
                onPressed: onReply,
                icon: const Icon(Icons.reply_rounded, size: 18),
              ),
            if (comment.canDelete)
              IconButton(
                tooltip: '删除评论',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _DynamicNeutralAvatar extends StatelessWidget {
  const _DynamicNeutralAvatar();

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '头像不可用',
    child: SizedBox.square(
      key: const Key('dynamic-avatar-neutral'),
      dimension: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFE8E1EC),
          border: Border.all(color: const Color(0xFFD4C7DB), width: 2),
        ),
        child: const Icon(Icons.person_outline, color: Color(0xFF70647D)),
      ),
    ),
  );
}

DateTime _currentPresentationTime(BuildContext context) =>
    context
        .getInheritedWidgetOfExactType<AppDependencyScope>()
        ?.dependencies
        .currentTime() ??
    DateTime.now();

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

class _PendingDynamicLikeIntent {
  const _PendingDynamicLikeIntent({
    required this.desiredLiked,
    required this.requestId,
  });

  final bool desiredLiked;
  final String requestId;
}

class _PendingDynamicWriteIntent {
  const _PendingDynamicWriteIntent({
    required this.requestKey,
    required this.requestId,
  });

  final String requestKey;
  final String requestId;
}

void _showOperationError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(_messageFor(error))));
}
