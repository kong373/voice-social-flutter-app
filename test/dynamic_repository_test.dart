import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/features/discovery/dynamic/data/mock_dynamic_repository.dart';
import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';

void main() {
  test(
    'dynamic likes and comments remain scoped to the selected post',
    () async {
      final MockDynamicRepository repository = MockDynamicRepository();
      final PagedResult<DynamicPost> feed = await repository.fetchFeed();
      final DynamicPost first = feed.items.first;
      final DynamicPost second = feed.items[1];

      final DynamicPost liked = await repository.toggleLike(first.id);
      expect(liked.isLiked, isNot(first.isLiked));
      expect(
        (await repository.fetchPost(second.id)).likeCount,
        second.likeCount,
      );

      await repository.addComment(dynamicId: first.id, content: '这条回应只属于第一条动态');
      expect(
        (await repository.fetchPost(first.id)).commentCount,
        first.commentCount + 1,
      );
      expect(
        (await repository.fetchPost(second.id)).commentCount,
        second.commentCount,
      );
    },
  );

  test('text publishing and ranking work without vendor SDKs', () async {
    final MockDynamicRepository repository = MockDynamicRepository();
    final DynamicPost post = await repository.publish(
      const PublishDynamicRequest(
        content: '一条不依赖图片上传的真实动态',
        category: DynamicCategory.chat,
        topics: <String>['真实生活'],
      ),
    );
    expect(post.author.userId, 10001);
    expect((await repository.fetchFeed()).items.first.id, post.id);

    final RankingSnapshot users = await repository.fetchRanking(
      board: RankingBoard.charm,
      period: RankingPeriod.week,
    );
    final RankingSnapshot rooms = await repository.fetchRanking(
      board: RankingBoard.room,
      period: RankingPeriod.day,
    );
    expect(users.entries.first.userId, isNotNull);
    expect(rooms.entries.first.roomId, isNotNull);
  });
}
