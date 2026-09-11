import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/account/domain/user_avatar_descriptor.dart';
import 'package:voice_social_app/features/account/presentation/user_avatar_view.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/mock_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';
import 'package:voice_social_app/features/discovery/dynamic/presentation/dynamic_pages.dart';

void main() {
  testWidgets('dynamic post and comment renderers use secure avatar views', (
    tester,
  ) async {
    final preset = UserAvatarDescriptor.fromBackendData({
      'kind': 'PRESET',
      'reference': 'avatar-preset-sun',
    });
    final post = DynamicPost(
      id: 'post-1',
      author: DynamicAuthor(
        userId: 10001,
        nickname: '作者',
        avatarUrl: 'https://legacy.invalid/post.png',
        avatar: preset,
      ),
      content: '动态正文',
      createdAt: '2026-09-12T00:00:00Z',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: Scaffold(
          body: DynamicPostCard(post: post, onOpen: () {}, onLike: () async {}),
        ),
      ),
    );
    final postAvatar = tester.widget<UserAvatarView>(
      find.byType(UserAvatarView),
    );
    expect(postAvatar.avatar, same(preset));
    expect(find.byType(RuntimeAvatar), findsNothing);

    final repository = _AvatarRepository(
      post,
      const DynamicComment(
        id: 'comment-none',
        dynamicId: 'post-1',
        author: DynamicAuthor(
          userId: 10004,
          nickname: '无头像评论者',
          avatarUrl: 'https://legacy.invalid/none.png',
        ),
        content: '无头像',
        createdAt: '2026-09-12T00:03:00Z',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.social(),
        home: DynamicDetailPage(
          postId: 'post-1',
          repository: repository,
          currentUserId: 10001,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UserAvatarView), findsNWidgets(2));
    expect(find.byKey(const Key('dynamic-avatar-neutral')), findsOneWidget);
    expect(find.byType(RuntimeAvatar), findsNothing);
  });
}

class _AvatarRepository extends MockDynamicRepository {
  _AvatarRepository(this.post, this.comment);

  final DynamicPost post;
  final DynamicComment comment;

  @override
  Future<DynamicPost> fetchPost(String dynamicId) async => post;

  @override
  Future<PagedResult<DynamicComment>> fetchComments({
    required String dynamicId,
    int page = 1,
    int pageSize = 30,
  }) async => PagedResult<DynamicComment>(
    items: <DynamicComment>[comment],
    page: page,
    hasMore: false,
  );
}
