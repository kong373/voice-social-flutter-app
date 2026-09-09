import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/data/mock_room_operations_repository.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';
import 'package:voice_social_app/features/room/presentation/room_management_page.dart';

void main() {
  testWidgets(
    'unknown audio decision retains original subject and boolean after refresh',
    (tester) async {
      final repo = _Operations()..failOnce = true;
      await tester.pumpWidget(
        MaterialApp(
          home: RoomManagementPage(
            roomId: 'room',
            currentUserId: 20001,
            currentRole: RoomRole.owner,
            repositoryOverride: repo,
            seats: const [
              MicSeat(
                number: 2,
                backendIndex: 2,
                userId: 20002,
                state: MicSeatState.occupiedMuted,
                audioMute: RoomAudioMuteState(
                  selfMuted: true,
                  forcedMuted: true,
                  legacyMuted: false,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('麦位管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '解除管理静音'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('刷新权威状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试原静音操作'));
      await tester.pumpAndSettle();
      expect(repo.audioWrites, [(2, false), (2, false)]);
      expect(repo.audioSubjects, [20002, 20002]);
      expect(find.text('重试原静音操作'), findsNothing);
      expect(find.text('个人静音'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'unknown direct arrangement retains original member and seat after refresh',
    (tester) async {
      final repo = _Operations()..failOnce = true;
      await tester.pumpWidget(
        MaterialApp(
          home: RoomManagementPage(
            roomId: 'room',
            currentUserId: 20001,
            currentRole: RoomRole.owner,
            repositoryOverride: repo,
            seats: const [
              MicSeat(
                number: 9,
                backendIndex: 9,
                state: MicSeatState.available,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('阿岚'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('阿岚'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('安排上麦'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9 号麦'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('刷新权威状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试原安排'));
      await tester.pumpAndSettle();
      expect(repo.assignments, [(20005, 9), (20005, 9)]);
      expect(find.text('重试原安排'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('audio management never changes the public-text mute list', () async {
    final repo = MockRoomOperationsRepository();
    await repo.setSeatMuted(roomId: 'room', backendMicIndex: 2, muted: false);
    expect(
      (await repo.fetchMutedUsers('room')).map((m) => m.userId),
      contains(20002),
    );
    await repo.setSeatMuted(roomId: 'room', backendMicIndex: 3, muted: true);
    expect(
      (await repo.fetchMutedUsers('room')).map((m) => m.userId),
      isNot(contains(20003)),
    );
  });

  testWidgets('releasing management mute preserves personal and text mute', (
    tester,
  ) async {
    final repo = _Operations();
    await tester.pumpWidget(
      MaterialApp(
        home: RoomManagementPage(
          roomId: 'room',
          currentUserId: 20001,
          currentRole: RoomRole.owner,
          repositoryOverride: repo,
          seats: const [
            MicSeat(
              number: 2,
              backendIndex: 2,
              userId: 20002,
              userName: '南风',
              state: MicSeatState.occupiedMuted,
              audioMute: RoomAudioMuteState(
                selfMuted: true,
                forcedMuted: true,
                legacyMuted: true,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('麦位管理'));
    await tester.pumpAndSettle();
    expect(find.text('个人静音'), findsOneWidget);
    expect(find.text('管理静音'), findsOneWidget);
    expect(find.text('历史静音限制'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '解除管理静音'));
    await tester.pumpAndSettle();
    expect(repo.audioWrites, [(2, false)]);
    expect(find.text('个人静音'), findsOneWidget);
    expect(find.text('管理静音'), findsNothing);
    expect(find.text('历史静音限制'), findsNothing);
    expect(find.widgetWithText(ActionChip, '强制静音'), findsOneWidget);
    expect(find.text('麦位已开麦'), findsNothing);
    expect(
      (await repo.fetchMutedUsers('room')).map((m) => m.userId),
      contains(20002),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final occupied in [false, true]) {
    testWidgets(
      'unknown audio authority or empty seat cannot be audio-governed: $occupied',
      (tester) async {
        final repo = _Operations();
        await tester.pumpWidget(
          MaterialApp(
            home: RoomManagementPage(
              roomId: 'room',
              currentUserId: 20001,
              currentRole: RoomRole.owner,
              repositoryOverride: repo,
              seats: [
                MicSeat(
                  number: 2,
                  backendIndex: 2,
                  userId: occupied ? 20002 : null,
                  state: occupied
                      ? MicSeatState.occupied
                      : MicSeatState.available,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('麦位管理'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ActionChip>(find.widgetWithText(ActionChip, '强制静音'))
              .onPressed,
          isNull,
        );
        expect(repo.audioWrites, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _Operations extends MockRoomOperationsRepository {
  final List<(int, bool)> audioWrites = [];
  final List<int?> audioSubjects = [];
  final List<(int, int)> assignments = [];
  bool failOnce = false;
  void _fail() {
    if (failOnce) {
      failOnce = false;
      throw const ApiException(
        kind: ApiFailureKind.network,
        message: 'response lost',
      );
    }
  }

  @override
  Future<void> assignUserToMic({
    required String roomId,
    required int userId,
    required int backendMicIndex,
  }) async {
    assignments.add((userId, backendMicIndex));
    _fail();
  }

  @override
  Future<void> setSeatMuted({
    required String roomId,
    required int backendMicIndex,
    required bool muted,
    int? targetUserId,
  }) async {
    audioWrites.add((backendMicIndex, muted));
    audioSubjects.add(targetUserId);
    _fail();
    await super.setSeatMuted(
      roomId: roomId,
      backendMicIndex: backendMicIndex,
      muted: muted,
    );
  }
}
