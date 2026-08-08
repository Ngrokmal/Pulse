import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/services/group_profile_bulk_warmup_service.dart';
import '../../../../core/widgets/common_loading_widget.dart';
import '../../../../core/widgets/report_dialog.dart';
import '../../../admin/domain/usecases/report_group_usecase.dart';
import '../../domain/usecases/watch_group_member_presence_usecase.dart';
import '../blocs/group_info_bloc.dart';
import '../widgets/group_friend_list_tile.dart';
import '../widgets/group_member_presence_scope.dart';

class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  final String currentUserId;
  const GroupInfoScreen({
    super.key,
    required this.groupId,
    required this.currentUserId,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late final GroupInfoBloc _groupInfoBloc;
  late final WatchGroupMemberPresenceUseCase _watchMemberPresence;
  late final GroupProfileBulkWarmupService _groupProfileWarmup;
  final ScrollController _memberListScrollController = ScrollController();
  Timer? _memberWindowDebounce;
  bool _hasTriggeredInitialWarmup = false;

  final ValueNotifier<int> _memberCacheVersion = ValueNotifier<int>(0);
  Set<String> _lastKnownMemberUids = const {};

  static const double _kEstimatedRowExtent = 64.0;
  static const int _kPrefetchWindow = 15;
  static const int _kFallbackInitialWindow = 30;

  final TextEditingController _addMemberController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _groupInfoBloc = di.sl<GroupInfoBloc>()..add(LoadGroupInfoEvent(widget.groupId));
    _watchMemberPresence = di.sl<WatchGroupMemberPresenceUseCase>();
    _groupProfileWarmup = di.sl<GroupProfileBulkWarmupService>();
    _memberListScrollController.addListener(_onMemberListScrolled);
  }

  @override
  void dispose() {
    _memberWindowDebounce?.cancel();
    _memberListScrollController.removeListener(_onMemberListScrolled);
    _memberListScrollController.dispose();
    _memberCacheVersion.dispose();
    _addMemberController.dispose();
    _groupInfoBloc.close();
    super.dispose();
  }

  void _addMember() {
    final uid = _addMemberController.text.trim();
    if (uid.isEmpty) return;
    _groupInfoBloc.add(AddMemberRequested(
      groupId: widget.groupId,
      uid: uid,
      actorUid: widget.currentUserId,
    ));
    _addMemberController.clear();
  }

  Future<void> _confirmRemoveMember(String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove $uid from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _groupInfoBloc.add(RemoveMemberRequested(
        groupId: widget.groupId,
        uid: uid,
        actorUid: widget.currentUserId,
      ));
    }
  }

  Future<void> _reportGroup() async {
    final submission = await showReportDialog(context, title: 'Report Group');
    if (submission == null) return;
    final result = await di.sl<ReportGroupUseCase>()(
      reporterUid: widget.currentUserId,
      groupId: widget.groupId,
      reason: submission.reason,
    );
    if (!mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted'))),
    );
  }

  Future<void> _confirmLeaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _groupInfoBloc.add(LeaveGroupRequested(groupId: widget.groupId, uid: widget.currentUserId));
    }
  }

  void _promoteAdmin(String uid) {
    _groupInfoBloc.add(PromoteAdminRequested(
      groupId: widget.groupId,
      uid: uid,
      actorUid: widget.currentUserId,
    ));
  }

  void _demoteAdmin(String uid) {
    _groupInfoBloc.add(DemoteAdminRequested(
      groupId: widget.groupId,
      uid: uid,
      actorUid: widget.currentUserId,
    ));
  }


  void _onMemberListScrolled() {
    _memberWindowDebounce?.cancel();
    _memberWindowDebounce = Timer(const Duration(milliseconds: 250), _warmUpVisibleMemberWindow);
  }

  void _warmUpVisibleMemberWindow() {
    if (!mounted) return;
    final state = _groupInfoBloc.state;
    if (state is! GroupInfoLoadedState) return;
    final members = state.group.cachedMemberUids;
    if (members.isEmpty) return;

    if (!_memberListScrollController.hasClients) {
      unawaited(_groupProfileWarmup
          .warmUpVisibleMembers(members.take(_kFallbackInitialWindow))
          .then((_) => _bumpMemberCacheVersion()));
      return;
    }

    final position = _memberListScrollController.position;
    final firstVisibleIndex = (position.pixels / _kEstimatedRowExtent).floor().clamp(0, members.length - 1);
    final lastVisibleIndex =
        ((position.pixels + position.viewportDimension) / _kEstimatedRowExtent).ceil().clamp(0, members.length - 1);
    final windowStart = (firstVisibleIndex - _kPrefetchWindow).clamp(0, members.length - 1);
    final windowEnd = (lastVisibleIndex + _kPrefetchWindow).clamp(0, members.length - 1);
    unawaited(_groupProfileWarmup
        .warmUpVisibleMembers(members.sublist(windowStart, windowEnd + 1))
        .then((_) => _bumpMemberCacheVersion()));
  }

  void _warmUpDeltaMembers(Iterable<String> newMemberUids) {
    final delta = newMemberUids.toList(growable: false);
    if (delta.isEmpty) return;
    unawaited(_groupProfileWarmup.warmUpVisibleMembers(delta).then((_) => _bumpMemberCacheVersion()));
  }

  void _bumpMemberCacheVersion() {
    if (!mounted) return;
    _memberCacheVersion.value++;
  }

  Future<void> _editGroupName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit group name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null) return;
    _groupInfoBloc.add(UpdateGroupNameRequested(
      groupId: widget.groupId,
      name: newName,
      actorUid: widget.currentUserId,
    ));
  }

  Future<void> _pickAndUpdateGroupPhoto() async {
    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;
    _groupInfoBloc.add(UpdateGroupPhotoRequested(
      groupId: widget.groupId,
      imageFile: File(picked.path),
      actorUid: widget.currentUserId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GroupInfoBloc>.value(
      value: _groupInfoBloc,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Group Info'),
          actions: [
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Report group',
              onPressed: _reportGroup,
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: 'Leave group',
              onPressed: _confirmLeaveGroup,
            ),
          ],
        ),
        body: BlocConsumer<GroupInfoBloc, GroupInfoState>(
          listener: (context, state) {
            if (state is GroupInfoErrorState) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            } else if (state is GroupInfoLeftState) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            } else if (state is GroupInfoLoadedState && !_hasTriggeredInitialWarmup) {
              _hasTriggeredInitialWarmup = true;
              _lastKnownMemberUids = state.group.cachedMemberUids.toSet();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _warmUpVisibleMemberWindow();
              });
            } else if (state is GroupInfoLoadedState) {
              final currentMemberUids = state.group.cachedMemberUids.toSet();
              final addedMemberUids = currentMemberUids.difference(_lastKnownMemberUids);
              _lastKnownMemberUids = currentMemberUids;
              if (addedMemberUids.isNotEmpty) {
                _warmUpDeltaMembers(addedMemberUids);
              }
            }
          },
          builder: (context, state) {
            if (state is GroupInfoLoading || state is GroupInfoInitial) {
              return const CommonLoadingWidget(message: 'গ্রুপ তথ্য লোড হচ্ছে…');
            }
            if (state is GroupInfoErrorState) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _groupInfoBloc.add(LoadGroupInfoEvent(widget.groupId)),
                      child: const Text('আবার চেষ্টা করুন'),
                    ),
                  ],
                ),
              );
            }
            if (state is GroupInfoLoadedState) {
              final group = state.group;
              final members = group.cachedMemberUids;
              final viewerIsAdmin = group.isAdmin(widget.currentUserId);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: (viewerIsAdmin && !state.isMutating) ? _pickAndUpdateGroupPhoto : null,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 32,
                                backgroundImage: group.groupPhotoUrl != null
                                    ? NetworkImage(group.groupPhotoUrl!)
                                    : null,
                                child: group.groupPhotoUrl == null
                                    ? const Icon(Icons.group, size: 32)
                                    : null,
                              ),
                              if (viewerIsAdmin)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      group.name,
                                      style: Theme.of(context).textTheme.headlineSmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (viewerIsAdmin)
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      tooltip: 'Edit group name',
                                      onPressed: state.isMutating ? null : () => _editGroupName(group.name),
                                    ),
                                ],
                              ),
                              Text(
                                '${members.length} members',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (viewerIsAdmin) ...[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _addMemberController,
                              enabled: !state.isMutating,
                              decoration: const InputDecoration(
                                labelText: 'Add member by user ID',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _addMember(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.person_add),
                            onPressed: state.isMutating ? null : _addMember,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  Expanded(
                    child: ListView.builder(
                      controller: _memberListScrollController,
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final uid = members[index];
                        final isCreator = uid == group.creatorId;
                        final isMemberAdmin = group.isAdmin(uid);
                        final subtitle = isCreator
                            ? 'Creator'
                            : (isMemberAdmin ? 'Admin' : null);
                        return GroupMemberPresenceScope(
                          key: ValueKey(uid),
                          memberUid: uid,
                          watchPresence: _watchMemberPresence,
                          child: GroupFriendListTile(
                            memberUid: uid,
                            cacheVersion: _memberCacheVersion,
                            subtitleOverride: subtitle,
                            trailing: (isCreator || !viewerIsAdmin)
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isMemberAdmin
                                              ? Icons.remove_moderator
                                              : Icons.admin_panel_settings_outlined,
                                        ),
                                        tooltip: isMemberAdmin ? 'Remove admin' : 'Make admin',
                                        onPressed: state.isMutating
                                            ? null
                                            : () => isMemberAdmin ? _demoteAdmin(uid) : _promoteAdmin(uid),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline),
                                        tooltip: 'Remove from group',
                                        onPressed: state.isMutating
                                            ? null
                                            : () => _confirmRemoveMember(uid),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
