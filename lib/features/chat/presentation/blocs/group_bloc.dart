import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../domain/usecases/create_group_usecase.dart';

// Stability + Loading + Error Handling মাইলস্টোন: ChatBloc-এর একই
// action-timeout ধ্রুবক — Firestore batch write (group creation) কখনো
// hang করলে GroupCreating state-এ চিরকাল আটকে না থাকার জন্য।
const _kActionTimeout = Duration(seconds: 15);

abstract class GroupEvent {}

/// GROUP_CHAT_ALGORITHM.md ধারা ১: creator + নূন্যতম ২ জন সদস্য (মোট ৩+)।
/// [memberUids]-এ creator বাদে বাকি সদস্যদের uid থাকে।
class CreateGroupRequested extends GroupEvent {
  final String name;
  final String creatorId;
  final List<String> memberUids;

  CreateGroupRequested({
    required this.name,
    required this.creatorId,
    required this.memberUids,
  });
}

abstract class GroupState {}

class GroupInitial extends GroupState {}

class GroupCreating extends GroupState {}

class GroupCreatedState extends GroupState {
  final String groupId;
  GroupCreatedState({required this.groupId});
}

class GroupErrorState extends GroupState {
  final String message;
  GroupErrorState({required this.message});
}

class GroupBloc extends Bloc<GroupEvent, GroupState> {
  final CreateGroupUseCase createGroupUseCase;

  GroupBloc({required this.createGroupUseCase}) : super(GroupInitial()) {
    on<CreateGroupRequested>((event, emit) async {
      // GROUP_CHAT_ALGORITHM.md ধারা ১: গ্রুপ নাম আবশ্যক, নূন্যতম ২ জন member
      // (creator-সহ মোট ৩+)। এই validation বর্তমান প্রজেক্টের অন্যান্য Bloc-এর
      // প্যাটার্নের (ChatListBloc._filtered) মতো Bloc স্তরেই রাখা হয়েছে, কারণ
      // বিদ্যমান UseCase-গুলোর কোনোটিতেই ভ্যালিডেশন লজিক নেই (পাতলা wrapper-only)।
      final trimmedName = event.name.trim();
      if (trimmedName.isEmpty) {
        emit(GroupErrorState(message: 'Group name is required'));
        return;
      }
      final uniqueMembers = event.memberUids.toSet()..remove(event.creatorId);
      if (uniqueMembers.length < 2) {
        emit(GroupErrorState(
          message: 'Select at least 2 other members to create a group',
        ));
        return;
      }

      emit(GroupCreating());
      try {
        final groupId = await createGroupUseCase(
          name: trimmedName,
          creatorId: event.creatorId,
          initialMembers: [event.creatorId, ...uniqueMembers],
        ).timeout(_kActionTimeout);
        emit(GroupCreatedState(groupId: groupId));
      } catch (error) {
        emit(GroupErrorState(message: friendlyErrorMessage(error)));
      }
    });
  }
}
