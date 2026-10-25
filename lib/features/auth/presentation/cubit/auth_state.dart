import '../../../../core/errors/failures.dart';
import '../../domain/entities/user_entity.dart';

abstract class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class AuthAuthenticated extends AuthState {
  final UserEntity user;
  const AuthAuthenticated(this.user);
}
class AuthFailureState extends AuthState {
  final Failure failure;
  const AuthFailureState(this.failure);
}
