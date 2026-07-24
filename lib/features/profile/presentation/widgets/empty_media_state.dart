import 'package:flutter/material.dart';
import '../../../../core/widgets/empty_state.dart';

/// Thin, profile-specific wrapper around the already-shared
/// [EmptyState] widget (kept from Day 6 base) so "no media yet" reads
/// consistently with every other empty state in the app.
class EmptyMediaState extends StatelessWidget {
  final String title;
  final String? subtitle;

  const EmptyMediaState({
    super.key,
    this.title = 'No media yet',
    this.subtitle = 'Photos and videos shared here will show up in this space.',
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.photo_library_outlined,
      title: title,
      subtitle: subtitle,
    );
  }
}
