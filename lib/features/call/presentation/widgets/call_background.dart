import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Full-bleed gradient background shared by all call screens, matching the
/// same top/middle/bottom gradient `AuthScreen` uses elsewhere in the app.
class CallBackground extends StatelessWidget {
  final Widget child;

  const CallBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.backgroundTop, AppColors.backgroundMiddle, AppColors.backgroundBottom],
        ),
      ),
      child: child,
    );
  }
}
