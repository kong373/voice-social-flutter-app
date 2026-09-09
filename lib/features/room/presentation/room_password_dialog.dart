import 'package:flutter/material.dart';

/// Ephemeral input only: no restoration, autofill, logging or saved password.
class RoomPasswordDialog extends StatefulWidget {
  const RoomPasswordDialog({super.key});

  @override
  State<RoomPasswordDialog> createState() => _RoomPasswordDialogState();
}

class _RoomPasswordDialogState extends State<RoomPasswordDialog> {
  final TextEditingController _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final String password = _password.text.trim();
    if (password.isEmpty || password.length > 32) {
      setState(() => _error = '请输入不超过32个字符的房间密码');
      return;
    }
    _password.clear();
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('输入房间密码'),
    content: TextField(
      key: const Key('room-entry-password'),
      controller: _password,
      autofocus: true,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofillHints: null,
      maxLength: 32,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(labelText: '房间密码', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () {
          _password.clear();
          Navigator.of(context).pop();
        },
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('确认进入')),
    ],
  );
}
