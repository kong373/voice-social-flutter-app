import 'package:voice_social_app/core/network/api_exception.dart';

/// Display/read-model only. Catalog prices, recharge quantities and payment
/// commands still use whole GIFT_COIN units; never feed tenths into those APIs.
class GiftCoinAmount {
  const GiftCoinAmount.whole(int whole) : _whole = whole, _decimal = null;
  GiftCoinAmount.fromTenths(Object? value)
    : _whole = null,
      _decimal = _decimalString(value);

  final int? _whole;
  final String? _decimal;
  BigInt get tenths => _decimal == null
      ? BigInt.from(_whole!) * BigInt.from(10)
      : BigInt.parse(_decimal);

  String get text {
    final value = tenths;
    final whole = value ~/ BigInt.from(10);
    final remainder = value % BigInt.from(10);
    return remainder == BigInt.zero ? '$whole' : '$whole.$remainder';
  }

  bool coversWholeCoins(int cost) =>
      cost >= 0 && tenths >= BigInt.from(cost) * BigInt.from(10);

  static String _decimalString(Object? value) {
    if (value is! String || !RegExp(r'^[0-9]+$').hasMatch(value)) {
      throw invalidCoinPrecision;
    }
    return value;
  }

  static GiftCoinAmount ledger(Map<String, Object?> data) {
    if (data['currency'] != 'GIFT_COIN' &&
        data['currency'] != 'GIFT_COIN_TENTH')
      throw invalidCoinPrecision;
    requireMetadata(data);
    return GiftCoinAmount.fromTenths(data['amountTenths']);
  }

  static void requireMetadata(Map<String, Object?> data) {
    if (data['precisionVersion'] != 'GIFT_COIN_TENTHS_V1' ||
        data['scale'] is! int ||
        data['scale'] != 10) {
      throw invalidCoinPrecision;
    }
  }
}

class GiftCoinBalance {
  const GiftCoinBalance({required this.available, required this.frozen});
  factory GiftCoinBalance.parse(Object? raw) {
    if (raw is! Map) throw invalidCoinPrecision;
    final data = Map<String, Object?>.from(raw);
    if (data['currency'] != 'GIFT_COIN') throw invalidCoinPrecision;
    GiftCoinAmount.requireMetadata(data);
    return GiftCoinBalance(
      available: GiftCoinAmount.fromTenths(data['availableTenths']),
      frozen: GiftCoinAmount.fromTenths(data['frozenTenths']),
    );
  }
  final GiftCoinAmount available;
  final GiftCoinAmount frozen;
}

const invalidCoinPrecision = ApiException(
  kind: ApiFailureKind.protocol,
  message: '礼物币精度、单位或金额不合法，请刷新后重试',
);
