import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/fixed_eight_seat_adapter.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

void main() {
  const FixedEightSeatAdapter adapter = FixedEightSeatAdapter();

  test('maps explicit legacy zero-based seats without losing identities', () {
    final List<MicSeat> result = adapter.adapt(const <BackendMicSeat>[
      BackendMicSeat(
        index: 0,
        status: 3,
        userId: 9,
        userName: '房主',
        userRoleCode: 3,
      ),
      BackendMicSeat(index: 1, status: 3, userId: 1, userName: '一号麦'),
      BackendMicSeat(index: 2, status: 1),
    ]);

    expect(result, hasLength(9));
    expect(result.first.backendIndex, 0);
    expect(result[1].backendIndex, 1);
    expect(
      result.where((MicSeat seat) => seat.backendIndex == 0),
      hasLength(1),
    );
    expect(
      result.singleWhere((MicSeat seat) => seat.backendIndex == 0).userRole,
      RoomRole.owner,
    );
  });

  test('S02 preserves all nine occupied canonical seats and offline ninth', () {
    final result = adapter.adapt([
      for (int index = 1; index <= 9; index++)
        BackendMicSeat(
          index: index,
          status: 3,
          userId: index,
          isOnline: index != 9,
        ),
    ]);
    expect(result, hasLength(9));
    expect(
      result.map((s) => s.backendIndex),
      orderedEquals([1, 2, 3, 4, 5, 6, 7, 8, 9]),
    );
    expect(result.last.isOccupied, isTrue);
    expect(result.last.isOnline, isFalse);
  });

  test('rejects mixed legacy zero and canonical ninth seat', () {
    final List<BackendMicSeat> seats = <BackendMicSeat>[
      for (int index = 0; index <= 9; index += 1)
        BackendMicSeat(
          index: index,
          status: 3,
          userId: index + 1,
          userName: '用户$index',
        ),
    ];

    expect(() => adapter.adapt(seats), throwsA(isA<ApiException>()));
  });
}
