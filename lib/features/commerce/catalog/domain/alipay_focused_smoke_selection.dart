import 'commerce_catalog_models.dart';

/// Selects the lowest-value enabled catalog item for the cancellation-only
/// Alipay smoke. The server-provided minor-unit amount is the ordering key;
/// malformed, missing, or non-positive values are never sent to order
/// creation. Ties preserve the catalog's existing order.
RechargeProduct? selectLowestPositiveEnabledRechargeProduct(
  Iterable<RechargeProduct> products,
) {
  RechargeProduct? selected;
  int? selectedAmountMinor;
  for (final RechargeProduct product in products) {
    final int? amountMinor = product.amountMinor;
    if (!product.enabled || amountMinor == null || amountMinor <= 0) {
      continue;
    }
    if (selectedAmountMinor == null || amountMinor < selectedAmountMinor) {
      selected = product;
      selectedAmountMinor = amountMinor;
    }
  }
  return selected;
}
