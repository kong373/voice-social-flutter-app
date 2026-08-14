import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';
import 'package:voice_social_app/features/shell/main_shell.dart';

class VoiceSocialApp extends StatelessWidget {
  const VoiceSocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voice Social App',
      theme: AppTheme.dark(),
      home: const MainShell(),
    );
  }
}
