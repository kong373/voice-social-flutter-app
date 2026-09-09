import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';

void main() {
  for (final TargetPlatform platform in <TargetPlatform>[
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final int initialComments in <int>[0, 1]) {
      testWidgets(
        '$platform refreshes short detail with $initialComments comments',
        (WidgetTester tester) async {
          await tester.binding.setSurfaceSize(const Size(390, 844));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final _Repository repository = _Repository(initialComments);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark().copyWith(platform: platform),
              home: DynamicDetailPage(
                postId: 'short-post',
                repository: repository,
                currentUserId: 1,
              ),
            ),
          );
          await tester.pumpAndSettle();

          final Finder scrollable = find.descendant(
            of: find.byType(RefreshIndicator),
            matching: find.byType(Scrollable),
          );
          expect(
            tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
            0,
          );
          expect(repository.postReads, 1);
          expect(repository.commentReads, 1);
          expect(find.text('评论 $initialComments'), findsOneWidget);
          expect(
            tester
                .widget<DynamicPostCard>(find.byType(DynamicPostCard))
                .post
                .likeCount,
            0,
          );

          repository.post = repository.post.copyWith(
            likeCount: 1,
            commentCount: initialComments + 1,
          );
          repository.comments = <DynamicComment>[
            ...repository.comments,
            _comment('external', '对方新增的评论'),
          ];
          await tester.pump(const Duration(seconds: 30));
          expect(repository.postReads, 1);
          expect(repository.commentReads, 1);
          expect(find.text('对方新增的评论'), findsNothing);
          expect(find.text('评论 $initialComments'), findsOneWidget);

          await tester.drag(find.byType(ListView), const Offset(0, 350));
          await tester.pumpAndSettle();

          expect(repository.postReads, 2);
          expect(repository.commentReads, 2);
          expect(find.text('对方新增的评论'), findsOneWidget);
          expect(find.text('评论 ${initialComments + 1}'), findsOneWidget);
          expect(
            tester
                .widget<DynamicPostCard>(find.byType(DynamicPostCard))
                .post
                .likeCount,
            1,
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant(<TargetPlatform>{platform}),
      );
    }
  }
}

const DynamicAuthor _author = DynamicAuthor(userId: 2, nickname: '对方');

DynamicComment _comment(String id, String content) => DynamicComment(
  id: id,
  dynamicId: 'short-post',
  author: _author,
  content: content,
  createdAt: '2026-09-09T10:00:00Z',
);

class _Repository implements DynamicRepository {
  _Repository(int count)
    : post = DynamicPost(
        id: 'short-post',
        author: _author,
        content: '短动态',
        createdAt: '2026-09-09T10:00:00Z',
        commentCount: count,
      ),
      comments = <DynamicComment>[if (count == 1) _comment('initial', '已有评论')];

  DynamicPost post;
  List<DynamicComment> comments;
  int postReads = 0;
  int commentReads = 0;

  @override
  Future<DynamicPost> fetchPost(String dynamicId) async {
    postReads++;
    return post;
  }

  @override
  Future<PagedResult<DynamicComment>> fetchComments({
    required String dynamicId,
    int page = 1,
    int pageSize = 30,
  }) async {
    commentReads++;
    return PagedResult<DynamicComment>(
      items: comments,
      page: page,
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
