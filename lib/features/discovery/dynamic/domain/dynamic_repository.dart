import 'package:voice_social_app/features/discovery/dynamic/domain/dynamic_models.dart';

abstract interface class DynamicRepository {
  bool get supportsImagePublishing;

  Future<PagedResult<DynamicPost>> fetchFeed({
    DynamicCategory category = DynamicCategory.all,
    int page = 1,
    int pageSize = 20,
  });

  Future<DynamicPost> fetchPost(String dynamicId);

  Future<PagedResult<DynamicComment>> fetchComments({
    required String dynamicId,
    int page = 1,
    int pageSize = 30,
  });

  Future<DynamicPost> toggleLike(
    String dynamicId, {
    required bool liked,
    String? requestId,
  });

  Future<DynamicComment> addComment({
    required String dynamicId,
    required String content,
    int? replyToUserId,
    String? replyToCommentId,
    String? requestId,
  });

  Future<DynamicPost> publish(
    PublishDynamicRequest request, {
    String? requestId,
  });

  Future<void> deletePost(String dynamicId);

  Future<RankingSnapshot> fetchRanking({
    required RankingBoard board,
    required RankingPeriod period,
  });
}
