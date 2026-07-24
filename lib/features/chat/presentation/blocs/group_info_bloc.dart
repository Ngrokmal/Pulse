import 'dart:async';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../domain/entities/group_entity.dart';
import '../../domain/usecases/add_member_usecase.dart';
import '../../domain/usecases/delete_group_photo_usecase.dart';
import '../../domain/usecases/demote_admin_usecase.dart';
import '../../domain/usecases/leave_group_usecase.dart';
import '../../domain/usecases/promote_admin_usecase.dart';
import '../../domain/usecases/remove_member_usecase.dart';
import '../../domain/usecases/stream_group_usecase.dart';
import '../../domain/usecases/update_group_name_usecase.dart';
import '../../domain/usecases/update_group_photo_usecase.dart';
import '../../domain/usecases/upload_group_photo_usecase.dart';

// Stability + Loading + Error Handling মাইলস্টোন: ChatBloc-এর একই
// timeout ধ্রুবকগুলো (নিচে ব্যবহার — LoadGroupInfoEvent-এর প্রথম-snapshot
// গার্ড + প্রতিটি mutating action-এর bounded wait, যাতে isMutating flag
// কখনো স্থায়ীভাবে আটকে না থাকে — "infinite loading" fix)।
const _kLoadTimeout = Duration(seconds: 15);
const _kActionTimeout = Duration(seconds: 15);

abstract class GroupInfoEvent {}

class LoadGroupInfoEvent extends GroupInfoEvent {
  final String groupId;
  LoadGroupInfoEvent(this.groupId);
}

class AddMemberRequested extends GroupInfoEvent {
  final String groupId;
  final String uid;
  // Milestone 5: actorUid — যিনি এই action চালাচ্ছেন, admin-permission চেকের জন্য।
  final String actorUid;
  AddMemberRequested({required this.groupId, required this.uid, required this.actorUid});
}

class RemoveMemberRequested extends GroupInfoEvent {
  final String groupId;
  final String uid;
  final String actorUid;
  RemoveMemberRequested({required this.groupId, required this.uid, required this.actorUid});
}

class LeaveGroupRequested extends GroupInfoEvent {
  final String groupId;
  final String uid;
  LeaveGroupRequested({required this.groupId, required this.uid});
}

/// Milestone 5: admin role toggle events। uid = টার্গেট মেম্বার, actorUid = যিনি
/// promote/demote করছেন (permission check-এর জন্য)।
class PromoteAdminRequested extends GroupInfoEvent {
  final String groupId;
  final String uid;
  final String actorUid;
  PromoteAdminRequested({required this.groupId, required this.uid, required this.actorUid});
}

class DemoteAdminRequested extends GroupInfoEvent {
  final String groupId;
  final String uid;
  final String actorUid;
  DemoteAdminRequested({required this.groupId, required this.uid, required this.actorUid});
}

/// Milestone 6: group name/photo edit events। actorUid — permission চেকের
/// জন্য (AddMemberRequested-এর মতোই প্যাটার্ন)।
class UpdateGroupNameRequested extends GroupInfoEvent {
  final String groupId;
  final String name;
  final String actorUid;
  UpdateGroupNameRequested({required this.groupId, required this.name, required this.actorUid});
}

/// [imageFile] ইতিমধ্যে picked/local ফাইল (image_picker থেকে) — UI-লেয়ার
/// picking-এর দায়িত্ব নেয়, Bloc শুধু upload + persist + old-photo-cleanup করে।
class UpdateGroupPhotoRequested extends GroupInfoEvent {
  final String groupId;
  final File imageFile;
  final String actorUid;
  UpdateGroupPhotoRequested({required this.groupId, required this.imageFile, required this.actorUid});
}

abstract class GroupInfoState {}

class GroupInfoInitial extends GroupInfoState {}

class GroupInfoLoading extends GroupInfoState {}

class GroupInfoLoadedState extends GroupInfoState {
  final GroupEntity group;
  // Add/Remove/Promote/Demote চলাকালীন সাময়িক UI-lock — Firestore write সম্পন্ন
  // হওয়ার পর streamGroup listener-ই আসল রিফ্রেশড GroupInfoLoadedState পাঠাবে।
  final bool isMutating;
  GroupInfoLoadedState({required this.group, this.isMutating = false});
}

class GroupInfoErrorState extends GroupInfoState {
  final String message;
  GroupInfoErrorState({required this.message});
}

/// Milestone 4: leaveGroupUseCase সফল হওয়ার পর terminal state — screen এই state
/// শুনে Group Info + Group Chat উভয় স্ক্রিন থেকে pop করে Home-এ ফিরে যায়, কারণ
/// leaving user আর এই group-এর সদস্য নয় (group deleted হয়ে থাকতে পারে বা নাও পারে)।
class GroupInfoLeftState extends GroupInfoState {}

/// GroupChatBloc-এর সাথে সামঞ্জস্যপূর্ণ প্যাটার্ন: LoadGroupInfoEvent একটি ইনফিনিট
/// স্ট্রিমের ওপর emit.forEach চালায় (bloc-এর ডিফল্ট concurrent transformer-এর কারণে
/// অন্যান্য event type সমান্তরালে প্রসেস হতে কোনো বাধা নেই — GroupChatBloc.LoadGroupMessagesEvent-এও একই প্যাটার্ন)।
class GroupInfoBloc extends Bloc<GroupInfoEvent, GroupInfoState> {
  final StreamGroupUseCase streamGroupUseCase;
  final AddMemberUseCase addMemberUseCase;
  final RemoveMemberUseCase removeMemberUseCase;
  final LeaveGroupUseCase leaveGroupUseCase;
  final PromoteAdminUseCase promoteAdminUseCase;
  final DemoteAdminUseCase demoteAdminUseCase;
  // Milestone 6
  final UpdateGroupNameUseCase updateGroupNameUseCase;
  final UploadGroupPhotoUseCase uploadGroupPhotoUseCase;
  final UpdateGroupPhotoUseCase updateGroupPhotoUseCase;
  final DeleteGroupPhotoUseCase deleteGroupPhotoUseCase;

  GroupEntity? _currentGroup;
  // Stability fix: ChatBloc._loadTimeoutTimer-এর সমতুল্য — LoadGroupInfoEvent-এর
  // প্রথম snapshot guard-এর জন্য (নিচে দেখুন), close()-এ cancel করা হয়।
  Timer? _loadTimeoutTimer;

  GroupInfoBloc({
    required this.streamGroupUseCase,
    required this.addMemberUseCase,
    required this.removeMemberUseCase,
    required this.leaveGroupUseCase,
    required this.promoteAdminUseCase,
    required this.demoteAdminUseCase,
    required this.updateGroupNameUseCase,
    required this.uploadGroupPhotoUseCase,
    required this.updateGroupPhotoUseCase,
    required this.deleteGroupPhotoUseCase,
  }) : super(GroupInfoInitial()) {
    on<LoadGroupInfoEvent>((event, emit) async {
      emit(GroupInfoLoading());

      // Stability fix (Prevent infinite loading): ChatBloc/GroupChatBloc-এর
      // একই timeout-guard প্যাটার্ন — প্রথম group snapshot ১৫s-এর মধ্যে না
      // এলে retry-able error emit হয়, স্ট্রিম চালু থাকে (দেরিতে ডেটা এলে
      // self-heal)।
      bool firstSnapshotReceived = false;
      _loadTimeoutTimer?.cancel();
      _loadTimeoutTimer = Timer(_kLoadTimeout, () {
        if (!firstSnapshotReceived && !emit.isDone) {
          emit(GroupInfoErrorState(message: 'লোড হতে সময় বেশি লাগছে। আবার চেষ্টা করুন।'));
        }
      });

      await emit.forEach<GroupEntity>(
        streamGroupUseCase(event.groupId),
        onData: (group) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          _currentGroup = group;
          return GroupInfoLoadedState(group: group);
        },
        onError: (error, stackTrace) {
          firstSnapshotReceived = true;
          _loadTimeoutTimer?.cancel();
          return GroupInfoErrorState(message: friendlyErrorMessage(error));
        },
      );
      _loadTimeoutTimer?.cancel();
    });

    on<AddMemberRequested>((event, emit) async {
      final current = _currentGroup;
      if (current == null) return;

      // Milestone 5: শুধু admin (adminIds বা creator) member add করতে পারবে।
      if (!current.isAdmin(event.actorUid)) {
        emit(GroupInfoErrorState(message: 'Only group admins can add members'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      final trimmedUid = event.uid.trim();
      if (trimmedUid == current.creatorId || current.cachedMemberUids.contains(trimmedUid)) {
        emit(GroupInfoErrorState(message: 'User is already a member'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      emit(GroupInfoLoadedState(group: current, isMutating: true));
      try {
        // Stability fix (Prevent infinite loading): timeout ছাড়া isMutating
        // flag স্থায়ী নেটওয়ার্ক-ডাউন অবস্থায় চিরকাল true থেকে যেত (permanent
        // disabled UI) — OfflineQueueManager fix-এর কারণে এখন এই await real
        // ব্যর্থতাও ধরতে পারে।
        await addMemberUseCase(groupId: event.groupId, uid: trimmedUid, actorUid: event.actorUid).timeout(_kActionTimeout);
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });

    on<RemoveMemberRequested>((event, emit) async {
      final current = _currentGroup;
      if (current == null) return;

      // Milestone 5: শুধু admin member remove করতে পারবে।
      if (!current.isAdmin(event.actorUid)) {
        emit(GroupInfoErrorState(message: 'Only group admins can remove members'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      // GROUP_CHAT_ALGORITHM.md ধারা ৫: creator অপসারণ এখনো পরিকল্পিত ফ্লোর অংশ
      // (last-admin/orphan-group হ্যান্ডলিং নেই), তাই V1-এ creator-কে remove করা
      // যাবে না — ইচ্ছাকৃত গার্ড, admin-permission gating-এর পাশাপাশি বজায় থাকে।
      if (event.uid == current.creatorId) {
        emit(GroupInfoErrorState(message: 'The group creator cannot be removed'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      emit(GroupInfoLoadedState(group: current, isMutating: true));
      try {
        await removeMemberUseCase(groupId: event.groupId, uid: event.uid, actorUid: event.actorUid).timeout(_kActionTimeout);
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });

    on<LeaveGroupRequested>((event, emit) async {
      final current = _currentGroup;
      if (current == null) return;

      emit(GroupInfoLoadedState(group: current, isMutating: true));
      try {
        await leaveGroupUseCase(groupId: event.groupId, uid: event.uid).timeout(_kActionTimeout);
        // group deleted হোক বা শুধু self-removed — উভয় ক্ষেত্রেই leaving user-এর
        // জন্য এই screen আর প্রাসঙ্গিক নয়, তাই terminal state emit করা হয়।
        emit(GroupInfoLeftState());
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });

    on<PromoteAdminRequested>((event, emit) async {
      final current = _currentGroup;
      if (current == null) return;

      // Milestone 5: শুধু বিদ্যমান admin অন্য member-কে admin বানাতে পারবে।
      if (!current.isAdmin(event.actorUid)) {
        emit(GroupInfoErrorState(message: 'Only group admins can promote other admins'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }
      if (!current.cachedMemberUids.contains(event.uid)) {
        emit(GroupInfoErrorState(message: 'User is not a member of this group'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }
      if (current.isAdmin(event.uid)) {
        emit(GroupInfoErrorState(message: 'User is already an admin'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      emit(GroupInfoLoadedState(group: current, isMutating: true));
      try {
        await promoteAdminUseCase(groupId: event.groupId, uid: event.uid, actorUid: event.actorUid).timeout(_kActionTimeout);
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });

    on<DemoteAdminRequested>((event, emit) async {
      final current = _currentGroup;
      if (current == null) return;

      if (!current.isAdmin(event.actorUid)) {
        emit(GroupInfoErrorState(message: 'Only group admins can demote other admins'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }
      // creator সবসময় implicit admin (GroupEntity.isAdmin) — demote করা যাবে না,
      // নাহলে group orphan হয়ে যাবে (কোনো ownership-transfer trigger হয় না এখানে,
      // শুধু leaveGroup-এ হয়)।
      if (event.uid == current.creatorId) {
        emit(GroupInfoErrorState(message: 'The group creator cannot be demoted'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      emit(GroupInfoLoadedState(group: current, isMutating: true));
      try {
        await demoteAdminUseCase(groupId: event.groupId, uid: event.uid, actorUid: event.actorUid).timeout(_kActionTimeout);
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });

    on<UpdateGroupNameRequested>((event, emit) async {
      final current = _currentGroup;
      if (current == null) return;

      // Milestone 6: শুধু admin group name এডিট করতে পারবে।
      if (!current.isAdmin(event.actorUid)) {
        emit(GroupInfoErrorState(message: 'Only group admins can edit the group name'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      final trimmedName = event.name.trim();
      if (trimmedName.isEmpty) {
        emit(GroupInfoErrorState(message: 'Group name cannot be empty'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }
      if (trimmedName == current.name) {
        // কোনো পরিবর্তন নেই — no-op, নতুন write দরকার নেই।
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      emit(GroupInfoLoadedState(group: current, isMutating: true));
      try {
        await updateGroupNameUseCase(groupId: event.groupId, name: trimmedName, actorUid: event.actorUid).timeout(_kActionTimeout);
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });

    on<UpdateGroupPhotoRequested>((event, emit) async {
      final current = _currentGroup;
      if (current == null) return;

      // Milestone 6: শুধু admin group photo এডিট করতে পারবে।
      if (!current.isAdmin(event.actorUid)) {
        emit(GroupInfoErrorState(message: 'Only group admins can edit the group photo'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      emit(GroupInfoLoadedState(group: current, isMutating: true));
      try {
        // ধাপ ১: নতুন ছবি Cloudinary-তে upload। Stability fix (Prevent
        // Cloudinary hanging): media_repository_impl.dart-এ নিজেই এখন ১৫s
        // internal timeout আছে (HTTP request level) — এখানে usecase-level
        // timeout defense-in-depth হিসেবে রাখা হলো, isMutating flag চিরকাল
        // আটকে না থাকে তা নিশ্চিত করতে।
        final uploadResult = await uploadGroupPhotoUseCase(file: event.imageFile).timeout(_kActionTimeout);
        // ধাপ ২: Firestore-এ নতুন url/publicId persist — এটি সফল হলেই নতুন
        // ছবি "live" ধরা হয়, তাই delete-before-persist না করে persist-before-delete।
        await updateGroupPhotoUseCase(
          groupId: event.groupId,
          photoUrl: uploadResult.secureUrl,
          publicId: uploadResult.publicId,
          actorUid: event.actorUid,
        ).timeout(_kActionTimeout);
        // ধাপ ৩: পুরনো Cloudinary asset ডিলিট — best-effort। নতুন ছবি ইতিমধ্যে
        // persist হয়ে গেছে, তাই এই ধাপ ব্যর্থ হলেও ইউজারের group photo update
        // ব্যর্থ হিসেবে দেখানো হয় না (শুধু orphaned Cloudinary asset থেকে যায় —
        // known limitation, handoff-এ নোট করা আছে)। media_repository_impl-এর
        // নিজস্ব timeout ইতিমধ্যেই এই কল বাউন্ডেড রাখে।
        final oldPublicId = current.groupPhotoPublicId;
        if (oldPublicId != null && oldPublicId.isNotEmpty) {
          try {
            await deleteGroupPhotoUseCase(publicId: oldPublicId);
          } catch (_) {
            // silently ignored — ইচ্ছাকৃত, উপরের কমেন্ট দেখুন।
          }
        }
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });
  }

  // নোট: groupRepository.close() এখনো ইচ্ছাকৃতভাবে কল করা হয় না।
  // groupRepository DI-তে lazy singleton (GroupChatBloc-এর সাথে shared), এবং
  // close() সেই singleton-এর _groupMessagesSubscription বাতিল করে দিত।
  // GroupInfoScreen যদি GroupChatScreen-এর ওপরে push করা হয় (এখনো নিচে সক্রিয়) এবং
  // আগে pop হয়, তাহলে এখানে repository.close() কল করলে নিচের চ্যাট স্ট্রিম ভেঙে যেত।
  // streamGroup-এর নিজস্ব StreamController-এর onCancel ইতিমধ্যেই bloc বন্ধ হলে
  // সাবস্ক্রিপশন cleanup করে (GroupChatBloc-এও এখন এই একই প্যাটার্ন প্রয়োগ করা
  // হয়েছে — এই মাইলস্টোনের "Shared GroupRepository lifecycle" fix)।
  //
  // Stability fix: শুধু নিজস্ব local `_loadTimeoutTimer` cancel করতে close()
  // override করা হলো (repository-touching কিছু নয়, dangling Timer এড়াতে)।
  @override
  Future<void> close() async {
    _loadTimeoutTimer?.cancel();
    return super.close();
  }
}
