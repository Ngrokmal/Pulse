import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../domain/usecases/create_group_usecase.dart';

const _kActionTimeout = Duration(seconds: 15);

abstract class GroupEvent {}

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
