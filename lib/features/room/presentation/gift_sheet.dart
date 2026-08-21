import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/core/design_system/runtime_surfaces.dart';
import 'package:voice_social_app/core/network/api_exception.dart';
import 'package:voice_social_app/features/commerce/catalog/domain/commerce_catalog_models.dart';
import 'package:voice_social_app/features/commerce/presentation/commerce_pages.dart';

class GiftTarget {
  const GiftTarget({required this.userId, required this.name});

  final int userId;
  final String name;
}

class GiftSendRequest {
  const GiftSendRequest({
    required this.gift,
    required this.target,
    required this.quantity,
  });

  final GiftCatalogItem gift;
  final GiftTarget target;
  final int quantity;
}

class GiftSheet extends StatefulWidget {
  const GiftSheet({
    required this.balance,
    required this.account,
    required this.targets,
    required this.onSend,
    required this.onRechargeReturn,
    super.key,
  });

  final int? balance;
  final String account;
  final List<GiftTarget> targets;
  final Future<bool> Function(GiftSendRequest request) onSend;
  final Future<int?> Function() onRechargeReturn;

  @override
  State<GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<GiftSheet> {
  List<GiftCatalogItem>? _catalog;
  GiftCatalogItem? _selectedGift;
  GiftTarget? _selectedTarget;
  GiftCatalogCategory _category = GiftCatalogCategory.popular;
  int _quantity = 1;
  int? _balance;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedTarget = widget.targets.firstOrNull;
    _balance = widget.balance;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_catalog == null && _loading) _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final List<GiftCatalogItem> values = await AppDependencyScope.of(
        context,
      ).commerceCatalogRepository.fetchGiftCatalog();
      if (!mounted) return;
      final List<GiftCatalogItem> enabled = values
          .where((GiftCatalogItem item) => item.enabled)
          .toList(growable: false);
      setState(() {
        _catalog = enabled;
        _selectedGift = enabled.firstOrNull;
        if (_selectedGift != null) _category = _selectedGift!.category;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException ? error.message : '礼物目录加载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final GiftCatalogItem? gift = _selectedGift;
    final int total = gift == null ? 0 : gift.price * _quantity;
    final List<GiftCatalogItem> visible =
        (_catalog ?? const <GiftCatalogItem>[])
            .where((GiftCatalogItem item) => item.category == _category)
            .toList(growable: false);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 7),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  Text(
                    '送礼物',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '选择麦上用户',
                    style: TextStyle(
                      color: RoomColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _targets(),
            const SizedBox(height: 8),
            _GiftCampaignBanner(onTap: _showCampaignDetails),
            const SizedBox(height: 8),
            _categoryTabs(),
            const SizedBox(height: 3),
            Expanded(child: _giftGrid(visible)),
            _footer(total),
          ],
        ),
      ),
    );
  }

  Widget _targets() {
    if (widget.targets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('当前没有可赠送的麦上用户'),
        ),
      );
    }
    return SizedBox(
      height: 53,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: widget.targets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int index) {
          final GiftTarget target = widget.targets[index];
          final bool selected = target.userId == _selectedTarget?.userId;
          return InkWell(
            onTap: _submitting
                ? null
                : () => setState(() => _selectedTarget = target),
            borderRadius: BorderRadius.circular(99),
            child: Column(
              children: <Widget>[
                RuntimeAvatar(
                  seed: '${target.userId}',
                  size: 34,
                  ringColor: selected ? RoomColors.secondary : Colors.white54,
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 45,
                  child: Text(
                    target.name,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? RoomColors.secondary
                          : RoomColors.textSecondary,
                      fontSize: 8,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _categoryTabs() => SizedBox(
    height: 39,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      children: <Widget>[
        for (final GiftCatalogCategory category in GiftCatalogCategory.values)
          InkWell(
            onTap: _submitting
                ? null
                : () => setState(() {
                    _category = category;
                    _selectedGift = (_catalog ?? const <GiftCatalogItem>[])
                        .where(
                          (GiftCatalogItem item) => item.category == category,
                        )
                        .firstOrNull;
                  }),
            child: Padding(
              padding: const EdgeInsets.only(right: 25, top: 6),
              child: Column(
                children: <Widget>[
                  Text(
                    category == GiftCatalogCategory.popular
                        ? '普通礼物'
                        : category.label,
                    style: TextStyle(
                      color: _category == category
                          ? Colors.white
                          : RoomColors.textSecondary,
                      fontSize: 13,
                      fontWeight: _category == category
                          ? FontWeight.w900
                          : FontWeight.w600,
                    ),
                  ),
                  if (_category == category)
                    Container(
                      width: 20,
                      height: 3,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(
                        color: RoomColors.primary,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _giftGrid(List<GiftCatalogItem> visible) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!),
            TextButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadCatalog();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (visible.isEmpty) return const Center(child: Text('该分类暂无礼物'));
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 5,
        crossAxisSpacing: 4,
        childAspectRatio: 0.78,
      ),
      itemCount: visible.length,
      itemBuilder: (BuildContext context, int index) {
        final GiftCatalogItem item = visible[index];
        final bool selected = item.id == _selectedGift?.id;
        return InkWell(
          onTap: _submitting
              ? null
              : () => setState(() => _selectedGift = item),
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.fromLTRB(4, 5, 4, 4),
            decoration: BoxDecoration(
              color: selected
                  ? RoomColors.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected ? RoomColors.primary : Colors.transparent,
              ),
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Image.asset(_assetForGift(item), fit: BoxFit.contain),
                ),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.circle, color: RoomColors.gold, size: 7),
                    const SizedBox(width: 3),
                    Text(
                      '${item.price}',
                      style: const TextStyle(
                        color: RoomColors.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _footer(int total) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final bool compact =
          constraints.maxWidth < 380 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.15;
      return Container(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 12, 8, compact ? 8 : 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111226),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.circle,
                    color: RoomColors.secondary,
                    size: 9,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      _balance == null ? '余额以服务端为准' : '${_balance!}',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: '充值',
                    child: InkWell(
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                const RechargeCatalogPage(),
                          ),
                        );
                        if (!mounted) return;
                        final int? refreshed = await widget.onRechargeReturn();
                        if (mounted) setState(() => _balance = refreshed);
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 5 : 8,
                          vertical: 9,
                        ),
                        child: const Text(
                          '充值',
                          style: TextStyle(
                            color: RoomColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _QuantityPicker(
              value: _quantity,
              enabled: !_submitting,
              compact: compact,
              onChanged: (int value) => setState(() => _quantity = value),
            ),
            SizedBox(width: compact ? 4 : 6),
            Semantics(
              button: true,
              enabled:
                  !_submitting &&
                  _selectedTarget != null &&
                  _selectedGift != null,
              label: '赠送礼物',
              child: Material(
                color:
                    _submitting ||
                        _selectedTarget == null ||
                        _selectedGift == null
                    ? RoomColors.primary.withValues(alpha: 0.42)
                    : RoomColors.primary,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap:
                      _submitting ||
                          _selectedTarget == null ||
                          _selectedGift == null
                      ? null
                      : () => _submit(total),
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 38,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 16,
                      ),
                      child: Center(
                        child: _submitting
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                compact ? '赠送 $total' : '赠送 · $total',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: compact ? 12 : 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _submit(int total) async {
    final int? balance = _balance;
    if (balance != null && total > balance) {
      final bool? recharge = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('礼物币不足'),
          content: const Text('余额不足，可前往充值中心；返回后会保留当前房间、赠送对象、礼物和数量。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('去充值'),
            ),
          ],
        ),
      );
      if (recharge == true && mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const RechargeCatalogPage(),
          ),
        );
        if (!mounted) return;
        final int? refreshed = await widget.onRechargeReturn();
        if (mounted) setState(() => _balance = refreshed);
      }
      return;
    }
    setState(() => _submitting = true);
    try {
      final bool sent = await widget.onSend(
        GiftSendRequest(
          gift: _selectedGift!,
          target: _selectedTarget!,
          quantity: _quantity,
        ),
      );
      if (!mounted) return;
      if (sent) {
        final int? current = _balance;
        if (current != null) {
          setState(
            () => _balance = (current - total).clamp(0, 1 << 31).toInt(),
          );
        }
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('赠送失败，请检查余额或网络后重试')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showCampaignDetails() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF171833),
      showDragHandle: true,
      builder: (BuildContext sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Image(
              image: AssetImage('assets/runtime/gift-blossom.png'),
              width: 108,
              height: 108,
            ),
            Text('今日心意礼', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              '在当前房间选择一位麦上用户并送出礼物。余额、礼物目录与赠送结果均以仓库返回为准，不会伪造厂商支付结果。',
              textAlign: TextAlign.center,
              style: TextStyle(color: RoomColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('选择礼物'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _assetForGift(GiftCatalogItem item) => switch (item.id % 4) {
    0 => 'assets/runtime/gift-whale.png',
    1 => 'assets/runtime/gift-blossom.png',
    2 => 'assets/runtime/gift-ticket.png',
    _ => 'assets/runtime/gift-celebration-banner.png',
  };
}

class _GiftCampaignBanner extends StatelessWidget {
  const _GiftCampaignBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const Key('gift-campaign-entry'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[
                Color(0xFF6841D7),
                Color(0xFF9D58DF),
                Color(0xFF432D9E),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x554D2AC8), blurRadius: 14),
            ],
          ),
          child: const Row(
            children: <Widget>[
              Image(
                image: AssetImage('assets/runtime/gift-blossom.png'),
                width: 43,
                height: 43,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '今日心意礼',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '送出礼物，为房间点亮一份惊喜',
                      style: TextStyle(color: Colors.white70, fontSize: 9),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    ),
  );
}

class _QuantityPicker extends StatelessWidget {
  const _QuantityPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.compact = false,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    enabled: enabled,
    onSelected: onChanged,
    itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
      for (final int quantity in const <int>[1, 10, 66])
        PopupMenuItem<int>(value: quantity, child: Text('×$quantity')),
    ],
    child: Container(
      height: 38,
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: <Widget>[
          Text('×$value', style: const TextStyle(color: Colors.white)),
          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
        ],
      ),
    ),
  );
}

extension _FirstOrNullGift<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
