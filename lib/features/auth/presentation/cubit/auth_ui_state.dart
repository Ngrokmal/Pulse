class AuthUiState {
  final bool isLoginView;
  final bool isCovered;
  final double lookX;

  const AuthUiState({
    required this.isLoginView,
    required this.isCovered,
    required this.lookX,
  });

  factory AuthUiState.initial() => const AuthUiState(isLoginView: true, isCovered: false, lookX: 0.0);

  AuthUiState copyWith({bool? isLoginView, bool? isCovered, double? lookX}) {
    return AuthUiState(
      isLoginView: isLoginView ?? this.isLoginView,
      isCovered: isCovered ?? this.isCovered,
      lookX: lookX ?? this.lookX,
    );
  }
}
