import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

class GiftOption {
  const GiftOption({
    required this.name,
    required this.price,
    required this.icon,
  });

  final String name;
  final int price;
  final IconData icon;
}

class GiftSendRequest {
  const GiftSendRequest({
    required this.gift,
    required this.target,
    required this.quantity,
  });

  final GiftOption gift;
  final String target;
  final int quantity;
}

class GiftSheet extends StatefulWidget {
  const GiftSheet({
    required this.balance,
    required this.targets,
    required this.onSend,
    super.key,
  });

  final int balance;
  final List<String> targets;
  final Future<bool> Function(GiftSendRequest request) onSend;

  @override
  State<GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<GiftSheet> {
  static const List<GiftOption> _gifts = <GiftOption>[
    GiftOption(
      name: '玫瑰',
      price: 10,
      icon: Icons.local_florist_rounded,
    ),
    GiftOption(name: '热茶', price: 26, icon: Icons.local_cafe_rounded),
    GiftOption(name: '星光', price: 66, icon: Icons.auto_awesome_rounded),
    GiftOption(name: '晚安灯', price: 188, icon: Icons.nightlight_round),
  ];

  GiftOption _selectedGift = _gifts.first;
  String? _selectedTarget;
  int _quantity = 1;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedTarget = widget.targets.isEmpty ? null : widget.targets.first;
  }

  @override
  Widget build(BuildContext context) {
    final int total = _selectedGift.price * _quantity;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
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
                  '余额 ${widget.balance}',
                  style: const TextStyle(color: AppColors.warning),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('赠送对象', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedTarget,
              items: widget.targets
                  .map(
                    (String target) => DropdownMenuItem<String>(
                      value: target,
                      child: Text(target),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _submitting
                  ? null
                  : (String? value) {
                      setState(() => _selectedTarget = value);
                    },
            ),
            const SizedBox(height: 16),
            Text('普通礼物', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _gifts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (BuildContext context, int index) {
                  final GiftOption gift = _gifts[index];
                  final bool selected = gift.name == _selectedGift.name;
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _submitting
                        ? null
                        : () => setState(() => _selectedGift = gift),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 84,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.18)
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
                          Icon(gift.icon, color: AppColors.textPrimary),
                          const SizedBox(height: 6),
                          Text(gift.name),
                          Text(
                            '${gift.price}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
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
                onPressed: _submitting || _selectedTarget == null
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
    );
  }

  Future<void> _submit(int total) async {
    if (total > widget.balance) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('礼物币不足'),
          content: const Text('余额不足，请先前往充值。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final bool sent = await widget.onSend(
      GiftSendRequest(
        gift: _selectedGift,
        target: _selectedTarget!,
        quantity: _quantity,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    Navigator.of(context).pop(sent);
  }
}
