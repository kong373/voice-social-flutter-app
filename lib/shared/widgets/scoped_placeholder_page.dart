import 'package:flutter/material.dart';
import 'package:voice_social_app/core/design_system/app_theme.dart';

export 'package:voice_social_app/features/room/pk/domain/room_pk_models.dart';
export 'package:voice_social_app/features/room/pk/presentation/room_pk_pages.dart';

class ScopedPlaceholderPage extends StatelessWidget {
  const ScopedPlaceholderPage({
    required this.pageId,
    required this.title,
    required this.description,
    super.key,
  });

  final String pageId;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: ValueKey<String>(pageId),
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                description,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
