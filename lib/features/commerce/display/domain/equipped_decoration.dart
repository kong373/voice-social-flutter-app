/// Display-only metadata. It never grants a capability, purchase, or membership.
enum DecorationProduct {
  starRingFrame('decoration/star-ring-frame', 'AVATAR_FRAME', '星环头像框'),
  streamEntry('decoration/stream-entry', 'ROOM_ENTRY', '流光入场'),
  companionBadge('decoration/companion-badge', 'PROFILE_BADGE', '陪伴徽章');

  const DecorationProduct(this.assetKey, this.type, this.label);
  final String assetKey;
  final String type;
  final String label;

  static DecorationProduct? resolve(String? assetKey, String type) {
    for (final product in values) {
      if (product.assetKey == assetKey && product.type == type) return product;
    }
    return null;
  }
}

class EquippedDecoration {
  const EquippedDecoration({
    required this.decorationId,
    required this.type,
    required this.assetKey,
    required this.expiresAt,
  });

  final String decorationId;
  final String type;
  final String assetKey;
  final DateTime? expiresAt;

  DecorationProduct? get product => DecorationProduct.resolve(assetKey, type);
  bool isActiveAt(DateTime now) => expiresAt == null || expiresAt!.isAfter(now);

  static const _fields = {'decorationId', 'type', 'assetKey', 'expiresAt'};
  static const _types = {'AVATAR_FRAME', 'ROOM_ENTRY', 'PROFILE_BADGE'};
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _asset = RegExp(
    r'^decoration/[A-Za-z0-9][A-Za-z0-9/_-]{0,190}$',
  );
  static final _utcInstant = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$',
  );

  /// Missing legacy fields are undecorated. Malformed optional metadata cannot
  /// turn into artwork or make unrelated profile/room information unavailable.
  static List<EquippedDecoration> parseList(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.length > _types.length) return const [];
    final items = <EquippedDecoration>[];
    final seenIds = <String>{};
    final repeatedTypes = <String>{};
    final seenTypes = <String>{};
    for (final raw in value) {
      if (raw is! Map ||
          raw.length != _fields.length ||
          !_fields.every(raw.containsKey))
        return const [];
      final id = raw['decorationId'];
      final type = raw['type'];
      final asset = raw['assetKey'];
      final expiry = raw['expiresAt'];
      if (id is! String ||
          !_uuid.hasMatch(id) ||
          type is! String ||
          !_types.contains(type) ||
          asset is! String ||
          !_asset.hasMatch(asset))
        return const [];
      if (!seenIds.add(id.toLowerCase())) return const [];
      if (!seenTypes.add(type)) repeatedTypes.add(type);
      DateTime? expiresAt;
      if (expiry != null) {
        if (expiry is! String || !_utcInstant.hasMatch(expiry)) return const [];
        expiresAt = DateTime.tryParse(expiry);
        if (expiresAt == null ||
            expiresAt.toUtc().toIso8601String().substring(0, 19) !=
                expiry.substring(0, 19))
          return const [];
      }
      items.add(
        EquippedDecoration(
          decorationId: id,
          type: type,
          assetKey: asset,
          expiresAt: expiresAt,
        ),
      );
    }
    return List.unmodifiable(
      items.where((item) => !repeatedTypes.contains(item.type)),
    );
  }
}
