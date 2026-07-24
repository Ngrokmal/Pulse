import 'package:flutter/material.dart';
import '../utils/admin_access.dart';

/// Phase 8.6A (Admin Foundation)
///
/// Wraps every admin screen. If the current user isn't an admin, it pops
/// itself off the navigation stack before ever building the real admin UI —
/// defense-in-depth in case an admin route is ever pushed directly instead
/// of through the hidden entry point in [AdminAccess].
class AdminGuard extends StatefulWidget {
  final String uid;
  final WidgetBuilder builder;

  const AdminGuard({super.key, required this.uid, required this.builder});

  @override
  State<AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<AdminGuard> {
  @override
  void initState() {
    super.initState();
    if (!AdminAccess.isAdmin(widget.uid)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AdminAccess.isAdmin(widget.uid)) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return widget.builder(context);
  }
}
