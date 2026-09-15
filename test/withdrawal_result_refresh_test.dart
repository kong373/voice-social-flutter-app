import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_social_app/app/app_dependencies.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/data/backend_commerce_repository.dart';
import 'package:voice_social_app/features/commerce/domain/commerce_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

import 'support/media_http_fakes.dart';

// Actual repository + ApiClient parsing. Only the transport and its response
// timing are controlled. These fixtures never contact a server or move funds.
void main() {
  group('W4 withdrawal recovery', () {
    test('unknown then same-identity 403 preserves exact intent until explicit recovery', () async {
      final h = _Harness();
      addTearDown(h.close);
      var attempts = 0;
      h.override = (request) {
        if (!request.uri.path.endsWith('/withdrawal/apply')) return null;
        attempts++;
        if (attempts == 1) return MediaFakeResponse.json(null, status: 503, code: 50301);
        if (attempts == 2) return MediaFakeResponse.json(null, status: 403, code: 40322);
        return MediaFakeResponse.json(_receipt());
      };
      final quote = _quote();
      await expectLater(h.submit(quote: quote), throwsA(isA<ApiException>()));
      final originalKey = h.posts.single.headers.value('X-Request-Id');
      final originalBody = List<int>.of(h.posts.single.body);
      expect(originalKey, isNotEmpty);
      await expectLater(
        h.submit(quote: quote),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 40322)),
      );
      final retained = h.repository.pendingWithdrawal;
      expect(retained, isNotNull);
      expect(retained!.amount, 100);
      expect(retained.payoutAccountId, 'account-1');
      expect(retained.quote, same(quote));
      for (final attempt in <Future<WithdrawalRecord> Function()>[
        () => h.submit(amount: 200, quote: _quote(amount: 200)),
        () => h.submit(account: 'account-other'),
        () => h.submit(quote: _quote(version: 8)),
      ]) {
        await expectLater(attempt(), throwsA(isA<ApiException>()));
      }
      expect(h.posts, hasLength(2), reason: 'Neither refusal nor an altered intent may start a replacement POST');
      final recovered = await h.submit(quote: quote);
      expect(recovered.id, 'withdrawal-1');
      expect(h.repository.pendingWithdrawal, isNull);
      expect(h.posts, hasLength(3));
      for (final request in h.posts) {
        expect(request.headers.value('X-Request-Id'), originalKey);
        expect(request.body, originalBody);
      }
      expect(h.accountReads, 1);
      expect(h.http.requests.where((r) => r.uri.path.endsWith('/fee-rate')), isEmpty);
    });

    test('first definitive refusal clears the new intent and permits a separately confirmed request', () async {
      final h = _Harness();
      addTearDown(h.close);
      var attempts = 0;
      h.override = (request) {
        if (!request.uri.path.endsWith('/withdrawal/apply')) return null;
        return ++attempts == 1
            ? MediaFakeResponse.json(null, status: 403, code: 40375)
            : MediaFakeResponse.json(_receipt());
      };
      await expectLater(h.submit(), throwsA(isA<ApiException>()));
      expect(h.repository.pendingWithdrawal, isNull);
      final firstKey = h.posts.single.headers.value('X-Request-Id');
      expect((await h.submit()).id, 'withdrawal-1');
      expect(h.posts, hasLength(2));
      expect(h.posts.last.headers.value('X-Request-Id'), isNot(firstKey));
      expect(h.accountReads, 2);
    });

    test('late A refusal cannot clear B pending command and B cannot adopt A key', () async {
      final h = _Harness();
      addTearDown(h.close);
      final a = h.gate(), b = h.gate();
      final seenA = Completer<void>(), seenB = Completer<void>();
      var writes = 0;
      h.override = (request) {
        if (!request.uri.path.endsWith('/withdrawal/apply')) return null;
        switch (++writes) {
          case 1:
            seenA.complete();
            return a.future;
          case 2:
            seenB.complete();
            return b.future;
          default:
            return MediaFakeResponse.json(_receipt());
        }
      };
      final first = _outcome(h.submit());
      await seenA.future;
      final aKey = h.posts.single.headers.value('X-Request-Id');
      h.identity.change(2);
      expect(h.repository.pendingWithdrawal, isNull);
      final second = _outcome(h.submit(amount: 200, quote: _quote(amount: 200)));
      await seenB.future;
      a.complete(MediaFakeResponse.json(null, status: 403, code: 40322));
      expect(await first, isA<ApiException>());
      expect(h.repository.pendingWithdrawal!.amount, 200);
      expect(h.posts.last.headers.value('X-Request-Id'), isNot(aKey));
      b.complete(MediaFakeResponse.json(_receipt(amount: 200, id: 'withdrawal-b')));
      expect(await second, isA<WithdrawalRecord>());
      expect(h.repository.pendingWithdrawal, isNull);
      h.identity.change(1);
      expect(h.repository.pendingWithdrawal!.amount, 100);
      await h.submit();
      expect(h.posts, hasLength(3));
      expect(h.posts.last.headers.value('X-Request-Id'), aKey);
      expect(h.posts.last.body, h.posts.first.body);
    });

    test('ABA late original completion cannot clear a newer explicit recovery flight', () async {
      final h = _Harness();
      addTearDown(h.close);
      final old = h.gate(), current = h.gate();
      final seenOld = Completer<void>(), seenCurrent = Completer<void>();
      var writes = 0;
      h.override = (request) {
        if (!request.uri.path.endsWith('/withdrawal/apply')) return null;
        if (++writes == 1) {
          seenOld.complete();
          return old.future;
        }
        seenCurrent.complete();
        return current.future;
      };
      final prior = _outcome(h.submit());
      await seenOld.future;
      h.identity.change(2);
      h.identity.change(1);
      final recovery = _outcome(h.submit());
      await seenCurrent.future;
      old.complete(MediaFakeResponse.json(_receipt()));
      expect(await prior, isA<ApiException>());
      expect(h.repository.pendingWithdrawal, isNotNull);
      await expectLater(h.submit(account: 'different'), throwsA(isA<ApiException>()));
      expect(h.posts, hasLength(2));
      expect(h.posts.first.headers.value('X-Request-Id'), h.posts.last.headers.value('X-Request-Id'));
      expect(h.posts.first.body, h.posts.last.body);
      current.complete(MediaFakeResponse.json(_receipt()));
      expect(await recovery, isA<WithdrawalRecord>());
      expect(h.repository.pendingWithdrawal, isNull);
    });
  });

  group('W4 identity-bound withdrawal reads', () {
    for (final kind in ['quote', 'list', 'filtered', 'record']) {
      for (final aba in [false, true]) {
        test('$kind rejects delayed-open identity switch aba=$aba without sending', () async {
          final h = _Harness();
          addTearDown(h.close);
          final opened = Completer<void>(), release = Completer<void>();
          h.http.beforeOpen = (_) async {
            opened.complete();
            await release.future;
          };
          final result = expectLater(_read(h, kind), throwsA(_staleIdentity));
          await opened.future;
          h.identity.change(2);
          if (aba) h.identity.change(1);
          release.complete();
          await result;
          expect(h.http.requests, hasLength(1));
          expect(h.http.requests.single.aborted, isTrue);
          expect(h.http.requests.single.closes, 0);
          expect(h.http.requests.single.headers.value(HttpHeaders.authorizationHeader), isNull);
          expect(h.posts, isEmpty);
        });

        test('$kind stops a 401 recovery after identity switch aba=$aba', () async {
          final identity = TestMediaIdentity();
          final entered = Completer<void>(), release = Completer<void>();
          final h = _Harness(identity: identity, refresh: () async {
            entered.complete();
            await release.future;
            return true;
          });
          addTearDown(h.close);
          h.override = (_) => MediaFakeResponse.json(null, status: 401, code: 40101);
          final result = expectLater(_read(h, kind), throwsA(_staleIdentity));
          await entered.future;
          identity.change(2);
          if (aba) identity.change(1);
          release.complete();
          await result;
          expect(h.http.requests, hasLength(1));
          expect(h.http.requests.single.method, 'GET');
          expect(h.posts, isEmpty);
        });
      }

      test('$kind permits same-identity token refresh with unchanged query', () async {
        final identity = TestMediaIdentity();
        var refreshes = 0;
        final h = _Harness(identity: identity, refresh: () async {
          refreshes++;
          identity.refreshToken();
          return true;
        });
        addTearDown(h.close);
        var calls = 0;
        h.override = (_) => ++calls == 1
            ? MediaFakeResponse.json(null, status: 401, code: 40101)
            : null;
        await _read(h, kind);
        expect(refreshes, 1);
        expect(identity.generation, 1);
        expect(h.http.requests, hasLength(2));
        expect(h.http.requests.first.uri, h.http.requests.last.uri);
        expect(h.http.requests.first.headers.value(HttpHeaders.authorizationHeader), 'Bearer contract-A-old');
        expect(h.http.requests.last.headers.value(HttpHeaders.authorizationHeader), 'Bearer contract-refreshed');
        expect(h.http.requests.every((r) => r.method == 'GET'), isTrue);
        expect(h.repository.pendingWithdrawal, isNull);
      });

      for (final failure in [false, true]) {
        test('$kind rejects late ${failure ? 'error' : 'success'} for an obsolete identity', () async {
          final h = _Harness();
          addTearDown(h.close);
          final gate = h.gate();
          final started = Completer<MediaFakeRequest>();
          h.override = (request) {
            started.complete(request);
            return gate.future;
          };
          final result = expectLater(_read(h, kind), throwsA(_staleIdentity));
          final request = await started.future;
          h.identity.change(2);
          if (failure) gate.completeError(const SocketException('obsolete transport failure'));
          else gate.complete(MediaFakeResponse.json(h.data(request)));
          await result;
          expect(h.http.requests, hasLength(1));
          expect(h.posts, isEmpty);
        });
      }
    }

    for (final kind in ['filtered', 'record']) {
      test('$kind cannot rebind between pages when identity changes at the first body boundary', () async {
        final h = _Harness();
        addTearDown(h.close);
        h.history = List.generate(101, (index) => _record(id: 'withdrawal-${index + 1}'));
        h.override = (request) {
          if (request.uri.queryParameters['pageNum'] == '1') {
            final bytes = utf8.encode(jsonEncode({'code': 200, 'message': 'OK', 'data': h.data(request)}));
            return MediaFakeResponse(200, _changeAfterBody(bytes, h.identity));
          }
          return null;
        };
        await expectLater(_read(h, kind, recordId: 'withdrawal-101'), throwsA(_staleIdentity));
        expect(h.http.requests, hasLength(1), reason: 'A later page must never capture the new account');
        expect(h.posts, isEmpty);
      });
    }
  });

  _widgetTests();
}

void _widgetTests() {
  for (final oldError in [false, true]) {
    testWidgets('W4 post-submit readback wins over earlier refresh error=$oldError', (tester) async {
      final h = _Harness()..history = [];
      final write = h.gate(), old = h.gate();
      final submitted = Completer<void>(), oldStarted = Completer<void>();
      var recordReads = 0;
      h.override = (request) {
        if (request.uri.path.endsWith('/withdrawal/apply')) {
          submitted.complete();
          return write.future;
        }
        if (request.uri.path.endsWith('/records') && ++recordReads == 2) {
          oldStarted.complete();
          return old.future;
        }
        return null;
      };
      await _withPage(tester, h, (dependencies) async {
        final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
        await _confirmApplication(tester, h);
        await _until(tester, () => submitted.isCompleted, 'Application POST must reach the transport barrier');
        final prior = refresh();
        await _until(tester, () => oldStarted.isCompleted, 'Earlier refresh must reach the held GET');
        h.cash = 200;
        h.history = [_record(mask: '****NEW')];
        write.complete(MediaFakeResponse.json(_receipt()));
        await _until(tester, () => recordReads == 3 && find.text('提现申请已提交').evaluate().isNotEmpty,
            'Confirmed application must finish its authoritative readback');
        expect(find.text('可提现 ¥200.00'), findsOneWidget);
        expect(find.textContaining('****NEW'), findsOneWidget);
        if (oldError) old.completeError(const SocketException('obsolete refresh'));
        else old.complete(MediaFakeResponse.json(_recordPage([], size: 50)));
        await _finish(tester, prior);
        expect(find.text('可提现 ¥200.00'), findsOneWidget);
        expect(find.textContaining('****NEW'), findsOneWidget);
        expect(find.text('暂无提现记录'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(h.posts, hasLength(1));
        expect(h.repository.pendingWithdrawal, isNull);
      });
    });

    testWidgets('W4 old refresh error=$oldError cannot clear a newer loading state', (tester) async {
      final h = _Harness();
      final old = h.gate(), latest = h.gate();
      var reads = 0;
      h.override = (request) {
        if (request.uri.path.endsWith('/records')) {
          if (++reads == 2) return old.future;
          if (reads == 3) return latest.future;
        }
        return null;
      };
      await _withPage(tester, h, (dependencies) async {
        final refresh = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh;
        final prior = refresh();
        await _until(tester, () => reads == 2, 'First refresh request barrier');
        h.cash = 400;
        final current = refresh();
        await _until(tester, () => reads == 3, 'Second refresh request barrier');
        if (oldError) old.completeError(const SocketException('obsolete refresh'));
        else old.complete(MediaFakeResponse.json(_recordPage([_record(mask: '****OLD')], size: 50)));
        await _finish(tester, prior);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.textContaining('****OLD'), findsNothing);
        latest.complete(MediaFakeResponse.json(_recordPage([_record(status: 'SETTLED', mask: '****NEW')], size: 50)));
        await _finish(tester, current);
        expect(find.text('可提现 ¥400.00'), findsOneWidget);
        expect(find.text('¥100.00 · 打款成功'), findsOneWidget);
        expect(find.textContaining('****OLD'), findsNothing);
        expect(h.posts, isEmpty);
      });
    });
  }

  for (final stage in ['records', 'accounts']) {
    testWidgets('W4 replacement repository invalidates old $stage response and intermediate hints', (tester) async {
      final h = _Harness();
      final replacement = _Harness()..cash = 450;
      replacement.history = [_record(status: 'SETTLED', mask: '****REPLACEMENT')];
      final old = h.gate();
      final held = Completer<void>();
      await _withPage(tester, h, (dependencies) async {
        h.override = (request) {
          if (request.uri.path.endsWith('/$stage')) {
            if (!held.isCompleted) held.complete();
            return old.future;
          }
          return null;
        };
        final prior = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
        await _until(tester, () => held.isCompleted, 'Old scope must reach the selected stage');
        try {
          await _mount(tester, dependencies, replacement, stage: 'Replacement repository must issue and complete a new scope read');
          expect(find.text('可提现 ¥450.00'), findsOneWidget);
          final oldAccountReads = h.accountReads;
          if (stage == 'accounts') {
            old.complete(MediaFakeResponse.json(null, status: 403, code: 40375));
          } else {
            old.complete(MediaFakeResponse.json(_recordPage([_record(mask: '****OLD')], size: 50)));
          }
          await _finish(tester, prior);
          expect(find.text('可提现 ¥450.00'), findsOneWidget);
          expect(find.textContaining('****REPLACEMENT'), findsOneWidget);
          expect(find.textContaining('****OLD'), findsNothing);
          expect(find.textContaining('提现申请已安全禁用'), findsNothing);
          expect(h.accountReads, oldAccountReads, reason: 'An obsolete multi-stage read must not start another account GET');
          expect(h.posts, isEmpty);
          expect(replacement.posts, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          replacement.close();
        }
      });
    });
  }

  testWidgets('W4 disposed withdrawal page does not continue the next read stage', (tester) async {
    final h = _Harness();
    final old = h.gate();
    final held = Completer<void>();
    await _withPage(tester, h, (dependencies) async {
      h.override = (request) {
        if (request.uri.path.endsWith('/records')) {
          held.complete();
          return old.future;
        }
        return null;
      };
      final prior = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
      await _until(tester, () => held.isCompleted, 'Held history request before disposal');
      final accounts = h.accountReads;
      await tester.pumpWidget(const SizedBox.shrink());
      old.complete(MediaFakeResponse.json(_recordPage([_record()], size: 50)));
      await _finish(tester, prior);
      expect(h.accountReads, accounts);
      expect(h.posts, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('W4 same-page account ABA ignores a late failure without hiding the current result', (tester) async {
    final h = _Harness();
    final old = h.gate();
    final held = Completer<void>();
    var holdNext = true;
    await _withPage(tester, h, (dependencies) async {
      h.override = (request) {
        if (holdNext && request.uri.path.endsWith('/records')) {
          holdNext = false;
          held.complete();
          return old.future;
        }
        return null;
      };
      final prior = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();
      await _until(tester, () => held.isCompleted, 'Held old-account history request');
      h.cash = 470;
      h.identity.change(2);
      await _until(tester, () => find.text('可提现 ¥470.00').evaluate().isNotEmpty, 'B view ready');
      h.identity.change(1);
      await _until(tester, () => find.text('可提现 ¥470.00').evaluate().isNotEmpty && find.byType(RefreshIndicator).evaluate().isNotEmpty, 'A new generation ready');
      old.completeError(const SocketException('obsolete A history'));
      await _finish(tester, prior);
      expect(find.text('可提现 ¥470.00'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(h.posts, isEmpty);
    });
  });
}

Matcher get _staleIdentity => isA<ApiException>().having(
  (error) => error.message,
  'original identity fence',
  contains('登录身份已切换'),
);

Future<Object> _outcome(Future<Object> future) =>
    future.then<Object>((value) => value, onError: (Object error) => error);

Future<Object> _read(_Harness h, String kind, {String recordId = 'withdrawal-1'}) => switch (kind) {
  'quote' => h.repository.fetchWithdrawalQuote(amount: 100),
  'list' => h.repository.fetchWithdrawalRecords(page: 1, pageSize: 2),
  'filtered' => h.repository.fetchWithdrawalRecords(status: WithdrawalStatus.pending, page: 1, pageSize: 2),
  'record' => h.repository.fetchWithdrawalRecord(recordId),
  _ => throw ArgumentError(kind),
};

Stream<List<int>> _changeAfterBody(List<int> bytes, TestMediaIdentity identity) async* {
  yield bytes;
  identity.change(2);
}

WithdrawalQuote _quote({double amount = 100, int version = 7}) => WithdrawalQuote(
  quotedAmount: amount,
  feeAmount: 0,
  receivedAmount: amount,
  feeRateBasisPoints: 0,
  feeRateText: '0.00%',
  minimumAmount: 100,
  feePolicyVersion: version,
);

Map<String, Object?> _record({String id = 'withdrawal-1', String status = 'SUBMITTED', String mask = '****1001', double amount = 100}) => {
  'withdrawalId': id,
  'payoutAccountId': 'account-1',
  'amountMinor': (amount * 100).round(),
  'feeMinor': 0,
  'netAmountMinor': (amount * 100).round(),
  'status': status,
  'submittedAt': '2026-09-15T00:00:00Z',
  'holderNameMasked': '测*',
  'accountMasked': mask,
  'currency': 'CASH_CNY',
};

Map<String, Object?> _receipt({double amount = 100, String id = 'withdrawal-1'}) => {
  ..._record(amount: amount, id: id),
  'payoutStatus': 'MANUAL_REVIEW_PENDING',
  'providerInvocation': false,
};

Map<String, Object?> _recordPage(List<Map<String, Object?>> records, {int size = 100, int page = 1}) {
  final start = (page - 1) * size;
  final items = records.skip(start).take(size).toList();
  return {
    'list': items,
    'current': page,
    'pageSize': size,
    'total': records.length,
    'pages': records.isEmpty ? 0 : (records.length + size - 1) ~/ size,
  };
}

class _Wire extends MediaFakeHttp {
  _Wire(super.respond);
  @override
  Duration idleTimeout = const Duration(seconds: 2);
  @override
  void close({bool force = false}) {}
}

class _Harness {
  _Harness({TestMediaIdentity? identity, Future<bool> Function()? refresh})
      : identity = identity ?? TestMediaIdentity() {
    http = _Wire(_respond);
    repository = BackendCommerceRepository(
      apiClient: http.api(this.identity, refresh: refresh),
      currentUserId: () => this.identity.user == 0 ? null : '${this.identity.user}',
      identityGeneration: () => this.identity.generation,
      withdrawalIdentityChanges: this.identity,
    );
  }
  final TestMediaIdentity identity;
  late final _Wire http;
  late final BackendCommerceRepository repository;
  FutureOr<HttpClientResponse?> Function(MediaFakeRequest)? override;
  final _gates = <Completer<HttpClientResponse>>[];
  double cash = 300;
  List<Map<String, Object?>> history = [_record()];
  int accountReads = 0;

  List<MediaFakeRequest> get posts => http.requests.where((r) => r.method == 'POST').toList();

  Completer<HttpClientResponse> gate() {
    final value = Completer<HttpClientResponse>();
    _gates.add(value);
    return value;
  }

  Future<WithdrawalRecord> submit({double amount = 100, WithdrawalQuote? quote, String account = 'account-1'}) =>
      repository.applyWithdrawal(amount: amount, confirmedQuote: quote ?? _quote(amount: amount), payoutAccountId: account);

  Future<HttpClientResponse> _respond(MediaFakeRequest request) async {
    if (request.uri.path.endsWith('/accounts')) accountReads++;
    final hook = override;
    if (hook != null) {
      final value = await hook(request);
      if (value != null) return value;
    }
    return MediaFakeResponse.json(data(request));
  }

  Object? data(MediaFakeRequest request) {
    final path = request.uri.path;
    if (path.endsWith('/ncoin')) return {
      'integer': 100,
      'currency': 'GIFT_COIN',
      'precisionVersion': 'GIFT_COIN_TENTHS_V1',
      'scale': 10,
      'availableTenths': '1000',
      'frozenTenths': '0',
    };
    if (path.endsWith('/wallet/overview')) return {
      'incomeRole': 'ANCHOR', 'incomeEligible': true, 'canWithdraw': true,
      'balance': cash, 'frozenBalance': 0, 'totalEarnings': 500,
      'yesterdayEarnings': 0, 'totalWithdraw': 0, 'isRealName': true,
      'agentEarnings': null, 'agentEarningsStatus': 'UNAVAILABLE',
      'superAgentEarnings': null, 'superAgentEarningsStatus': 'UNAVAILABLE',
      'defaultBankCard': {
        'payoutAccountId': 'account-1', 'accountType': 'ALIPAY',
        'accountMasked': '****1001', 'holderNameMasked': '测*',
      },
    };
    if (path.endsWith('/accounts')) return {
      'list': [{
        'payoutAccountId': 'account-1', 'accountType': 'ALIPAY',
        'accountMasked': '****1001', 'holderNameMasked': '测*',
        'status': 'BOUND', 'selectable': true, 'verificationSource': 'USER_DECLARED',
      }],
      'total': 1, 'selectedPayoutAccountId': 'account-1', 'defaultPayoutAccountId': 'account-1',
      'selectionRequired': false, 'providerInvocation': false, 'canBind': true, 'bindingBlockReason': 'NONE',
    };
    if (path.endsWith('/fee-rate')) return {
      'amountMinor': int.parse(request.uri.queryParameters['amountMinor']!),
      'feeMinor': 0, 'netAmountMinor': int.parse(request.uri.queryParameters['amountMinor']!),
      'minimumAmountMinor': 10000, 'feeRateBasisPoints': 0, 'feePolicyVersion': 7,
      'rounding': 'CEILING_FEN', 'settlementMode': 'MANUAL_FINANCE', 'providerInvocation': false,
    };
    if (path.endsWith('/records')) return _recordPage(history,
      size: int.parse(request.uri.queryParameters['pageSize']!),
      page: int.parse(request.uri.queryParameters['pageNum']!),
    );
    if (path.endsWith('/withdrawal/apply')) return _receipt();
    throw StateError('Unexpected W4 fixture route: ${request.method} $path');
  }

  void releaseGates() {
    for (final value in _gates) {
      if (!value.isCompleted) value.complete(MediaFakeResponse.json(null, status: 503, code: 50301));
    }
  }

  void close() {
    releaseGates();
    identity.dispose();
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready, String stage) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 10));
    if (ready()) return;
  }
  fail('Did not reach observed W4 barrier: $stage. Initial fixture failure is not business RED.');
}

Future<void> _finish(WidgetTester tester, Future<void> operation) async {
  var done = false;
  Object? failure;
  operation.then<void>((_) { done = true; }, onError: (Object error, StackTrace _) {
    failure = error;
    done = true;
  });
  await _until(tester, () => done, 'Completion of explicitly released request');
  if (failure != null) throw failure!;
  await tester.pump();
}

Future<void> _mount(WidgetTester tester, AppDependencies dependencies, _Harness h, {
  String stage = 'Initial fixture: wallet, records and accounts must load before controls are used',
}) async {
  await tester.pumpWidget(AppDependencyScope(
    dependencies: dependencies,
    child: MaterialApp(theme: AppTheme.social(),
      home: WithdrawalPage(key: const ValueKey('withdrawal-scope'), repository: h.repository)),
  ));
  await _until(tester, () => h.accountReads > 0 && find.byType(RefreshIndicator).evaluate().isNotEmpty, stage);
  expect(find.text('提现记录'), findsOneWidget);
  expect(find.widgetWithText(FilledButton, '申请提现'), findsOneWidget);
}

Future<void> _withPage(WidgetTester tester, _Harness h, Future<void> Function(AppDependencies) run) async {
  tester.view.physicalSize = const Size(430, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dependencies = AppDependencies.mock();
  try {
    await _mount(tester, dependencies, h);
    await run(dependencies);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    h.releaseGates();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
    dependencies.dispose();
    h.close();
  }
}

Future<void> _confirmApplication(WidgetTester tester, _Harness h) async {
  expect(find.byType(TextField), findsOneWidget);
  await tester.enterText(find.byType(TextField), '100');
  await tester.ensureVisible(find.text('计算到账金额'));
  await tester.tap(find.text('计算到账金额'));
  await _until(tester, () => find.textContaining('服务端报价：').evaluate().isNotEmpty, 'Valid quote must render before confirmation');
  final apply = find.widgetWithText(FilledButton, '申请提现');
  expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
  await tester.ensureVisible(apply);
  await tester.tap(apply);
  await _until(tester, () => find.text('确认提现').evaluate().isNotEmpty, 'Explicit confirmation dialog');
  expect(h.posts, isEmpty, reason: 'Opening the dialog is not authorization to send');
  await tester.tap(find.text('确认提现'));
}
