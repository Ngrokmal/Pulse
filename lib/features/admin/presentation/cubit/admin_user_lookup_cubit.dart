import 'package:flutter_bloc/flutter_bloc.dart';
import 'admin_user_lookup_state.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/admin_user_record.dart';
import '../../domain/usecases/lookup_user_by_uid_usecase.dart';
import '../../domain/usecases/lookup_users_by_username_usecase.dart';

/// Phase 8.6A (Admin Foundation)
///
/// A search term is tried both as an exact uid and as a username prefix,
/// since admins may have either on hand. Results are merged and deduped
/// by uid.
class AdminUserLookupCubit extends Cubit<AdminUserLookupState> {
  final LookupUserByUidUseCase lookupUserByUidUseCase;
  final LookupUsersByUsernameUseCase lookupUsersByUsernameUseCase;

  AdminUserLookupCubit({
    required this.lookupUserByUidUseCase,
    required this.lookupUsersByUsernameUseCase,
  }) : super(AdminUserLookupInitial());

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      emit(AdminUserLookupInitial());
      return;
    }

    emit(AdminUserLookupLoading());

    final byUidResult = await lookupUserByUidUseCase(trimmed);
    final byUsernameResult = await lookupUsersByUsernameUseCase(trimmed);

    final failure = byUsernameResult.fold<Failure?>((f) => f, (_) => null) ?? byUidResult.fold<Failure?>((f) => f, (_) => null);
    final byUsername = byUsernameResult.fold<List<AdminUserRecord>>((_) => const <AdminUserRecord>[], (list) => list);
    final byUid = byUidResult.fold<AdminUserRecord?>((_) => null, (record) => record);

    final merged = <String, AdminUserRecord>{};
    if (byUid != null) merged[byUid.profile.uid] = byUid;
    for (final record in byUsername) {
      merged[record.profile.uid] = record;
    }

    if (merged.isEmpty && failure != null) {
      emit(AdminUserLookupErrorState(failure));
      return;
    }

    emit(AdminUserLookupLoaded(merged.values.toList()));
  }
}
