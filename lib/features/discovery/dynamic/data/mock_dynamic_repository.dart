import 'dart:async';
import 'package:flutter/foundation.dart';
import '../domain/comment_mutations.dart';

import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_repository.dart';

class MockDynamicRepository
    with CommentMutationJournal
    implements DynamicRepository, RankingIdentity {
  MockDynamicRepository()
    : _posts = <DynamicPost>[
        const DynamicPost(
          id: 'dynamic-1001',
          author: DynamicAuthor(userId: 20001, nickname: '晚星'),
          content: '下班后终于松下来。今晚想听听大家最近遇到的温柔小事。',
          location: '武汉',
          tags: <String>['陪伴'],
          topics: <String>['下班后的松弛时刻'],
          likeCount: 28,
          commentCount: 3,
          isLiked: true,
          unlockChat: true,
          createdAt: '8 分钟前',
        ),
        const DynamicPost(
          id: 'dynamic-1002',
          author: DynamicAuthor(userId: 20002, nickname: '南风'),
          content: '整理了一份适合深夜听的轻音乐歌单，只在普通音乐主题房里一起安静聊天。',
          tags: <String>['音乐'],
          topics: <String>['深夜歌单'],
          likeCount: 16,
          commentCount: 1,
          createdAt: '36 分钟前',
        ),
        const DynamicPost(
          id: 'dynamic-1003',
          author: DynamicAuthor(userId: 20003, nickname: '阿岚'),
          content: '今天最开心的事情，是把拖了很久的计划真正开始做了。你今天完成了什么？',
          location: '杭州',
          tags: <String>['聊天'],
          topics: <String>['今天完成的一件事'],
          likeCount: 41,
          commentCount: 5,
          createdAt: '1 小时前',
        ),
      ],
      _comments = <String, List<DynamicComment>>{
        'dynamic-1001': <DynamicComment>[
          const DynamicComment(
            id: 'comment-1',
            dynamicId: 'dynamic-1001',
            author: DynamicAuthor(userId: 20004, nickname: '小满'),
            content: '今天同事帮我留了一杯热水，虽然很小，但很暖。',
            createdAt: '5 分钟前',
          ),
          const DynamicComment(
            id: 'comment-2',
            dynamicId: 'dynamic-1001',
            author: DynamicAuthor(userId: 20005, nickname: '鹿屿'),
            content: '回家路上看到晚霞，感觉一天没有白过。',
            createdAt: '3 分钟前',
          ),
        ],
      };

  final List<DynamicPost> _posts;
  final Map<String, List<DynamicComment>> _comments;
  int _postSequence = 2000;
  int _commentSequence = 100;
  final Set<String> _deletedComments = {};
  final Map<(int, String), DynamicComment> _commentReceipts = {};
  @override
  (int, int) get commentIdentity => (10001, 0);
  @override
  Listenable? get commentIdentityChanges => null;

  DynamicComment _projectComment(DynamicComment comment) {
    final deleted = _deletedComments.contains(comment.id);
    final parentDeleted = _deletedComments.contains(comment.replyToCommentId);
    final actor = commentIdentity.$1;
    return DynamicComment(
      id: comment.id,
      dynamicId: comment.dynamicId,
      author: comment.author,
      content: deleted ? '' : comment.content,
      createdAt: comment.createdAt,
      replyToCommentId: comment.replyToCommentId,
      replyToUserId: comment.replyToUserId,
      replyToNickname: parentDeleted ? null : comment.replyToNickname,
      status: deleted ? 'DELETED' : 'PUBLISHED',
      canReply: !deleted && actor > 0,
      canDelete:
          !deleted &&
          actor > 0 &&
          (comment.author.userId == actor ||
              _requirePost(comment.dynamicId).author.userId == actor),
      parentCommentStatus: parentDeleted
          ? 'DELETED'
          : comment.replyToCommentId == null
          ? 'NONE'
          : 'PUBLISHED',
      parentCommentPlaceholder: parentDeleted ? '该评论已删除' : '',
    );
  }

  @override
  Future<CommentDeletion> deleteComment({
    required String dynamicId,
    required String commentId,
    String? requestId,
  }) => commentMutation<CommentDeletion>(
    'delete',
    {'dynamicId': dynamicId, 'commentId': commentId},
    requestId,
    (command, identity) async {
      await _delay();
      requireCommentIdentity(identity);
      final post = _requirePost(dynamicId);
      final targets = (_comments[dynamicId] ?? []).where(
        (c) => c.id == commentId,
      );
      if (targets.isEmpty)
        throw const ApiException(
          kind: ApiFailureKind.business,
          code: 40452,
          httpStatus: 404,
          message: '评论不存在',
        );
      final target = targets.first;
      if (target.author.userId != identity.$1 &&
          post.author.userId != identity.$1)
        throw const ApiException(
          kind: ApiFailureKind.forbidden,
          code: 40352,
          message: '不能删除他人评论',
        );
      _deletedComments.add(commentId);
      final count = (_comments[dynamicId] ?? [])
          .where((c) => !_deletedComments.contains(c.id))
          .length;
      _posts[_posts.indexWhere((p) => p.id == dynamicId)] = post.copyWith(
        commentCount: count,
      );
      return CommentDeletion(dynamicId, commentId, count);
    },
  );

  @override
  bool get supportsImagePublishing => false;

  @override
  Future<PagedResult<DynamicPost>> fetchFeed({
    DynamicCategory category = DynamicCategory.all,
    int page = 1,
    int pageSize = 20,
  }) async {
    await _delay();
    final List<DynamicPost> filtered = category == DynamicCategory.all
        ? List<DynamicPost>.of(_posts)
        : _posts
              .where(
                (DynamicPost post) => post.tags.contains(category.backendTag),
              )
              .toList(growable: false);
    final int start = ((page - 1) * pageSize).clamp(0, filtered.length).toInt();
    final int end = (start + pageSize).clamp(0, filtered.length).toInt();
    return PagedResult<DynamicPost>(
      items: filtered.sublist(start, end),
      page: page,
      hasMore: end < filtered.length,
    );
  }

  @override
  Future<DynamicPost> fetchPost(String dynamicId) async {
    await _delay();
    return _requirePost(dynamicId);
  }

  @override
  Future<PagedResult<DynamicComment>> fetchComments({
    required String dynamicId,
    int page = 1,
    int pageSize = 30,
  }) async {
    await _delay();
    _requirePost(dynamicId);
    final List<DynamicComment> values = List<DynamicComment>.of(
      (_comments[dynamicId] ?? const <DynamicComment>[])
          .where((c) => !_deletedComments.contains(c.id))
          .map(_projectComment),
    );
    final int start = ((page - 1) * pageSize).clamp(0, values.length).toInt();
    final int end = (start + pageSize).clamp(0, values.length).toInt();
    return PagedResult<DynamicComment>(
      items: values.sublist(start, end),
      page: page,
      hasMore: end < values.length,
    );
  }

  @override
  Future<DynamicPost> toggleLike(
    String dynamicId, {
    required bool liked,
    String? requestId,
  }) async {
    await _delay();
    final int index = _posts.indexWhere(
      (DynamicPost post) => post.id == dynamicId,
    );
    if (index < 0) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '动态已删除或不可用',
      );
    }
    final DynamicPost current = _posts[index];
    final DynamicPost updated = current.copyWith(
      isLiked: liked,
      likeCount: (current.likeCount + (liked ? 1 : -1))
          .clamp(0, 1 << 31)
          .toInt(),
    );
    _posts[index] = updated;
    return updated;
  }

  @override
  Future<DynamicComment> addComment({
    required String dynamicId,
    required String content,
    int? replyToUserId,
    String? replyToCommentId,
    String? requestId,
  }) async {
    return commentMutation<DynamicComment>(
      'add',
      {
        'dynamicId': dynamicId,
        'content': content.trim(),
        if (replyToUserId != null) 'replyToUserId': replyToUserId,
        if (replyToCommentId != null) 'parentCommentId': replyToCommentId,
      },
      requestId,
      (command, identity) async {
        await _delay();
        requireCommentIdentity(identity);
        final receipt = _commentReceipts[(identity.$1, command.requestId)];
        if (replyToCommentId != null &&
            !(_comments[dynamicId] ?? []).any(
              (c) =>
                  c.id == replyToCommentId && !_deletedComments.contains(c.id),
            )) {
          throw const ApiException(
            kind: ApiFailureKind.business,
            code: 40452,
            httpStatus: 404,
            message: '回复目标不可用',
          );
        }
        if (receipt != null) return _projectComment(receipt);
        final String normalized = content.trim();
        if (normalized.isEmpty || normalized.length > 200) {
          throw const ApiException(
            kind: ApiFailureKind.validation,
            message: '评论内容需为 1～200 个字',
          );
        }
        final int postIndex = _posts.indexWhere(
          (DynamicPost post) => post.id == dynamicId,
        );
        if (postIndex < 0) {
          throw const ApiException(
            kind: ApiFailureKind.validation,
            message: '动态已删除或不可用',
          );
        }
        String? replyName;
        if (replyToCommentId != null) {
          for (final DynamicComment comment
              in _comments[dynamicId] ?? const <DynamicComment>[]) {
            if (comment.id == replyToCommentId) {
              replyName = comment.author.nickname;
              break;
            }
          }
        }
        final DynamicComment comment = DynamicComment(
          id: 'comment-${_commentSequence++}',
          dynamicId: dynamicId,
          author: DynamicAuthor(userId: identity.$1, nickname: '我'),
          content: normalized,
          createdAt: '刚刚',
          replyToUserId: replyToUserId,
          replyToNickname: replyName,
          replyToCommentId: replyToCommentId,
        );
        _comments
            .putIfAbsent(dynamicId, () => <DynamicComment>[])
            .insert(0, comment);
        _posts[postIndex] = _posts[postIndex].copyWith(
          commentCount: _posts[postIndex].commentCount + 1,
        );
        _commentReceipts[(identity.$1, command.requestId)] = comment;
        return _projectComment(comment);
      },
    );
  }

  @override
  Future<DynamicPost> publish(
    PublishDynamicRequest request, {
    String? requestId,
  }) async {
    await _delay();
    final String content = request.content.trim();
    if (content.isEmpty || content.length > 1000) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '动态内容需为 1～1000 个字',
      );
    }
    if (request.media.isNotEmpty ||
        (request.images.isNotEmpty && !supportsImagePublishing)) {
      throw const ApiException(
        kind: ApiFailureKind.configuration,
        message: '图片上传服务尚未接入',
      );
    }
    final DynamicPost post = DynamicPost(
      id: 'dynamic-${_postSequence++}',
      author: const DynamicAuthor(userId: 10001, nickname: '我'),
      content: content,
      images: request.images,
      location: request.location.trim(),
      tags: request.category == DynamicCategory.all
          ? const <String>['聊天']
          : <String>[request.category.label],
      topics: request.topics,
      createdAt: '刚刚',
    );
    _posts.insert(0, post);
    return post;
  }

  @override
  Future<void> deletePost(String dynamicId) async {
    await _delay();
    final DynamicPost post = _requirePost(dynamicId);
    if (post.author.userId != 10001) {
      throw const ApiException(
        kind: ApiFailureKind.forbidden,
        message: '只能删除自己发布的动态',
      );
    }
    _posts.removeWhere((DynamicPost value) => value.id == dynamicId);
    _comments.remove(dynamicId);
  }

  @override
  (int, int) get rankingIdentity => commentIdentity;
  @override
  Listenable? get rankingIdentityChanges => commentIdentityChanges;

  @override
  Future<RankingSnapshot> fetchRanking({
    required RankingBoard board,
    required RankingPeriod period,
    int page = 1,
    int pageSize = 20,
  }) async {
    await _delay();
    if (page < 1 || pageSize < 1 || pageSize > 50) {
      throw const ApiException(
        kind: ApiFailureKind.validation,
        message: '分页参数无效',
      );
    }
    final room = board == RankingBoard.room;
    // Explicit sample data, never a server-authoritative or live ranking.
    final all = List.generate(
      3,
      (i) => RankingEntry(
        rank: i + 1,
        userId: room ? null : 20001 + i,
        roomId: room ? ['880217', '660318', '520906'][i] : null,
        name: room
            ? ['深夜温柔陪伴', '下班后的松弛时刻', '安静音乐电台'][i]
            : ['晚星', '南风', '阿岚'][i],
        value: board.isGiftValue ? null : [128900, 96300, 81500][i],
        giftValueFen: board.isGiftValue
            ? BigInt.from([128900, 96300, 81500][i])
            : null,
        subtitle: '演示数据',
      ),
    );
    return RankingSnapshot(
      board: board,
      period: board.isGiftValue ? period : null,
      entries: all.skip((page - 1) * pageSize).take(pageSize).toList(),
      page: page,
      pageSize: pageSize,
      total: all.length,
      pages: (all.length + pageSize - 1) ~/ pageSize,
      serverAuthoritative: false,
    );
  }

  DynamicPost _requirePost(String id) {
    for (final DynamicPost post in _posts) {
      if (post.id == id) {
        return post;
      }
    }
    throw const ApiException(
      kind: ApiFailureKind.validation,
      message: '动态已删除或不可用',
    );
  }

  static Future<void> _delay() =>
      Future<void>.delayed(const Duration(milliseconds: 35));
}
