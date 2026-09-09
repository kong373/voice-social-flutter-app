import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_social_app/core/network/api_exception.dart';

/// A product lock, not a dismissible settings route. Only the supplied
/// authoritative operation can remove it through the AppGate.
class YouthModeLockPage extends StatefulWidget {
  const YouthModeLockPage({
    required this.onUnlock,
    this.statusMessage,
    super.key,
  });
  final Future<void> Function(String pin) onUnlock;
  final String? statusMessage;
  @override
  State<YouthModeLockPage> createState() => _YouthModeLockPageState();
}

class _YouthModeLockPageState extends State<YouthModeLockPage> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    if (!RegExp(r'^[0-9]{4}$').hasMatch(_pin.text)) {
      setState(() => _error = '请输入设置的 4 位数字密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final pin = _pin.text;
    _pin.clear();
    try {
      await widget.onUnlock(pin);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is ApiException ? error.message : '解锁未确认，请重试',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    '青少年模式已锁定',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '请输入开启时设置的 4 位数字密码，解锁后才能使用 App。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('youth-unlock-pin'),
                    controller: _pin,
                    enabled: !_busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(labelText: '解锁密码'),
                    onSubmitted: (_) => _unlock(),
                  ),
                  if (_error ?? widget.statusMessage
                      case final String message) ...[
                    const SizedBox(height: 12),
                    Text(message, key: const Key('youth-unlock-error')),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('youth-unlock-submit'),
                    onPressed: _busy ? null : _unlock,
                    child: Text(_busy ? '正在核验' : '解锁青少年模式'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
