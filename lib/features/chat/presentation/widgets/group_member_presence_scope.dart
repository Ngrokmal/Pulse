import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../domain/usecases/watch_group_member_presence_usecase.dart';

class GroupMemberPresenceScope extends StatefulWidget {
  const GroupMemberPresenceScope({
    super.key,
    required this.memberUid,
    required this.watchPresence,
    required this.child,
    this.onPresenceChanged,
  });

  final String memberUid;
  final WatchGroupMemberPresenceUseCase watchPresence;
  final Widget child;
  final ValueChanged<Map<String, dynamic>>? onPresenceChanged;

  @override
  State<GroupMemberPresenceScope> createState() => _GroupMemberPresenceScopeState();
}

class _GroupMemberPresenceScopeState extends State<GroupMemberPresenceScope> {
  StreamSubscription<Map<String, dynamic>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant GroupMemberPresenceScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memberUid != widget.memberUid) {
      _unsubscribe();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.watchPresence(widget.memberUid).listen((row) {
      widget.onPresenceChanged?.call(row);
    });
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
