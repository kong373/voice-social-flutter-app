import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.social(), home: page));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'feed like ignores double taps and stale response after refresh',
    (WidgetTester tester) async {
      final _ControlledDynamicRepository repository =
          _ControlledDynamicRepository();
      final Completer<DynamicPost> likeResponse = Completer<DynamicPost>();
      repository.pendingLike = likeResponse;
      repository.feedResponses = <DynamicPost>[
        _makePost(isLiked: false, likeCount: 0),
        _makePost(isLiked: false, likeCount: 0),
      ];
      await pumpPage(tester, DiscoveryFeedPage(repository: repository));

      final Finder likeIcon = find.byIcon(Icons.favorite_border_rounded);
      final Offset likePosition = tester.getCenter(likeIcon);
      await tester.tapAt(likePosition);
      await tester.tapAt(likePosition);
      await tester.pump();
      expect(repository.toggleLikeCalls, 1);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);

      await tester.tap(find.text('陪伴').first);
      await tester.pumpAndSettle();
      likeResponse.complete(_makePost(isLiked: true, likeCount: 1));
      await tester.pumpAndSettle();

      // The category refresh is newer than the like response, so the old
      // response must not overwrite the refreshed server state.
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    },
  );

  testWidgets('feed like failure is visible and the action can be retried', (
    WidgetTester tester,
  ) async {
    final _ControlledDynamicRepository repository =
        _ControlledDynamicRepository()
          ..nextLikeError = const ApiException(
            kind: ApiFailureKind.forbidden,
            message: '禁止点赞',
          );
    await pumpPage(tester, DiscoveryFeedPage(repository: repository));

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    expect(find.text('禁止点赞'), findsOneWidget);
    expect(repository.toggleLikeCalls, 1);
    expect(repository.toggleLikeDesiredValues, <bool>[true]);
    final String? firstRequestId = repository.toggleLikeRequestIds.single;
    expect(firstRequestId, isNotNull);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    expect(repository.toggleLikeCalls, 2);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(repository.toggleLikeDesiredValues, <bool>[true, true]);
    expect(repository.toggleLikeRequestIds[1], isNot(firstRequestId));
  });

  testWidgets('feed like ambiguous retry reuses desired state and request id', (
    WidgetTester tester,
  ) async {
    final _ControlledDynamicRepository repository =
        _ControlledDynamicRepository()
          ..nextLikeError = const ApiException(
            kind: ApiFailureKind.timeout,
            message: '请求超时',
          );
    await pumpPage(tester, DiscoveryFeedPage(repository: repository));

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    final String? firstRequestId = repository.toggleLikeRequestIds.single;
    expect(firstRequestId, isNotNull);
    expect(repository.toggleLikeDesiredValues, <bool>[true]);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    expect(repository.toggleLikeDesiredValues, <bool>[true, true]);
    expect(repository.toggleLikeRequestIds[1], firstRequestId);
  });

  testWidgets('comment failure keeps the draft and permits retry', (
    WidgetTester tester,
  ) async {
    final _ControlledDynamicRepository repository =
        _ControlledDynamicRepository()
          ..nextCommentError = const ApiException(
            kind: ApiFailureKind.conflict,
            message: '评论请求冲突，请重试',
          );
    await pumpPage(
      tester,
      DynamicDetailPage(
        postId: 'dynamic-1',
        repository: repository,
        currentUserId: 10001,
      ),
    );

    final Finder editor = find.byType(TextField);
    await tester.enterText(editor, '保留这条评论草稿');
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();
    expect(find.text('评论请求冲突，请重试'), findsOneWidget);
    expect(find.text('保留这条评论草稿'), findsOneWidget);
    expect(repository.addCommentCalls, 1);
    final String? firstRequestId = repository.addCommentRequestIds.single;
    expect(firstRequestId, isNotNull);

    // Let the failure SnackBar leave the bottom composer hit target before
    // retrying the unchanged draft.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final Finder retry = find.byTooltip('发送评论');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repository.addCommentCalls, 2);
    expect(repository.addCommentRequestIds[1], isNot(firstRequestId));
    expect(repository.fetchPostCalls, 2);
    expect(repository.fetchCommentsCalls, 2);
    expect(tester.widget<TextField>(editor).controller?.text, isEmpty);
    expect(find.text('保留这条评论草稿'), findsOneWidget);
    expect(find.text('评论 1'), findsOneWidget);
  });

  testWidgets('comment ambiguous retry reuses request id', (
    WidgetTester tester,
  ) async {
    final _ControlledDynamicRepository repository =
        _ControlledDynamicRepository()
          ..nextCommentError = const ApiException(
            kind: ApiFailureKind.timeout,
            message: '评论超时',
          );
    await pumpPage(
      tester,
      DynamicDetailPage(
        postId: 'dynamic-1',
        repository: repository,
        currentUserId: 10001,
      ),
    );

    final Finder editor = find.byType(TextField);
    await tester.enterText(editor, '保留同一次评论写入');
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();
    final String? firstRequestId = repository.addCommentRequestIds.single;
    expect(firstRequestId, isNotNull);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('发送评论'));
    await tester.pumpAndSettle();
    expect(repository.addCommentRequestIds[1], firstRequestId);
  });

  testWidgets(
    'comment success clears the draft and reports an authoritative refresh failure',
    (WidgetTester tester) async {
      final _ControlledDynamicRepository repository =
          _ControlledDynamicRepository();
      await pumpPage(
        tester,
        DynamicDetailPage(
          postId: 'dynamic-1',
          repository: repository,
          currentUserId: 10001,
        ),
      );
      repository.nextFetchCommentsError = const ApiException(
        kind: ApiFailureKind.network,
        message: '列表读取失败',
      );

      final Finder editor = find.byType(TextField);
      await tester.enterText(editor, '已经落库的评论');
      await tester.tap(find.byTooltip('发送评论'));
      await tester.pumpAndSettle();

      expect(repository.addCommentCalls, 1);
      expect(repository.fetchPostCalls, 2);
      expect(repository.fetchCommentsCalls, 2);
      expect(tester.widget<TextField>(editor).controller?.text, isEmpty);
      expect(find.text('评论已提交，但最新列表刷新失败，请稍后重试'), findsOneWidget);
      expect(find.text('评论 0'), findsOneWidget);
    },
  );

  testWidgets('publish failure is visible and retry succeeds', (
    WidgetTester tester,
  ) async {
    final _ControlledDynamicRepository repository =
        _ControlledDynamicRepository()
          ..nextPublishError = const ApiException(
            kind: ApiFailureKind.validation,
            message: '动态内容校验失败',
          );
    await pumpPage(tester, PublishDynamicPage(repository: repository));

    await tester.enterText(find.byType(TextFormField), '可重试的动态');
    final Finder submit = find.widgetWithText(FilledButton, '发布动态');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('动态内容校验失败'), findsOneWidget);
    expect(repository.publishCalls, 1);
    final String? firstRequestId = repository.publishRequestIds.single;
    expect(firstRequestId, isNotNull);

    final Finder retrySubmit = find.widgetWithText(FilledButton, '发布动态');
    await tester.ensureVisible(retrySubmit);
    await tester.tap(retrySubmit);
    await tester.pumpAndSettle();
    expect(repository.publishCalls, 2);
    expect(repository.publishRequestIds[1], isNot(firstRequestId));
    expect(find.byType(PublishDynamicPage), findsNothing);
  });

  testWidgets('publish ambiguous retry reuses request id', (
    WidgetTester tester,
  ) async {
    final _ControlledDynamicRepository repository =
        _ControlledDynamicRepository()
          ..nextPublishError = const ApiException(
            kind: ApiFailureKind.server,
            message: '发布结果未知',
          );
    await pumpPage(tester, PublishDynamicPage(repository: repository));

    await tester.enterText(find.byType(TextFormField), '需要幂等重试的动态');
    final Finder submit = find.widgetWithText(FilledButton, '发布动态');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    final String? firstRequestId = repository.publishRequestIds.single;
    expect(firstRequestId, isNotNull);

    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(repository.publishRequestIds[1], firstRequestId);
  });

  testWidgets('delete failure is visible and retry succeeds', (
    WidgetTester tester,
  ) async {
    final _ControlledDynamicRepository repository =
        _ControlledDynamicRepository()
          ..nextDeleteError = const ApiException(
            kind: ApiFailureKind.server,
            message: '删除服务暂不可用',
          );
    await pumpPage(
      tester,
      DynamicDetailPage(
        postId: 'dynamic-1',
        repository: repository,
        currentUserId: 10001,
      ),
    );

    await tester.tap(find.byTooltip('删除动态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除服务暂不可用'), findsOneWidget);
    expect(repository.deleteCalls, 1);

    await tester.tap(find.byTooltip('删除动态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 2);
    expect(find.byType(DynamicDetailPage), findsNothing);
  });

  testWidgets(
    'publish invalidates a pending feed generation and clears its loading state',
    (WidgetTester tester) async {
      final _ControlledDynamicRepository repository =
          _ControlledDynamicRepository()
            ..pendingFeed = Completer<PagedResult<DynamicPost>>();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.social(),
          home: DiscoveryFeedPage(repository: repository),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byTooltip('发布动态'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '并发发布的动态');
      await tester.tap(find.widgetWithText(FilledButton, '发布动态'));
      await tester.pumpAndSettle();

      expect(find.text('测试动态内容'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}

DynamicPost _makePost({required bool isLiked, required int likeCount}) =>
    DynamicPost(
      id: 'dynamic-1',
      author: const DynamicAuthor(userId: 10001, nickname: '测试用户'),
      content: '测试动态内容',
      likeCount: likeCount,
      commentCount: 0,
      isLiked: isLiked,
      createdAt: '刚刚',
    );

class _ControlledDynamicRepository implements DynamicRepository {
  _ControlledDynamicRepository()
    : _post = _makePost(isLiked: false, likeCount: 0);

  DynamicPost _post;
  final List<DynamicComment> _comments = <DynamicComment>[];
  List<DynamicPost> feedResponses = <DynamicPost>[];
  Completer<PagedResult<DynamicPost>>? pendingFeed;
  int feedCalls = 0;
  int fetchPostCalls = 0;
  int fetchCommentsCalls = 0;
  ApiException? nextFetchCommentsError;
  int toggleLikeCalls = 0;
  final List<bool> toggleLikeDesiredValues = <bool>[];
  final List<String?> toggleLikeRequestIds = <String?>[];
  Completer<DynamicPost>? pendingLike;
  ApiException? nextLikeError;
  int addCommentCalls = 0;
  final List<String?> addCommentRequestIds = <String?>[];
  ApiException? nextCommentError;
  Completer<DynamicComment>? pendingComment;
  int publishCalls = 0;
  final List<String?> publishRequestIds = <String?>[];
  ApiException? nextPublishError;
  int deleteCalls = 0;
  ApiException? nextDeleteError;

  @override
  bool get supportsImagePublishing => false;

  @override
  Future<PagedResult<DynamicPost>> fetchFeed({
    DynamicCategory category = DynamicCategory.all,
    int page = 1,
    int pageSize = 20,
  }) async {
    final int index = feedCalls++;
    final Completer<PagedResult<DynamicPost>>? pending = pendingFeed;
    if (pending != null) {
      return pending.future;
    }
    final DynamicPost value = feedResponses.isEmpty
        ? _post
        : feedResponses[index.clamp(0, feedResponses.length - 1).toInt()];
    return PagedResult<DynamicPost>(
      items: <DynamicPost>[value],
      page: page,
      hasMore: false,
    );
  }

  @override
  Future<DynamicPost> fetchPost(String dynamicId) async {
    fetchPostCalls += 1;
    return _post;
  }

  @override
  Future<PagedResult<DynamicComment>> fetchComments({
    required String dynamicId,
    int page = 1,
    int pageSize = 30,
  }) async {
    fetchCommentsCalls += 1;
    final ApiException? error = nextFetchCommentsError;
    nextFetchCommentsError = null;
    if (error != null) {
      throw error;
    }
    return PagedResult<DynamicComment>(
      items: List<DynamicComment>.unmodifiable(_comments),
      page: page,
      hasMore: false,
    );
  }

  @override
  Future<DynamicPost> toggleLike(
    String dynamicId, {
    required bool liked,
    String? requestId,
  }) async {
    toggleLikeCalls += 1;
    toggleLikeDesiredValues.add(liked);
    toggleLikeRequestIds.add(requestId);
    final ApiException? error = nextLikeError;
    nextLikeError = null;
    if (error != null) {
      throw error;
    }
    final Completer<DynamicPost>? pending = pendingLike;
    if (pending != null) {
      return pending.future;
    }
    _post = _post.copyWith(
      isLiked: liked,
      likeCount:
          _post.likeCount + (liked == _post.isLiked ? 0 : (liked ? 1 : -1)),
    );
    return _post;
  }

  @override
  Future<DynamicComment> addComment({
    required String dynamicId,
    required String content,
    int? replyToUserId,
    String? replyToCommentId,
    String? requestId,
  }) async {
    addCommentCalls += 1;
    addCommentRequestIds.add(requestId);
    final ApiException? error = nextCommentError;
    nextCommentError = null;
    if (error != null) {
      throw error;
    }
    final Completer<DynamicComment>? pending = pendingComment;
    if (pending != null) {
      return pending.future;
    }
    final DynamicComment comment = DynamicComment(
      id: 'comment-1',
      dynamicId: dynamicId,
      author: const DynamicAuthor(userId: 10001, nickname: '测试用户'),
      content: content,
      createdAt: '刚刚',
    );
    _comments.add(comment);
    _post = _post.copyWith(commentCount: _comments.length);
    return comment;
  }

  @override
  Future<DynamicPost> publish(
    PublishDynamicRequest request, {
    String? requestId,
  }) async {
    publishCalls += 1;
    publishRequestIds.add(requestId);
    final ApiException? error = nextPublishError;
    nextPublishError = null;
    if (error != null) {
      throw error;
    }
    return _post.copyWith();
  }

  @override
  Future<void> deletePost(String dynamicId) async {
    deleteCalls += 1;
    final ApiException? error = nextDeleteError;
    nextDeleteError = null;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<RankingSnapshot> fetchRanking({
    required RankingBoard board,
    required RankingPeriod period,
  }) async {
    return RankingSnapshot(
      board: board,
      period: period,
      entries: const <RankingEntry>[],
    );
  }
}
