import 'package:voice_social_app/core/network/api_client.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/core/network/backend_route_catalog.dart';
import 'package:voice_social_app/features/commerce/application/apple_iap_purchase_coordinator.dart';
import 'package:voice_social_app/features/commerce/domain/apple_iap_models.dart';

class BackendAppleIapPort implements AppleIapBackendPort {
  const BackendAppleIapPort({
    required ApiClient apiClient,
    required BackendRouteCatalog routes,
  }) : _apiClient = apiClient,
       _routes = routes;

  static const int _maximumJwsLength = 128 * 1024;
  final ApiClient _apiClient;
  final BackendRouteCatalog _routes;

  @override
  Future<AppleIapOrderBinding> createOrder({
    required String productId,
    required String requestId,
  }) async {
    final String expectedProductId = _uuid(productId, 'productId');
    final ApiResponse response = await _apiClient
        .postWithoutUnauthorizedRecovery(
          _routes.createAppleRechargeOrder,
          headers: <String, String>{'X-Request-Id': _requestId(requestId)},
          body: <String, Object?>{'productId': expectedProductId},
        );
    final Map<String, Object?> data = _map(response.data, 'Apple 下单');
    final String responseProductId = _uuid(data['productId'], 'productId');
    if (responseProductId != expectedProductId) {
      throw _protocol('Apple 下单商品与请求不一致');
    }
    final int amountMinor = _positiveInt(data['amountMinor'], 'amountMinor');
    final int giftCoinAmount = _positiveInt(
      data['giftCoinAmount'],
      'giftCoinAmount',
    );
    final String status = _requiredString(
      data['status'],
      'status',
    ).toUpperCase();
    if (status != 'CONFIRMING') {
      throw _protocol('Apple 下单初始状态无效');
    }
    return AppleIapOrderBinding(
      orderNo: _orderNo(data['orderNo']),
      productId: responseProductId,
      storeProductId: _storeProductId(data['storeProductId']),
      appAccountToken: _uuid(data['appAccountToken'], 'appAccountToken'),
      amountMinor: amountMinor,
      giftCoinAmount: giftCoinAmount,
      environment: _optionalString(data['environment']) ?? '',
      status: status,
      createdAt: _optionalDateTime(data['createdAt']),
    );
  }

  @override
  Future<AppleIapDeliveryAck> deliverTransaction({
    required String? orderNo,
    required AppleIapTransaction transaction,
    required String requestId,
  }) async {
    final String? expectedOrderNo = orderNo == null ? null : _orderNo(orderNo);
    final String signedTransaction = _jws(transaction.signedTransaction);
    final ApiResponse response = await _apiClient
        .postWithoutUnauthorizedRecovery(
          _routes.deliverAppleTransaction,
          headers: <String, String>{'X-Request-Id': _requestId(requestId)},
          body: <String, Object?>{
            if (expectedOrderNo != null) 'orderNo': expectedOrderNo,
            'signedTransaction': signedTransaction,
          },
        );
    final Map<String, Object?> data = _map(response.data, 'Apple 交易确认');
    final String responseOrderNo = _orderNo(data['orderNo']);
    final String transactionId = _transactionId(data['transactionId']);
    final AppleIapDeliveryState deliveryState = switch (_requiredString(
      data['deliveryState'],
      'deliveryState',
    ).toUpperCase()) {
      'DELIVERED' => AppleIapDeliveryState.delivered,
      'ALREADY_DELIVERED' => AppleIapDeliveryState.alreadyDelivered,
      'PENDING' => AppleIapDeliveryState.pending,
      'REJECTED' => AppleIapDeliveryState.rejected,
      _ => throw _protocol('Apple 交易确认状态无效'),
    };
    final int creditedGiftCoins = _nonNegativeInt(
      data['creditedGiftCoins'],
      'creditedGiftCoins',
    );
    final bool finishAllowed = _bool(data['finishAllowed'], 'finishAllowed');
    if ((expectedOrderNo != null && responseOrderNo != expectedOrderNo) ||
        transactionId != transaction.transactionId ||
        (deliveryState.delivered && creditedGiftCoins <= 0) ||
        (!deliveryState.delivered && creditedGiftCoins != 0) ||
        (finishAllowed && !deliveryState.delivered)) {
      throw _protocol('Apple 交易确认响应与请求或到账状态矛盾');
    }
    return AppleIapDeliveryAck(
      orderNo: responseOrderNo,
      transactionId: transactionId,
      deliveryState: deliveryState,
      creditedGiftCoins: creditedGiftCoins,
      finishAllowed: finishAllowed,
    );
  }

  @override
  Future<AppleIapOrderStatus> readOrderStatus(String orderNo) async {
    final String expectedOrderNo = _orderNo(orderNo);
    final ApiResponse response = await _apiClient.get(
      _routes.appleRechargeOrderStatus,
      query: <String, String>{'orderNo': expectedOrderNo},
    );
    final Map<String, Object?> data = _map(response.data, 'Apple 订单状态');
    final String responseOrderNo = _orderNo(data['orderNo']);
    final String status = _requiredString(
      data['status'],
      'status',
    ).toUpperCase();
    if (responseOrderNo != expectedOrderNo ||
        !const <String>{
          'CREATED',
          'CONFIRMING',
          'SUCCEEDED',
          'FAILED',
          'CANCELLED',
        }.contains(status)) {
      throw _protocol('Apple 订单状态响应与请求不一致');
    }
    final int creditedGiftCoins = _nonNegativeInt(
      data['creditedGiftCoins'],
      'creditedGiftCoins',
    );
    final String? transactionId = switch (data['transactionId']) {
      null => null,
      final Object value => _transactionId(value),
    };
    final bool finishAllowed = _bool(data['finishAllowed'], 'finishAllowed');
    final bool succeeded = status == 'SUCCEEDED';
    if ((succeeded &&
            (creditedGiftCoins <= 0 ||
                transactionId == null ||
                !finishAllowed)) ||
        (!succeeded && (creditedGiftCoins != 0 || finishAllowed))) {
      throw _protocol('Apple 订单状态与到账信息矛盾');
    }
    return AppleIapOrderStatus(
      orderNo: responseOrderNo,
      status: status,
      creditedGiftCoins: creditedGiftCoins,
      transactionId: transactionId,
      finishAllowed: finishAllowed,
      environment: _optionalString(data['environment']),
    );
  }

  static Map<String, Object?> _map(Object? raw, String label) {
    if (raw is! Map<Object?, Object?> || raw.isEmpty) {
      throw _protocol('$label响应不是有效对象');
    }
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in raw.entries) {
      if (entry.key is! String) {
        throw _protocol('$label响应包含非法字段');
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static String _requiredString(Object? raw, String field) {
    if (raw is! String || raw.isEmpty || raw.trim() != raw) {
      throw _protocol('Apple 响应缺少有效 $field');
    }
    return raw;
  }

  static String? _optionalString(Object? raw) {
    if (raw == null) {
      return null;
    }
    return _requiredString(raw, 'optional field');
  }

  static DateTime? _optionalDateTime(Object? raw) {
    final String? value = _optionalString(raw);
    if (value == null) {
      return null;
    }
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw _protocol('Apple 响应时间无效');
    }
    return parsed.toUtc();
  }

  static String _requestId(String value) {
    if (!RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(value)) {
      throw _protocol('Apple 请求幂等 ID 无效');
    }
    return value;
  }

  static String _orderNo(Object? raw) {
    final String value = _requiredString(raw, 'orderNo');
    if (!RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(value)) {
      throw _protocol('Apple 订单号格式无效');
    }
    return value;
  }

  static String _storeProductId(Object? raw) {
    final String value = _requiredString(raw, 'storeProductId');
    if (value.length > 255 || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
      throw _protocol('Apple 商品标识格式无效');
    }
    return value;
  }

  static String _uuid(Object? raw, String field) {
    final String value = _requiredString(raw, field).toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(value)) {
      throw _protocol('Apple $field 格式无效');
    }
    return value;
  }

  static String _transactionId(Object? raw) {
    final String value = _requiredString(raw, 'transactionId');
    if (value.length > 32 || !RegExp(r'^[0-9]+$').hasMatch(value)) {
      throw _protocol('Apple transactionId 格式无效');
    }
    return value;
  }

  static String _jws(String value) {
    if (value.isEmpty ||
        value.length > _maximumJwsLength ||
        value.trim() != value ||
        value.split('.').length != 3 ||
        value.codeUnits.any((int unit) => unit < 0x21 || unit == 0x7f)) {
      throw _protocol('Apple 签名交易格式无效');
    }
    return value;
  }

  static int _positiveInt(Object? raw, String field) {
    final int value = _nonNegativeInt(raw, field);
    if (value <= 0) {
      throw _protocol('Apple $field 必须大于零');
    }
    return value;
  }

  static int _nonNegativeInt(Object? raw, String field) {
    if (raw is! int || raw < 0) {
      throw _protocol('Apple $field 必须是非负整数');
    }
    return raw;
  }

  static bool _bool(Object? raw, String field) {
    if (raw is! bool) {
      throw _protocol('Apple $field 必须是布尔值');
    }
    return raw;
  }

  static ApiException _protocol(String message) =>
      ApiException(kind: ApiFailureKind.protocol, message: message);
}
