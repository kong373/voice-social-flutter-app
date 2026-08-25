import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/app/app_environment.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/discovery/data/mock_discovery_repository.dart';
import 'package:voice_social_app/features/discovery/domain/discovery_models.dart';
import 'package:voice_social_app/features/discovery/presentation/search_results_page.dart';

void main() {
  testWidgets('loads the next search page once and appends stable results', (
    WidgetTester tester,
  ) async {
    final _PagingDiscoveryRepository repository = _PagingDiscoveryRepository();
    await _pumpSearch(tester, repository);

    expect(repository.requests, hasLength(1));
    expect(repository.requests.single.page, 1);
    repository.requests.single.complete(
      _result(rooms: const <DiscoveryRoom>[_firstRoom], hasMore: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一页房间'), findsOneWidget);
    expect(find.text('加载更多'), findsOneWidget);

    await tester.ensureVisible(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await tester.pump();

    expect(repository.requests, hasLength(2));
    expect(repository.requests.last.page, 2);
    expect(repository.requests.last.type, SearchEntityType.all);

    repository.requests.last.complete(
      _result(
        rooms: const <DiscoveryRoom>[_firstRoom, _secondRoom],
        page: 2,
        hasMore: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一页房间'), findsOneWidget);
    expect(find.text('第二页房间'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets('discards a stale next page after the search type changes', (
    WidgetTester tester,
  ) async {
    final _PagingDiscoveryRepository repository = _PagingDiscoveryRepository();
    await _pumpSearch(tester, repository);
    repository.requests.single.complete(
      _result(rooms: const <DiscoveryRoom>[_firstRoom], hasMore: true),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    expect(repository.requests, hasLength(2));

    await tester.tap(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text('房间'),
      ),
    );
    await tester.pump();
    expect(repository.requests, hasLength(3));
    expect(repository.requests.last.page, 1);
    expect(repository.requests.last.type, SearchEntityType.rooms);

    repository.requests.last.complete(
      _result(rooms: const <DiscoveryRoom>[_filteredRoom], hasMore: false),
    );
    await tester.pumpAndSettle();
    repository.requests[1].complete(
      _result(
        rooms: const <DiscoveryRoom>[_staleRoom],
        page: 2,
        hasMore: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('筛选后的房间'), findsOneWidget);
    expect(find.text('第一页房间'), findsNothing);
    expect(find.text('过期分页房间'), findsNothing);
  });

  testWidgets('keeps loaded results and retries the same page after failure', (
    WidgetTester tester,
  ) async {
    final _PagingDiscoveryRepository repository = _PagingDiscoveryRepository();
    await _pumpSearch(tester, repository);
    repository.requests.single.complete(
      _result(rooms: const <DiscoveryRoom>[_firstRoom], hasMore: true),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('加载更多'));
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    repository.requests.last.completeError(StateError('temporary failure'));
    await tester.pumpAndSettle();

    expect(find.text('第一页房间'), findsOneWidget);
    expect(find.text('搜索服务暂时不可用，请稍后重试'), findsOneWidget);
    expect(find.text('重试加载'), findsOneWidget);

    await tester.tap(find.text('重试加载'));
    await tester.pump();
    expect(repository.requests, hasLength(3));
    expect(repository.requests.last.page, 2);
    repository.requests.last.complete(
      _result(
        rooms: const <DiscoveryRoom>[_secondRoom],
        page: 2,
        hasMore: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('第一页房间'), findsOneWidget);
    expect(find.text('第二页房间'), findsOneWidget);
    expect(find.text('重试加载'), findsNothing);
  });
}

Future<void> _pumpSearch(
  WidgetTester tester,
  _PagingDiscoveryRepository repository,
) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final AppDependencies dependencies = AppDependencies.forTestEnvironment(
    environment: AppEnvironment.mock(),
    discoveryRepository: repository,
  );
  await tester.pumpWidget(
    AppDependencyScope(
      dependencies: dependencies,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const SearchResultsPage(keyword: '夜聊'),
      ),
    ),
  );
  await tester.pump();
}

DiscoverySearchResult _result({
  required List<DiscoveryRoom> rooms,
  int page = 1,
  bool hasMore = false,
}) {
  return DiscoverySearchResult(
    rooms: rooms,
    users: const <DiscoveryUser>[],
    page: page,
    pageSize: 20,
    hasMore: hasMore,
  );
}

const DiscoveryRoom _firstRoom = DiscoveryRoom(
  id: 'room-page-1',
  code: '100001',
  title: '第一页房间',
  topic: '第一页',
  onlineCount: 11,
  occupiedSeats: 2,
  isSpeaking: true,
  isFavorite: false,
);

const DiscoveryRoom _secondRoom = DiscoveryRoom(
  id: 'room-page-2',
  code: '100002',
  title: '第二页房间',
  topic: '第二页',
  onlineCount: 12,
  occupiedSeats: 3,
  isSpeaking: false,
  isFavorite: false,
);

const DiscoveryRoom _filteredRoom = DiscoveryRoom(
  id: 'room-filtered',
  code: '100003',
  title: '筛选后的房间',
  topic: '当前请求',
  onlineCount: 13,
  occupiedSeats: 4,
  isSpeaking: true,
  isFavorite: false,
);

const DiscoveryRoom _staleRoom = DiscoveryRoom(
  id: 'room-stale',
  code: '100004',
  title: '过期分页房间',
  topic: '过期请求',
  onlineCount: 14,
  occupiedSeats: 5,
  isSpeaking: false,
  isFavorite: false,
);

class _SearchRequest {
  _SearchRequest({required this.type, required this.page});

  final SearchEntityType type;
  final int page;
  final Completer<DiscoverySearchResult> _completer =
      Completer<DiscoverySearchResult>();

  Future<DiscoverySearchResult> get future => _completer.future;

  void complete(DiscoverySearchResult result) => _completer.complete(result);

  void completeError(Object error) => _completer.completeError(error);
}

class _PagingDiscoveryRepository extends MockDiscoveryRepository {
  final List<_SearchRequest> requests = <_SearchRequest>[];

  @override
  Future<DiscoverySearchResult> search({
    required String keyword,
    required SearchEntityType type,
    int page = 1,
    int pageSize = 20,
  }) {
    final _SearchRequest request = _SearchRequest(type: type, page: page);
    requests.add(request);
    return request.future;
  }
}
