/// Only these packaged images may be selected by a backend catalog assetKey.
/// Legacy symbolic keys and unknown paths leave the existing UI fallback intact.
String? builtInGiftCatalogAsset(String? assetKey) => switch (assetKey) {
  'assets/runtime/gift-whale.png' ||
  'assets/runtime/gift-blossom.png' ||
  'assets/runtime/gift-ticket.png' ||
  'assets/runtime/gift-celebration-banner.png' => assetKey,
  _ => null,
};
