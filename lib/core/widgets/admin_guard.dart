import 'package:flutter/material.dart';
import '../utils/admin_access.dart';

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
