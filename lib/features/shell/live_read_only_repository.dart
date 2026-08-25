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

class VendorCapabilityReadiness {
  const VendorCapabilityReadiness({
    required this.capability,
    required this.boundaryStatus,
    required this.runtimeStatus,
    required this.provider,
    required this.missingConfiguration,
    required this.serverOnlySecretProperties,
    required this.adapterContract,
    required this.securityBoundary,
  });

  final String capability;
  final String boundaryStatus;
  final String runtimeStatus;
  final String provider;
  final List<String> missingConfiguration;
  final List<String> serverOnlySecretProperties;
  final String adapterContract;
  final String securityBoundary;

  bool get boundaryReady => boundaryStatus == 'READY';
  bool get runtimeReady => runtimeStatus == 'READY';
}

class VendorReadinessOverview {
  const VendorReadinessOverview({
    required this.contractVersion,
    required this.integrationStatus,
    required this.runtimeStatus,
    required this.allBoundariesReady,
    required this.allRuntimeAdaptersReady,
    required this.capabilities,
  });

  final String contractVersion;
  final String integrationStatus;
  final String runtimeStatus;
  final bool allBoundariesReady;
  final bool allRuntimeAdaptersReady;
  final Map<String, VendorCapabilityReadiness> capabilities;
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
  static const String _vendorReadinessPath =
      '/app-register-api/vendor/v1/readiness';
  static const Set<String> _authoritativeOrderStatuses = <String>{
    'PENDING',
    'CREATED',
    'CONFIRMING',
    'PROCESSING',
    'SUCCEEDED',
    'SUCCESS',
    'PAID',
    'FAILED',
    'FAILURE',
    'CANCELED',
    'CANCELLED',
  };

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
    final Map<String, Object?> giftCoin = _requiredMap(
      responses[0].data,
      field: '礼物币余额响应',
    );
    final Map<String, Object?> wallet = _requiredMap(
      responses[1].data,
      field: '钱包余额响应',
    );
    final int giftCoinBalance = _requiredGiftCoinBalance(giftCoin);
    final double cashBalance = _requiredNonNegativeNumber(
      wallet,
      'balance',
      field: '现金余额',
    );
    final double frozenBalance = _requiredNonNegativeNumber(
      wallet,
      'frozenBalance',
      field: '冻结余额',
    );
    return LiveWalletSnapshot(
      giftCoinBalance: giftCoinBalance,
      cashBalance: cashBalance,
      frozenBalance: frozenBalance,
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
    final Map<String, Object?> data = _requiredMap(
      response.data,
      field: '充值订单响应',
    );
    final List<Object?> rawOrders = _requiredAliasedList(data);
    final int total = _requiredNonNegativeInt(data, 'total', field: '充值订单总数');
    if (total < rawOrders.length) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单总数小于当前返回记录数',
      );
    }
    return <LivePaymentOrder>[
      for (final Object? raw in rawOrders)
        _paymentOrderFromMap(_requiredMap(raw, field: '充值订单记录')),
    ];
  }

  Future<VendorReadinessOverview> fetchVendorReadiness() async {
    final ApiResponse response = await _apiClient.get(_vendorReadinessPath);
    final Map<String, Object?> data = _map(response.data);
    final Map<String, Object?> rawCapabilities = _map(data['capabilities']);
    final Map<String, VendorCapabilityReadiness> capabilities =
        <String, VendorCapabilityReadiness>{};
    for (final MapEntry<String, Object?> entry in rawCapabilities.entries) {
      final Map<String, Object?> raw = _map(entry.value);
      capabilities[entry.key] = VendorCapabilityReadiness(
        capability: _string(raw['capability'], fallback: entry.key),
        boundaryStatus: _string(raw['boundaryStatus'], fallback: 'UNKNOWN'),
        runtimeStatus: _string(raw['runtimeStatus'], fallback: 'UNKNOWN'),
        provider: _string(raw['provider'], fallback: 'UNCONFIGURED'),
        missingConfiguration: _strings(raw['missingConfiguration']),
        serverOnlySecretProperties: _strings(raw['serverOnlySecretProperties']),
        adapterContract: _string(raw['adapterContract']),
        securityBoundary: _string(raw['securityBoundary']),
      );
    }
    final String contractVersion = _string(data['contractVersion']);
    if (contractVersion.isEmpty || capabilities.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '厂商接入准备响应字段不完整',
      );
    }
    return VendorReadinessOverview(
      contractVersion: contractVersion,
      integrationStatus: _string(data['integrationStatus']),
      runtimeStatus: _string(data['runtimeStatus']),
      allBoundariesReady: data['allBoundariesReady'] == true,
      allRuntimeAdaptersReady: data['allRuntimeAdaptersReady'] == true,
      capabilities: Map<String, VendorCapabilityReadiness>.unmodifiable(
        capabilities,
      ),
    );
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};

  static Map<String, Object?> _requiredMap(
    Object? value, {
    required String field,
  }) {
    if (value is! Map) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$field必须是对象');
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '$field包含非法字段名',
        );
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _requiredAliasedList(Map<String, Object?> data) {
    List<Object?>? selected;
    for (final String key in <String>['list', 'records']) {
      if (!data.containsKey(key)) {
        continue;
      }
      final Object? raw = data[key];
      if (raw is! List) {
        throw ApiException(
          kind: ApiFailureKind.protocol,
          message: '充值订单$key必须是数组',
        );
      }
      final List<Object?> candidate = <Object?>[...raw];
      if (selected != null && !_deepEqual(selected, candidate)) {
        throw const ApiException(
          kind: ApiFailureKind.protocol,
          message: '充值订单 list 与 records 不一致',
        );
      }
      selected = candidate;
    }
    if (selected == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '充值订单响应缺少 list 或 records',
      );
    }
    return selected;
  }

  static int _requiredGiftCoinBalance(Map<String, Object?> data) {
    final int? integer = _optionalStrictInt(data, 'integer', field: '礼物币余额');
    final int? value = _optionalStrictInt(data, 'value', field: '礼物币余额');
    if (integer == null && value == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物币余额缺少有效服务端整数',
      );
    }
    if (integer != null && value != null && integer != value) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物币余额的 integer 与 value 不一致',
      );
    }
    final int balance = integer ?? value!;
    if (balance < 0) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '礼物币余额不能为负数',
      );
    }
    return balance;
  }

  static int? _optionalStrictInt(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    if (!data.containsKey(key)) {
      return null;
    }
    final Object? raw = data[key];
    if (raw is! int) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field的 $key 不是有效服务端整数',
      );
    }
    return raw;
  }

  static int _requiredNonNegativeInt(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    if (!data.containsKey(key) || data[key] is! int) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端整数',
      );
    }
    final int value = data[key]! as int;
    if (value < 0) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$field不能为负数');
    }
    return value;
  }

  static double _requiredNonNegativeNumber(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    final Object? raw = data[key];
    if (!data.containsKey(key) || raw is! num || !raw.isFinite) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端金额',
      );
    }
    final double value = raw.toDouble();
    if (value < 0) {
      throw ApiException(kind: ApiFailureKind.protocol, message: '$field不能为负数');
    }
    return value;
  }

  static LivePaymentOrder _paymentOrderFromMap(Map<String, Object?> raw) {
    final String orderNo = _requiredNonEmptyString(
      raw,
      'orderNo',
      field: '订单号',
    );
    final double amount = _requiredNonNegativeNumber(
      raw,
      'amount',
      field: '订单金额',
    );
    final int giftCoinAmount = _requiredNonNegativeInt(
      raw,
      'ncoin',
      field: '订单礼物币金额',
    );
    final String channelName = _requiredNonEmptyString(
      raw,
      'payType',
      field: '支付渠道',
    );
    final String status = _requiredOrderStatus(raw['status']);
    final DateTime createdAt = _requiredDateTime(raw['createDate']);
    return LivePaymentOrder(
      orderNo: orderNo,
      amount: amount,
      giftCoinAmount: giftCoinAmount,
      channelName: channelName,
      status: status,
      createdAt: createdAt,
    );
  }

  static String _requiredNonEmptyString(
    Map<String, Object?> data,
    String key, {
    required String field,
  }) {
    final Object? raw = data[key];
    if (raw is! String || raw.trim().isEmpty) {
      throw ApiException(
        kind: ApiFailureKind.protocol,
        message: '$field缺少有效服务端字符串',
      );
    }
    return raw.trim();
  }

  static String _requiredOrderStatus(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单响应缺少有效服务端状态',
      );
    }
    final String status = value.trim().toUpperCase();
    if (!_authoritativeOrderStatuses.contains(status)) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单响应缺少有效服务端状态',
      );
    }
    return status;
  }

  static DateTime _requiredDateTime(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单响应缺少有效服务端时间',
      );
    }
    final DateTime? parsed = DateTime.tryParse(value.trim());
    if (parsed == null) {
      throw const ApiException(
        kind: ApiFailureKind.protocol,
        message: '订单响应缺少有效服务端时间',
      );
    }
    return parsed;
  }

  static bool _deepEqual(Object? left, Object? right) {
    if (left is List && right is List) {
      if (left.length != right.length) {
        return false;
      }
      for (int index = 0; index < left.length; index += 1) {
        if (!_deepEqual(left[index], right[index])) {
          return false;
        }
      }
      return true;
    }
    if (left is Map && right is Map) {
      if (left.length != right.length) {
        return false;
      }
      for (final Object? key in left.keys) {
        if (!right.containsKey(key) || !_deepEqual(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is num && right is num) {
      return left == right;
    }
    return left == right;
  }

  static List<Object?> _list(Object? value) =>
      value is List<Object?> ? value : <Object?>[];

  static List<String> _strings(Object? value) => <String>[
    for (final Object? item in _list(value))
      if (_string(item).isNotEmpty) _string(item),
  ];

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static String _string(Object? value, {String fallback = ''}) {
    final String normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }
}
