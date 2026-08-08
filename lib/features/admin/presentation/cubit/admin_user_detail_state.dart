import '../../../../core/errors/failures.dart';
import '../../domain/entities/admin_user_record.dart';
import '../../domain/entities/ban_record.dart';
import '../../domain/entities/user_warning.dart';

abstract class AdminUserDetailState {
  const AdminUserDetailState();
}

class AdminUserDetailLoading extends AdminUserDetailState {}

class AdminUserDetailLoaded extends AdminUserDetailState {
  final AdminUserRecord record;
  final List<UserWarning> warnings;
  final List<BanRecord> banHistory;
  final bool actionInProgress;
  const AdminUserDetailLoaded(
    this.record, {
    this.warnings = const [],
    this.banHistory = const [],
    this.actionInProgress = false,
  });
}

class AdminUserDetailNotFound extends AdminUserDetailState {}

class AdminUserDetailErrorState extends AdminUserDetailState {
  final Failure failure;
  const AdminUserDetailErrorState(this.failure);
}
