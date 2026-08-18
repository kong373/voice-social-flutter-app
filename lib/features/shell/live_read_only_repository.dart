import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';

class LiveCurrentUser {
  const LiveCurrentUser({
    required this.userId,
    required this.account,
    required this.nickname,
    required this.mobile,
    required this.roles,
    required this.status,
  });

  final int userId;
  final String account;
  final String nickname;
  final String mobile;
  final String roles;
  final String status;
}

class LiveWalletSnapshot {
  const LiveWalletSnapshot({
    required this.giftCoinBalance,
    required this.cashBalance,
    required this.frozenBalance,
  });

  final int giftCoinBalance;
  final double cashBalance;
  final double frozenBalance;
}

class LivePaymentOrder {
  const LivePaymentOrder({
    required this.orderNo,
    required this.amount,
    required this.giftCoinAmount,
    required this.channelName,
    required this.status,
    required this.createdAt,
  });

  final String orderNo;
  final double amount;
  final int giftCoinAmount;
  final String channelName;
  final String status;
  final DateTime? createdAt;
}

class LiveReadOnlyOverview {
  const LiveReadOnlyOverview({
    required this.user,
    required this.wallet,
    required this.orders,
  });

  final LiveCurrentUser user;
  final LiveWalletSnapshot wallet;
  final List<LivePaymentOrder> orders;
}

/// Narrow repository for the M3.2A live shell.
///
/// It intentionally contains no mutation method. SMS/RTC/IM/payment provider
/// integration is introduced behind separate, server-authoritative ports.
class LiveReadOnlyRepository {
  LiveReadOnlyRepository(this._apiClient);

  static const String _currentUserPath =
      '/app-register-api/userAccount/v1/current';
  static const String _giftCoinPath = '/app-economy-api/ncoin';
  static const String _walletPath = '/app-mini-api/mini/v1/wallet/overview';
  static const String _ordersPath = '/app-economy-api/pay/getOrders';

  final ApiClient _apiClient;

  Future<LiveReadOnlyOverview> fetchOverview() async {
    final List<Object> values = await Future.wait<Object>(<Future<Object>>[
      fetchCurrentUser(),
      fetchWallet(),
      fetchOrders(),
    ]);
    return LiveReadOnlyOverview(
      user: values[0] as LiveCurrentUser,
      wallet: values[1] as LiveWalletSnapshot,
      orders: values[2] as List<LivePaymentOrder>,
    );
  }

  Future<LiveCurrentUser> fetchCurrentUser() async {
    final ApiResponse response = await _apiClient.get(_currentUserPath);
    final Map<String, Object?> data = _map(response.data);
    final int userId = _int(data['userId']) ?? _int(data['id']) ?? 0;
    if (userId <= 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '当前用户响应缺少 userId',
      );
    }
    return LiveCurrentUser(
      userId: userId,
      account: _string(data['loginName'], fallback: '$userId'),
      nickname: _string(data['nickName'], fallback: '当前用户'),
      mobile: _string(data['mobile']),
      roles: _string(data['roles']),
      status: _string(data['status']),
    );
  }

  Future<LiveWalletSnapshot> fetchWallet() async {
    final List<ApiResponse> responses = await Future.wait<ApiResponse>(
      <Future<ApiResponse>>[
        _apiClient.get(_giftCoinPath),
        _apiClient.get(_walletPath),
      ],
    );
    final Map<String, Object?> giftCoin = _map(responses[0].data);
    final Map<String, Object?> wallet = _map(responses[1].data);
    return LiveWalletSnapshot(
      giftCoinBalance: _int(giftCoin['integer'] ?? giftCoin['value']) ?? 0,
      cashBalance: _double(wallet['balance']) ?? 0,
      frozenBalance: _double(wallet['frozenBalance']) ?? 0,
    );
  }

  Future<List<LivePaymentOrder>> fetchOrders({
    int page = 1,
    int pageSize = 20,
  }) async {
    final ApiResponse response = await _apiClient.post(
      _ordersPath,
      body: <String, Object?>{
        'pageNum': page,
        'pageSize': pageSize,
        'isSearchCount': true,
      },
    );
    final Map<String, Object?> data = _map(response.data);
    return <LivePaymentOrder>[
      for (final Object? raw in _list(data['list']))
        if (raw is Map<String, Object?>)
          LivePaymentOrder(
            orderNo: _string(raw['orderNo']),
            amount: _double(raw['amount']) ?? 0,
            giftCoinAmount: _int(raw['ncoin']) ?? 0,
            channelName: _string(raw['payType'], fallback: '支付渠道'),
            status: _string(raw['status'], fallback: 'UNKNOWN'),
            createdAt: DateTime.tryParse(_string(raw['createDate'])),
          ),
    ];
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};

  static List<Object?> _list(Object? value) =>
      value is List<Object?> ? value : <Object?>[];

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _double(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }
}
