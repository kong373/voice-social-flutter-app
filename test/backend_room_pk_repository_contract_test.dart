import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/room/pk/data/backend_room_pk_repository.dart';

void main() {
  test(
    'backend PK rejects legacy numeric identifiers before any HTTP call',
    () async {
      final BackendRoomPkRepository repository = BackendRoomPkRepository(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://127.0.0.1:1/'),
          clientType: 'Android',
          clientInnerVersion: '6',
          authorizationProvider: () => 'Bearer contract-test',
        ),
        routes: const BackendRouteCatalog(),
      );

      await expectLater(
        repository.fetchHotOpponents(roomId: '9527'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
      await expectLater(
        repository.fetchHistory(roomId: '9527'),
        throwsA(
          isA<ApiException>().having(
            (ApiException error) => error.kind,
            'kind',
            ApiFailureKind.validation,
          ),
        ),
      );
    },
  );
}
