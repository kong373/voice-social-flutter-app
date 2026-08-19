import 'package:flutter/material.dart';
import 'package:voice_social_app/app/app_dependency_scope.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
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
    _selectedTarget = widget.targets.isEmpty ? null : widget.targets.first;
    _balance = widget.balance;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_catalog == null && _loading) {
      _loadCatalog();
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final List<GiftCatalogItem> values = await AppDependencyScope.of(
        context,
      ).commerceCatalogRepository.fetchGiftCatalog();
      if (!mounted) {
        return;
      }
      final List<GiftCatalogItem> enabled = values
          .where((GiftCatalogItem item) => item.enabled)
          .toList(growable: false);
      setState(() {
        _catalog = enabled;
        _selectedGift = enabled.firstOrNull;
        if (_selectedGift != null) {
          _category = _selectedGift!.category;
        }
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is ApiException ? error.message : '礼物目录加载失败';
        });
      }
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
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Text('送礼物', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  Text(
                    _balance == null ? '余额以服务端为准' : '余额 $_balance',
                    style: const TextStyle(color: AppColors.warning),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('赠送对象', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (widget.targets.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text('当前没有可赠送的麦上用户'),
                )
              else
                DropdownButtonFormField<GiftTarget>(
                  initialValue: _selectedTarget,
                  items: widget.targets
                      .map(
                        (GiftTarget target) => DropdownMenuItem<GiftTarget>(
                          value: target,
                          child: Text(target.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _submitting
                      ? null
                      : (GiftTarget? value) =>
                            setState(() => _selectedTarget = value),
                ),
              const SizedBox(height: 16),
              Text('普通礼物', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Material(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: <Widget>[
                        Expanded(child: Text(_error!)),
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
                  ),
                )
              else if (_catalog?.isEmpty ?? true)
                const Text('当前没有可用普通礼物')
              else ...<Widget>[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<GiftCatalogCategory>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<GiftCatalogCategory>>[
                      for (final GiftCatalogCategory category
                          in GiftCatalogCategory.values)
                        ButtonSegment<GiftCatalogCategory>(
                          value: category,
                          label: Text(category.label),
                        ),
                    ],
                    selected: <GiftCatalogCategory>{_category},
                    onSelectionChanged: _submitting
                        ? null
                        : (Set<GiftCatalogCategory> values) => setState(() {
                            _category = values.first;
                            _selectedGift =
                                (_catalog ?? const <GiftCatalogItem>[])
                                    .where(
                                      (GiftCatalogItem item) =>
                                          item.category == values.first,
                                    )
                                    .firstOrNull;
                          }),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 108,
                  child: visible.isEmpty
                      ? const Center(child: Text('该分类暂无礼物'))
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (BuildContext context, int index) {
                            final GiftCatalogItem item = visible[index];
                            final bool selected = item.id == gift?.id;
                            return InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: _submitting
                                  ? null
                                  : () => setState(() => _selectedGift = item),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 88,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.primary.withValues(
                                          alpha: 0.18,
                                        )
                                      : AppColors.surfaceHigh,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Icon(_giftIcon(item.category)),
                                    const SizedBox(height: 6),
                                    Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${item.price}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: <int>[1, 10, 66]
                    .map(
                      (int quantity) => ChoiceChip(
                        label: Text('×$quantity'),
                        selected: _quantity == quantity,
                        onSelected: _submitting
                            ? null
                            : (_) => setState(() => _quantity = quantity),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _submitting ||
                          _selectedTarget == null ||
                          _selectedGift == null
                      ? null
                      : () => _submit(total),
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('赠送 · $total'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        if (!mounted) {
          return;
        }
        final int? refreshed = await widget.onRechargeReturn();
        if (mounted) {
          setState(() => _balance = refreshed);
        }
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
      if (!mounted) {
        return;
      }
      if (sent) {
        final int? current = _balance;
        if (current != null) {
          setState(
            () => _balance = (current - total).clamp(0, 1 << 31).toInt(),
          );
        }
        Navigator.of(context).pop(true);
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('赠送失败，请检查余额或网络后重试')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  static IconData _giftIcon(GiftCatalogCategory category) => switch (category) {
    GiftCatalogCategory.popular => Icons.auto_awesome_rounded,
    GiftCatalogCategory.companionship => Icons.favorite_outline_rounded,
    GiftCatalogCategory.celebration => Icons.celebration_outlined,
  };
}

extension _FirstOrNullGift<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
