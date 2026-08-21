import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/room/domain/fixed_eight_seat_adapter.dart';
import 'package:voice_social_app/features/room/domain/room_models.dart';

void main() {
  const FixedEightSeatAdapter adapter = FixedEightSeatAdapter();

  test(
    'maps backend seat zero into a free slot while keeping eight UI seats',
    () {
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

      expect(result, hasLength(8));
      expect(
        result.where((MicSeat seat) => seat.backendIndex == 0),
        hasLength(1),
      );
      expect(
        result.singleWhere((MicSeat seat) => seat.backendIndex == 0).userRole,
        RoomRole.owner,
      );
    },
  );

  test('rejects an impossible nine-occupied-seat response', () {
    final List<BackendMicSeat> seats = <BackendMicSeat>[
      for (int index = 0; index <= 8; index += 1)
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
