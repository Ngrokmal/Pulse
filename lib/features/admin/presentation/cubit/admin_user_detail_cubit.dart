import 'package:flutter_bloc/flutter_bloc.dart';
import 'admin_user_detail_state.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/ban_record.dart';
import '../../domain/entities/ban_type.dart';
import '../../domain/entities/user_warning.dart';
import '../../domain/usecases/ban_user_usecase.dart';
import '../../domain/usecases/disable_account_usecase.dart';
import '../../domain/usecases/get_ban_history_usecase.dart';
import '../../domain/usecases/get_user_warnings_usecase.dart';
import '../../domain/usecases/issue_warning_usecase.dart';
import '../../domain/usecases/lookup_user_by_uid_usecase.dart';
import '../../domain/usecases/restore_account_usecase.dart';
import '../../domain/usecases/unban_user_usecase.dart';

class AdminUserDetailCubit extends Cubit<AdminUserDetailState> {
  final String uid;
  final String adminUid;
  final LookupUserByUidUseCase lookupUserByUidUseCase;
  final BanUserUseCase banUserUseCase;
  final UnbanUserUseCase unbanUserUseCase;
  final DisableAccountUseCase disableAccountUseCase;
  final RestoreAccountUseCase restoreAccountUseCase;
  final GetBanHistoryUseCase getBanHistoryUseCase;
  final GetUserWarningsUseCase getUserWarningsUseCase;
  final IssueWarningUseCase issueWarningUseCase;

  AdminUserDetailCubit({
    required this.uid,
    required this.adminUid,
    required this.lookupUserByUidUseCase,
    required this.banUserUseCase,
    required this.unbanUserUseCase,
    required this.disableAccountUseCase,
    required this.restoreAccountUseCase,
    required this.getBanHistoryUseCase,
    required this.getUserWarningsUseCase,
    required this.issueWarningUseCase,
  }) : super(AdminUserDetailLoading());

  Future<void> load() async {
    emit(AdminUserDetailLoading());
    final result = await lookupUserByUidUseCase(uid);
    final warningsResult = await getUserWarningsUseCase(uid);
    final warnings = warningsResult.fold<List<UserWarning>>((_) => const [], (list) => list);
    final banHistoryResult = await getBanHistoryUseCase(uid);
    final banHistory = banHistoryResult.fold<List<BanRecord>>((_) => const [], (list) => list);
    result.fold(
      (failure) => emit(AdminUserDetailErrorState(failure)),
      (record) => record == null
          ? emit(AdminUserDetailNotFound())
          : emit(AdminUserDetailLoaded(record, warnings: warnings, banHistory: banHistory)),
    );
  }

  Future<void> issueWarning(String reason) async {
    final current = state;
    if (current is! AdminUserDetailLoaded) return;
    emit(AdminUserDetailLoaded(current.record,
        warnings: current.warnings, banHistory: current.banHistory, actionInProgress: true));
    final result = await issueWarningUseCase(userUid: uid, reason: reason, issuedBy: adminUid);
    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      emit(AdminUserDetailErrorState(failure));
    } else {
      await load();
    }
  }

  Future<void> ban({required String reason, required BanType type, DateTime? expiresAt}) async {
    final current = state;
    if (current is! AdminUserDetailLoaded) return;
    emit(AdminUserDetailLoaded(current.record,
        warnings: current.warnings, banHistory: current.banHistory, actionInProgress: true));
    final result = await banUserUseCase(
      targetUid: uid,
      reason: reason,
      issuedBy: adminUid,
      type: type,
      expiresAt: expiresAt,
    );
    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      emit(AdminUserDetailErrorState(failure));
    } else {
      await load();
    }
  }

  Future<void> unban() async {
    final current = state;
    if (current is! AdminUserDetailLoaded) return;
    emit(AdminUserDetailLoaded(current.record,
        warnings: current.warnings, banHistory: current.banHistory, actionInProgress: true));
    final result = await unbanUserUseCase(targetUid: uid, issuedBy: adminUid);
    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      emit(AdminUserDetailErrorState(failure));
    } else {
      await load();
    }
  }

  Future<void> disable() async {
    final current = state;
    if (current is! AdminUserDetailLoaded) return;
    emit(AdminUserDetailLoaded(current.record,
        warnings: current.warnings, banHistory: current.banHistory, actionInProgress: true));
    final result = await disableAccountUseCase(targetUid: uid, issuedBy: adminUid);
    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      emit(AdminUserDetailErrorState(failure));
    } else {
      await load();
    }
  }

  Future<void> restore() async {
    final current = state;
    if (current is! AdminUserDetailLoaded) return;
    emit(AdminUserDetailLoaded(current.record,
        warnings: current.warnings, banHistory: current.banHistory, actionInProgress: true));
    final result = await restoreAccountUseCase(targetUid: uid, issuedBy: adminUid);
    final failure = result.fold<Failure?>((f) => f, (_) => null);
    if (failure != null) {
      emit(AdminUserDetailErrorState(failure));
    } else {
      await load();
    }
  }
}
