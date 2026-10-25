import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/verification_status.dart';

class VerificationBadge extends StatelessWidget {
  final VerificationStatus status;
  final double size;

  const VerificationBadge({super.key, required this.status, this.size = 18});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case VerificationStatus.verified:
        return Icon(Icons.verified_rounded, size: size, color: const Color(0xff2ecc71));
      case VerificationStatus.pending:
        return Icon(Icons.hourglass_top_rounded, size: size, color: AppColors.primaryAccent);
      case VerificationStatus.notVerified:
        return const SizedBox.shrink();
    }
  }
}
