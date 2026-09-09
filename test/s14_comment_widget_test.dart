import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/mock_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';

void main() {
  Future<void> mountPage(WidgetTester tester, _Repository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DynamicDetailPage(
          postId: 'p1',
          repository: repo,
          currentUserId: 10001,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byTooltip('删除评论').first);
    await tester.pumpAndSettle();
    expect(find.text('仅删除该评论，已有回复会保留。'), findsOneWidget);
    await tester.tap(find.text('确认删除评论'));
    await tester.pump();
  }

  testWidgets('S14 absent capabilities never offer reply or delete', (
    tester,
  ) async {
    final repo = _Repository()..capabilities = false;
    await mountPage(tester, repo);
    expect(find.byTooltip('回复评论'), findsNothing);
    expect(find.byTooltip('删除评论'), findsNothing);
    await tester.tap(find.text('parent text'));
    await tester.pump();
    expect(find.byTooltip('取消回复'), findsNothing);
  });
  testWidgets(
    'S14 reply sends parent and deletion preserves child using server count',
    (tester) async {
      final repo = _Repository();
      await mountPage(tester, repo);
      await tester.tap(find.byTooltip('回复评论').first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('取消回复'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'reply text');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('发送评论'));
      await tester.pumpAndSettle();
      expect(repo.replyTarget, 'parent');
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
      expect(find.text('parent text'), findsNothing);
      expect(find.text('child text'), findsOneWidget);
      expect(find.text('该评论已删除'), findsOneWidget);
      expect(find.text('评论 9'), findsOneWidget);
    },
  );
  testWidgets(
    'S14 unknown delete freezes target and survives page recreation with exact key/body',
    (tester) async {
      final repo = _Repository()
        ..failure = const ApiException(
          kind: ApiFailureKind.network,
          message: 'unknown',
        );
      await mountPage(tester, repo);
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(repo.pendingCommentMutation, isNotNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      final original = repo.writes.single;
      await tester.pumpWidget(const SizedBox());
      await mountPage(tester, repo);
      expect(find.text('重试原删除'), findsOneWidget);
      repo.failure = null;
      await tester.tap(find.text('重试原删除'));
      await tester.pumpAndSettle();
      expect(repo.writes.last, original);
      expect(find.text('评论 9'), findsOneWidget);
    },
  );
  testWidgets(
    'S14 unknown reply draft and parent survive page recreation with exact key/body',
    (tester) async {
      final repo = _Repository()
        ..failure = const ApiException(
          kind: ApiFailureKind.network,
          message: 'unknown',
        );
      await mountPage(tester, repo);
      await tester.tap(find.byTooltip('回复评论').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'original reply');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('发送评论'));
      await tester.pumpAndSettle();
      final original = repo.addWrites.single;
      expect(repo.pendingCommentMutation?.body['parentCommentId'], 'parent');
      await tester.pumpWidget(const SizedBox());
      await mountPage(tester, repo);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'original reply',
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      repo.failure = null;
      await tester.tap(find.byTooltip('发送评论'));
      await tester.pumpAndSettle();
      expect(repo.addWrites.last, original);
      expect(repo.pendingCommentMutation, isNull);
      expect(find.text('评论 2'), findsOneWidget);
    },
  );
  testWidgets(
    'S14 conflict refreshes authority without showing deletion success',
    (tester) async {
      final repo = _Repository()
        ..failure = const ApiException(
          kind: ApiFailureKind.conflict,
          code: 40903,
          message: 'different target',
        );
      await mountPage(tester, repo);
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(repo.pendingCommentMutation, isNull);
      expect(find.text('parent text'), findsOneWidget);
      expect(find.text('评论 2'), findsOneWidget);
      expect(repo.loads, greaterThan(1));
    },
  );
  testWidgets(
    'S14 A late success cannot update B and A restores original delete',
    (tester) async {
      final repo = _Repository()..hold = Completer<void>();
      await mountPage(tester, repo);
      await confirm(tester);
      final original = repo.writes.single;
      repo.switchUser(2);
      await tester.pumpAndSettle();
      expect(find.text('重试原删除'), findsNothing);
      expect(repo.pendingCommentMutation, isNull);
      repo.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('评论 2'), findsOneWidget);
      expect(find.text('parent text'), findsOneWidget);
      repo.hold = null;
      repo.switchUser(10001);
      await tester.pumpAndSettle();
      expect(find.text('重试原删除'), findsOneWidget);
      await tester.tap(find.text('重试原删除'));
      await tester.pumpAndSettle();
      expect(repo.writes.last, original);
      expect(find.text('评论 9'), findsOneWidget);
    },
  );
  test(
    'S14 Mock author and post-owner rights, no third-party delete and no child cascade',
    () async {
      final repo = MockDynamicRepository();
      final owner = _MockAsOwner();
      expect(
        (await owner.fetchComments(
          dynamicId: 'dynamic-1001',
        )).items.first.canDelete,
        isTrue,
      );
      await owner.deleteComment(
        dynamicId: 'dynamic-1001',
        commentId: 'comment-1',
      );
      expect(
        (await owner.fetchComments(
          dynamicId: 'dynamic-1001',
        )).items.map((c) => c.id),
        ['comment-2'],
      );
      await expectLater(
        repo.deleteComment(dynamicId: 'dynamic-1001', commentId: 'comment-1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40352)),
      );
      final parent = await repo.addComment(
        dynamicId: 'dynamic-1001',
        content: 'mine',
      );
      final child = await repo.addComment(
        dynamicId: 'dynamic-1001',
        content: 'child',
        replyToCommentId: parent.id,
      );
      await repo.deleteComment(dynamicId: 'dynamic-1001', commentId: parent.id);
      final comments = await repo.fetchComments(dynamicId: 'dynamic-1001');
      expect(comments.items.any((c) => c.id == parent.id), isFalse);
      expect(
        comments.items.firstWhere((c) => c.id == child.id).parentCommentStatus,
        'DELETED',
      );
      await expectLater(
        repo.addComment(
          dynamicId: 'dynamic-1001',
          content: 'late',
          replyToCommentId: parent.id,
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
}

class _Repository extends MockDynamicRepository {
  final addWrites = <(String, String)>[];
  final changes = ChangeNotifier();
  int user = 10001, generation = 0, loads = 0;
  bool capabilities = true, deleted = false;
  Object? failure;
  Completer<void>? hold;
  String? replyTarget;
  final writes = <(String, String)>[];
  @override
  (int, int) get commentIdentity => (user, generation);
  @override
  Listenable get commentIdentityChanges => changes;
  void switchUser(int id) {
    user = id;
    generation++;
    changes.notifyListeners();
  }

  @override
  Future<DynamicPost> fetchPost(String id) async {
    loads++;
    return DynamicPost(
      id: 'p1',
      author: const DynamicAuthor(userId: 10001, nickname: 'Owner'),
      content: 'post text',
      createdAt: '2026-09-09T00:00:00Z',
      commentCount: deleted ? 9 : 2,
    );
  }

  @override
  Future<PagedResult<DynamicComment>> fetchComments({
    required String dynamicId,
    int page = 1,
    int pageSize = 30,
  }) async => PagedResult(
    items: [
      if (!deleted)
        DynamicComment(
          id: 'parent',
          dynamicId: 'p1',
          author: const DynamicAuthor(userId: 10001, nickname: 'A'),
          content: 'parent text',
          createdAt: '2026-09-09T00:00:00Z',
          canDelete: capabilities && user == 10001,
          canReply: capabilities,
        ),
      DynamicComment(
        id: 'child',
        dynamicId: 'p1',
        author: const DynamicAuthor(userId: 2, nickname: 'B'),
        content: 'child text',
        createdAt: '2026-09-09T00:00:00Z',
        replyToCommentId: 'parent',
        canReply: capabilities,
        parentCommentStatus: deleted ? 'DELETED' : 'PUBLISHED',
        parentCommentPlaceholder: deleted ? '该评论已删除' : '',
      ),
    ],
    page: page,
    hasMore: false,
  );
  @override
  Future<DynamicComment> addComment({
    required String dynamicId,
    required String content,
    int? replyToUserId,
    String? replyToCommentId,
    String? requestId,
  }) async {
    return commentMutation(
      'add',
      {
        'dynamicId': dynamicId,
        'content': content,
        if (replyToUserId != null) 'replyToUserId': replyToUserId,
        if (replyToCommentId != null) 'parentCommentId': replyToCommentId,
      },
      requestId,
      (command, identity) async {
        addWrites.add((command.requestId, jsonEncode(command.body)));
        if (failure != null) throw failure!;
        replyTarget = replyToCommentId;
        return DynamicComment(
          id: 'new',
          dynamicId: dynamicId,
          author: const DynamicAuthor(userId: 10001, nickname: 'A'),
          content: content,
          createdAt: '2026-09-09T00:00:00Z',
        );
      },
    );
  }

  @override
  Future<CommentDeletion> deleteComment({
    required String dynamicId,
    required String commentId,
    String? requestId,
  }) => commentMutation(
    'delete',
    {'dynamicId': dynamicId, 'commentId': commentId},
    requestId,
    (command, identity) async {
      writes.add((command.requestId, jsonEncode(command.body)));
      if (hold != null) await hold!.future;
      if (failure != null) throw failure!;
      // Deliberately return late success even after a switch: journal and UI must fence it.
      if (identity == commentIdentity) deleted = true;
      return CommentDeletion(dynamicId, commentId, 9);
    },
  );
}

class _MockAsOwner extends MockDynamicRepository {
  @override
  (int, int) get commentIdentity => (20001, 0);
}
