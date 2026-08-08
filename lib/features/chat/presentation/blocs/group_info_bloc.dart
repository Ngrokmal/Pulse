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

class UpdateGroupNameRequested extends GroupInfoEvent {
  final String groupId;
  final String name;
  final String actorUid;
  UpdateGroupNameRequested({required this.groupId, required this.name, required this.actorUid});
}

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
  final bool isMutating;
  GroupInfoLoadedState({required this.group, this.isMutating = false});
}

class GroupInfoErrorState extends GroupInfoState {
  final String message;
  GroupInfoErrorState({required this.message});
}

class GroupInfoLeftState extends GroupInfoState {}

class GroupInfoBloc extends Bloc<GroupInfoEvent, GroupInfoState> {
  final StreamGroupUseCase streamGroupUseCase;
  final AddMemberUseCase addMemberUseCase;
  final RemoveMemberUseCase removeMemberUseCase;
  final LeaveGroupUseCase leaveGroupUseCase;
  final PromoteAdminUseCase promoteAdminUseCase;
  final DemoteAdminUseCase demoteAdminUseCase;
  final UpdateGroupNameUseCase updateGroupNameUseCase;
  final UploadGroupPhotoUseCase uploadGroupPhotoUseCase;
  final UpdateGroupPhotoUseCase updateGroupPhotoUseCase;
  final DeleteGroupPhotoUseCase deleteGroupPhotoUseCase;

  GroupEntity? _currentGroup;
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

      bool firstSnapshotReceived = false;
      _loadTimeoutTimer?.cancel();
      _loadTimeoutTimer = Timer(_kLoadTimeout, () {
        if (!firstSnapshotReceived && !emit.isDone) {
          emit(GroupInfoErrorState(message: 'লোড হতে সময় বেশি লাগছে। আবার চেষ্টা করুন।'));
        }
      });

      await emit.forEach<GroupEntity>(
        streamGroupUseCase(event.groupId).distinct(),
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
        await addMemberUseCase(groupId: event.groupId, uid: trimmedUid, actorUid: event.actorUid).timeout(_kActionTimeout);
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });

    on<RemoveMemberRequested>((event, emit) async {
      final current = _currentGroup;
      if (current == null) return;

      if (!current.isAdmin(event.actorUid)) {
        emit(GroupInfoErrorState(message: 'Only group admins can remove members'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

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
        emit(GroupInfoLeftState());
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });

    on<PromoteAdminRequested>((event, emit) async {
      final current = _currentGroup;
      if (current == null) return;

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

      if (!current.isAdmin(event.actorUid)) {
        emit(GroupInfoErrorState(message: 'Only group admins can edit the group photo'));
        emit(GroupInfoLoadedState(group: current));
        return;
      }

      emit(GroupInfoLoadedState(group: current, isMutating: true));
      try {
        final uploadResult = await uploadGroupPhotoUseCase(file: event.imageFile).timeout(_kActionTimeout);
        await updateGroupPhotoUseCase(
          groupId: event.groupId,
          photoUrl: uploadResult.secureUrl,
          publicId: uploadResult.publicId,
          actorUid: event.actorUid,
        ).timeout(_kActionTimeout);
        final oldPublicId = current.groupPhotoPublicId;
        if (oldPublicId != null && oldPublicId.isNotEmpty) {
          try {
            await deleteGroupPhotoUseCase(publicId: oldPublicId);
          } catch (_) {
          }
        }
      } catch (error) {
        emit(GroupInfoErrorState(message: friendlyErrorMessage(error)));
        emit(GroupInfoLoadedState(group: current));
      }
    });
  }

  @override
  Future<void> close() async {
    _loadTimeoutTimer?.cancel();
    return super.close();
  }
}
