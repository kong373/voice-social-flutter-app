import 'package:flutter/material.dart';
import '../catalog/domain/commerce_catalog_models.dart';
import '../display/domain/equipped_decoration.dart';
import '../display/presentation/decoration_artwork.dart';

/// Read-only bundled artwork. Never resolves a catalog value as a network URL.
class DecorationPreview extends StatelessWidget {
  const DecorationPreview({
    required this.item,
    this.size = 72,
    this.allowMockAssetPaths = false,
    super.key,
  });

  final DecorationItem item;
  final double size;
  final bool allowMockAssetPaths;

  static const mockAssets = <String>{
    'assets/runtime/avatar-rose.png',
    'assets/runtime/avatar-silver.png',
    'assets/runtime/room-cover-festival.png',
    'assets/runtime/gift-blossom.png',
  };

  @override
  Widget build(BuildContext context) {
    final key = item.assetUrl;
    final type = switch (item.kind) {
      DecorationKind.avatarFrame => 'AVATAR_FRAME',
      DecorationKind.entrance => 'ROOM_ENTRY',
      DecorationKind.profileCard => 'PROFILE_BADGE',
      _ => '',
    };
    final product = DecorationProduct.resolve(key, type);
    if (product != null) return DecorationArtwork(product: product, size: size);
    final asset = allowMockAssetPaths && mockAssets.contains(key) ? key : null;
    Widget missing(String label) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_not_supported_outlined, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: asset == null
          ? missing('预览未配置')
          : Image.asset(
              asset,
              fit: BoxFit.contain,
              semanticLabel: '${item.name}预览',
              errorBuilder: (_, _, _) => missing('预览资源缺失'),
            ),
    );
  }
}
