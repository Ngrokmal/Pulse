import 'package:flutter_bloc/flutter_bloc.dart';
import 'auth_state.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/register_usecase.dart';

class AuthCubit extends Cubit<AuthState> {
  final LoginUseCase loginUseCase;
  final RegisterUseCase registerUseCase;

  AuthCubit({required this.loginUseCase, required this.registerUseCase}) : super(AuthInitial());

  Future<void> login(String email, String password) async {
    emit(AuthLoading());
    final result = await loginUseCase(email: email, password: password);
    result.fold(
      (failure) => emit(AuthFailureState(failure)),
      (userEntity) => emit(AuthAuthenticated(userEntity)),
    );
  }

  Future<void> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) async {
    emit(AuthLoading());
    final result = await registerUseCase(
      fullName: fullName,
      username: username,
      email: email,
      password: password,
    );
    result.fold(
      (failure) => emit(AuthFailureState(failure)),
      (userEntity) => emit(AuthAuthenticated(userEntity)),
    );
  }
}
