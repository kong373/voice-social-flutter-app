import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'commerce_models.dart';
import 'refund_request_id.dart';

/// Full input exists only in the open binding flow. Never persist or log it.
class PayoutAccountInput {
  const PayoutAccountInput({
    required this.accountType,
    required this.accountNumber,
    required this.holderName,
    required this.bankName,
  });
  final String accountType;
  final String accountNumber;
  final String holderName;
  final String bankName;
  Map<String, Object?> toBody() => {
    'accountType': accountType,
    'accountNumber': accountNumber,
    'holderName': holderName,
    'bankName': bankName,
  };
  bool get valid =>
      holderName.trim().isNotEmpty &&
      (accountType == 'ALIPAY'
          ? bankName.isEmpty &&
                (RegExp(r'^\+?\d{6,20}$').hasMatch(accountNumber) ||
                    RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch(accountNumber))
          : accountType == 'BANK_CARD' &&
                RegExp(r'^\d+$').hasMatch(accountNumber) &&
                bankName.trim().isNotEmpty);
}

abstract interface class PayoutAccountBindingRepository {
  Future<PayoutAccountSelection> bindPayoutAccount(
    PayoutAccountInput input, {
    required String requestId,
  });
}

/// A page-owned retry intent; leaving the page or any identity generation
/// change irrevocably clears it. An unknown result can only replay this input.
class PayoutBindingSession {
  PayoutBindingSession(this.repository)
    : identity = repository.withdrawalIdentity {
    repository.withdrawalIdentityChanges?.addListener(_identityChanged);
  }
  final CommerceRepository repository;
  final (String?, int) identity;
  PayoutAccountInput? _pending;
  String? _requestId;
  bool _closed = false;
  bool _busy = false;
  bool _outcomeUnknown = false;
  bool get hasPending =>
      !_closed && identity == repository.withdrawalIdentity && _pending != null;
  @visibleForTesting
  String? get requestId => hasPending ? _requestId : null;
  void _identityChanged() {
    if (identity != repository.withdrawalIdentity) dispose();
  }

  void _requireCurrent() {
    if (_closed ||
        identity.$1 == null ||
        identity != repository.withdrawalIdentity) {
      dispose();
      throw const ApiException(
        kind: ApiFailureKind.unauthorized,
        message: '登录身份已变更，请重新打开收款绑定',
      );
    }
  }

  Future<PayoutAccountSelection> submit(PayoutAccountInput input) async {
    _requireCurrent();
    if (_busy) throw StateError('BINDING_IN_PROGRESS');
    if (_pending == null) {
      if (!input.valid)
        throw const ApiException(
          kind: ApiFailureKind.validation,
          message: '请填写本人姓名及有效收款资料',
        );
      _pending = input;
      _requestId = newCommerceRefundRequestId('flutter-payout-binding');
    }
    _busy = true;
    try {
      final result = await (repository as PayoutAccountBindingRepository)
          .bindPayoutAccount(_pending!, requestId: _requestId!);
      _requireCurrent();
      _pending = null;
      _requestId = null;
      _outcomeUnknown = false;
      return result;
    } catch (error) {
      if (_closed || identity != repository.withdrawalIdentity) {
        dispose();
      } else if (shouldRetainCommerceRefundRequest(error)) {
        _outcomeUnknown = true;
      } else if (!_outcomeUnknown) {
        // Later authorization/validation failures precede receipt lookup and
        // cannot prove that an earlier unknown write was not committed.
        _pending = null;
        _requestId = null;
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _closed = true;
    _pending = null;
    _requestId = null;
    _outcomeUnknown = false;
    repository.withdrawalIdentityChanges?.removeListener(_identityChanged);
  }
}
