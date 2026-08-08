import 'package:flutter_bloc/flutter_bloc.dart';
import 'auth_ui_state.dart';

class AuthUiCubit extends Cubit<AuthUiState> {
  AuthUiCubit() : super(AuthUiState.initial());

  void toggleView() => emit(state.copyWith(isLoginView: !state.isLoginView));
  void setCovered(bool covered) => emit(state.copyWith(isCovered: covered));
  void updateLookX(String text) {
    final x = (text.length - 10).clamp(-6, 6).toDouble();
    emit(state.copyWith(lookX: x));
  }
}
