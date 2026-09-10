import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/features/community/domain/community_repository.dart';
import 'package:voice_social_app/features/community/presentation/community_pages.dart';
import 'package:voice_social_app/features/media/app_image_media_host.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
import 'package:voice_social_app/features/room/pk/domain/room_pk_repository.dart';
import 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';
import 'package:voice_social_app/features/room/presentation/room_cover_artwork.dart';

import 'guild_pk_room_media_contract_test.dart'
    show
        GuildPkMediaFixture,
        guildPkMediaFields,
        mediaCurrentRoomId,
        mediaTargetRoomId;

void main() {
  for (final hasMedia in [true, false]) {
    for (final surface in ['guild', 'pk preparation', 'pk battle']) {
      testWidgets(
        '$surface renders ${hasMedia ? 'controlled covers' : 'original artwork'} from parsed room projections',
        (tester) async {
          final fields = hasMedia ? guildPkMediaFields() : <String, Object?>{};
          final fixture = GuildPkMediaFixture(fields);
          addTearDown(fixture.dispose);
          await tester.binding.setSurfaceSize(const Size(390, 2000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final dependencies = _Dependencies(fixture);
          final Widget page;
          if (surface == 'guild') {
            page = const GuildDetailPage(guildId: 'guild-media');
          } else if (surface == 'pk preparation') {
            page = const RoomPkPreparationPage(
              roomId: mediaCurrentRoomId,
              roomTitle: '当前房间',
            );
          } else {
            final battle = (await tester.runAsync(
              () => fixture.pk.fetchActiveBattle(roomId: mediaCurrentRoomId),
            ))!;
            page = RoomPkBattlePage(
              roomId: mediaCurrentRoomId,
              initialBattle: battle.copyWith(
                stage: RoomPkBattleStage.completed,
              ),
            );
          }
          addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
          await tester.pumpWidget(
            AppDependencyScope(
              dependencies: dependencies,
              child: MaterialApp(theme: AppTheme.social(), home: page),
            ),
          );
          // The HTTP stream adapter needs real event-loop turns as well as
          // fake frame pumping before the page can leave its loading state.
          for (
            var i = 0;
            i < 100 &&
                find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(find.byType(CircularProgressIndicator), findsNothing);
          await tester.pumpAndSettle();

          final artwork = tester.widgetList<RoomCoverArtwork>(
            find.byType(RoomCoverArtwork),
          );
          if (hasMedia) {
            expect(artwork, isNotEmpty);
            for (final item in artwork) {
              expect(item.roomId, mediaTargetRoomId);
              expect(item.media!.toJson(), fields['coverMedia']);
              expect(item.media!.toJson(), isNot(fields['backgroundMedia']));
            }
            expect(artwork.length, surface == 'pk preparation' ? 4 : 1);
          } else {
            expect(artwork, isEmpty);
            if (surface != 'guild') {
              expect(find.byType(RuntimeAvatar), findsWidgets);
            }
          }
          if (surface == 'guild') {
            expect(find.text('公会关联房间'), findsOneWidget);
            expect(find.text('3 人正在房间'), findsOneWidget);
          } else if (surface == 'pk preparation') {
            expect(find.text('收到的邀请'), findsOneWidget);
            expect(find.text('拒绝'), findsOneWidget);
            expect(find.text('接受并准备'), findsOneWidget);
            expect(find.text('10 : 10'), findsOneWidget);
          } else {
            expect(find.text('当前房间'), findsWidgets);
            expect(find.text('PK 对手房间'), findsWidgets);
            expect(find.text('10'), findsNWidgets(2));
          }
          expect(
            tester
                .widgetList<Image>(find.byType(Image))
                .where((image) => image.image is NetworkImage),
            isEmpty,
          );
          expect(
            fixture.http.requests.every((request) => request.method == 'GET'),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

class _Dependencies implements AppDependencies {
  _Dependencies(GuildPkMediaFixture fixture)
    : communityRepository = fixture.community,
      roomPkRepository = fixture.pk;
  @override
  final CommunityRepository communityRepository;
  @override
  final RoomPkRepository roomPkRepository;
  @override
  AppImageMediaHost? get imageMediaHost => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
