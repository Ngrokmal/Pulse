import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/widgets/common_loading_widget.dart';
import '../../../../core/widgets/report_dialog.dart';
import '../../../admin/domain/usecases/report_group_usecase.dart';
import '../blocs/group_info_bloc.dart';

/// GROUP_CHAT_ALGORITHM.md ধারা ১, ৪-৫ — Milestone 3 (Group Info / Member List /
/// Add Member / Remove Member) + Milestone 4 (Leave Group) + Milestone 5
/// (Admin roles / permission gating), V1 বেসিক স্কোপ।
///
/// নোট: CreateGroupScreen-এর মতোই — এখনো প্রজেক্টে কোনো friend/user-directory
/// ফিচার নেই, তাই "Add Member"-ও সরাসরি uid টাইপ করে হয় (সাময়িক কিন্তু পূর্ণাঙ্গ
/// কার্যকরী; friend-picker আসলে শুধু এই ইনপুট অংশটি প্রতিস্থাপন করবে)। Milestone 5-এ
/// admin-only gating যোগ হয়েছে: শুধু admin (adminIds বা creator) member
/// add/remove এবং admin promote/demote করতে পারে — নন-admin viewer-দের জন্য এই
/// কন্ট্রোলগুলো UI-তে লুকানো থাকে (Bloc-ও একই পারমিশন সার্ভার-সাইড ছাড়াই ডাবল-চেক করে)।
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
  final TextEditingController _addMemberController = TextEditingController();
  // Milestone 6: photo picking নিজেই stateless/one-shot অ্যাকশন, তাই আলাদা কোনো
  // controller/state field দরকার নেই — শুধু এই একটি ImagePicker ইনস্ট্যান্স।
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _groupInfoBloc = di.sl<GroupInfoBloc>()..add(LoadGroupInfoEvent(widget.groupId));
  }

  @override
  void dispose() {
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

  // Milestone 6: group name edit — RemoveMember-এর confirm-dialog প্যাটার্নের
  // মতোই, কিন্তু confirmation-এর বদলে text-input dialog।
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
    if (newName == null) return; // dialog cancelled
    _groupInfoBloc.add(UpdateGroupNameRequested(
      groupId: widget.groupId,
      name: newName,
      actorUid: widget.currentUserId,
    ));
  }

  // Milestone 6: group photo edit — gallery থেকে একটি ছবি pick করে Bloc-এ পাঠায়;
  // upload/persist/old-photo-cleanup সবকিছু GroupInfoBloc-এ হয় (UI শুধু picking-এর
  // দায়িত্ব নেয়, Repository → UseCase → Bloc → UI প্যাটার্ন বজায় থাকে)।
  Future<void> _pickAndUpdateGroupPhoto() async {
    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return; // ইউজার picker বাতিল করেছে
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
              // leave সফল — Group Info ও Group Chat উভয় স্ক্রিন পপ করে প্রথম
              // route (Home)-এ ফিরে যাওয়া, কারণ leaving user আর এই group-এর
              // অংশ নয়।
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
          builder: (context, state) {
            if (state is GroupInfoLoading || state is GroupInfoInitial) {
              // Stability fix (item 3, 4): CommonLoadingWidget replace।
              return const CommonLoadingWidget(message: 'গ্রুপ তথ্য লোড হচ্ছে…');
            }
            if (state is GroupInfoErrorState) {
              // Stability fix (item 6 — Retry support): এই BlocConsumer-এর
              // listener ইতিমধ্যেই SnackBar দেখায় (item 11 আগে থেকেই পূরণ) —
              // এখানে শুধু retry বাটন যোগ করা হলো।
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
              // Milestone 5: viewer admin কিনা — Add Member ইনপুট ও প্রতিটি
              // member row-এর admin/remove কন্ট্রোল এই ফ্ল্যাগ দিয়ে গার্ড হয়।
              final viewerIsAdmin = group.isAdmin(widget.currentUserId);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Milestone 6: group photo avatar — শুধু admin viewer-এর
                        // জন্য tappable (camera overlay দেখা যায়), নন-admin viewer
                        // শুধু ছবি দেখে, এডিট করতে পারে না।
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
                                  // Milestone 6: নাম এডিট শুধু admin-এর জন্য।
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
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final uid = members[index];
                        final isCreator = uid == group.creatorId;
                        final isMemberAdmin = group.isAdmin(uid);
                        final subtitle = isCreator
                            ? 'Creator'
                            : (isMemberAdmin ? 'Admin' : null);
                        return ListTile(
                          key: ValueKey(uid),
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(uid),
                          subtitle: subtitle != null ? Text(subtitle) : null,
                          // creator-এর পাশে কোনো কন্ট্রোল দেখানো হয় না; বাকিদের
                          // জন্য শুধু admin viewer-এর কাছে promote/demote + remove
                          // দেখা যায় (Milestone 5)।
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
