import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Formats a connected call's elapsed [duration] as `mm:ss`, or `h:mm:ss`
/// once past an hour.
class CallTimerText extends StatelessWidget {
  final Duration duration;
  final TextStyle? style;

  const CallTimerText({super.key, required this.duration, this.style});

  static String format(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      format(duration),
      style: style ?? const TextStyle(color: AppColors.textSecondary, fontSize: 16),
    );
  }
}
