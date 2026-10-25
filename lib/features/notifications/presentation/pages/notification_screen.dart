import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../blocs/notification_bloc.dart';
import '../widgets/notification_tile.dart';

class NotificationScreen extends StatefulWidget {
  final String currentUserId;
  const NotificationScreen({super.key, required this.currentUserId});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  late final NotificationBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = di.sl<NotificationBloc>()..add(LoadNotificationsEvent(widget.currentUserId));
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<NotificationBloc>.value(
      value: _bloc,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            BlocBuilder<NotificationBloc, NotificationState>(
              builder: (context, state) {
                final hasUnread = state is NotificationLoadedState && state.unreadCount > 0;
                return TextButton(
                  onPressed: hasUnread
                      ? () => _bloc.add(MarkAllNotificationsReadEvent(widget.currentUserId))
                      : null,
                  child: Text(
                    'Mark all read',
                    style: TextStyle(
                      color: hasUnread ? AppColors.primaryAccent : AppColors.textSecondary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: BlocConsumer<NotificationBloc, NotificationState>(
          listener: (context, state) {
            if (state is NotificationErrorState) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildBody(context, state),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, NotificationState state) {
    if (state is NotificationLoading || state is NotificationInitial) {
      return const Center(
        key: ValueKey('notif-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (state is NotificationLoadedState) {
      if (state.notifications.isEmpty) {
        return RefreshIndicator(
          key: const ValueKey('notif-empty'),
          onRefresh: () async => _bloc.add(RefreshNotificationsEvent(widget.currentUserId)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'No notifications yet',
                subtitle: "You'll see updates here as they come in",
              ),
            ],
          ),
        );
      }
      return RefreshIndicator(
        key: const ValueKey('notif-loaded'),
        onRefresh: () async => _bloc.add(RefreshNotificationsEvent(widget.currentUserId)),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
          itemCount: state.notifications.length,
          itemBuilder: (context, index) {
            final item = state.notifications[index];
            return NotificationTile(
              key: ValueKey(item.id),
              notification: item,
              onTap: () {
                if (!item.isRead) {
                  _bloc.add(MarkNotificationReadEvent(uid: widget.currentUserId, notificationId: item.id));
                }
              },
              onDelete: () =>
                  _bloc.add(DeleteNotificationEvent(uid: widget.currentUserId, notificationId: item.id)),
            );
          },
        ),
      );
    }
    if (state is NotificationErrorState) {
      return RefreshIndicator(
        key: const ValueKey('notif-error'),
        onRefresh: () async => _bloc.add(LoadNotificationsEvent(widget.currentUserId)),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            ErrorStateView(message: state.message),
          ],
        ),
      );
    }
    return const SizedBox.shrink(key: ValueKey('notif-blank'));
  }
}
