import 'package:flutter/widgets.dart';
import '../domain/commerce_models.dart';

/// Clears visible financial data immediately on account/generation changes.
/// Commands and unknown receipts remain owned by the account-scoped repository.
mixin CommerceIdentityFence<T extends StatefulWidget> on State<T> {
  CommerceRepository get commerceIdentityRepository;
  void clearCommerceIdentity();
  Future<void> reloadCommerceIdentity();
  CommerceRepository? _identityRepository;
  (String?, int)? _identity;
  int _readEpoch = 0;

  (int, (String?, int)) beginCommerceRead() =>
      (++_readEpoch, commerceIdentityRepository.withdrawalIdentity);
  bool acceptsCommerceRead((int, (String?, int)) ticket) =>
      mounted &&
      ticket.$1 == _readEpoch &&
      ticket.$2 == commerceIdentityRepository.withdrawalIdentity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = commerceIdentityRepository;
    if (!identical(_identityRepository, repository)) {
      _identityRepository?.withdrawalIdentityChanges?.removeListener(_changed);
      if (_identityRepository != null) {
        _readEpoch++;
        clearCommerceIdentity();
      }
      _identityRepository = repository;
      _identity = repository.withdrawalIdentity;
      repository.withdrawalIdentityChanges?.addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted || _identity == commerceIdentityRepository.withdrawalIdentity)
      return;
    _identity = commerceIdentityRepository.withdrawalIdentity;
    _readEpoch++;
    setState(clearCommerceIdentity);
    if (_identity!.$1 != null) reloadCommerceIdentity();
  }

  @override
  void dispose() {
    _readEpoch++;
    _identityRepository?.withdrawalIdentityChanges?.removeListener(_changed);
    super.dispose();
  }
}
