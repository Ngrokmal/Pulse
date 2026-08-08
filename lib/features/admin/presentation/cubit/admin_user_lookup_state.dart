import '../../../../core/errors/failures.dart';
import '../../domain/entities/admin_user_record.dart';

abstract class AdminUserLookupState {
  const AdminUserLookupState();
}

class AdminUserLookupInitial extends AdminUserLookupState {}

class AdminUserLookupLoading extends AdminUserLookupState {}

class AdminUserLookupLoaded extends AdminUserLookupState {
  final List<AdminUserRecord> results;
  const AdminUserLookupLoaded(this.results);
}

class AdminUserLookupErrorState extends AdminUserLookupState {
  final Failure failure;
  const AdminUserLookupErrorState(this.failure);
}
