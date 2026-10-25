class AuthorizationResult {
  final bool allowed;
  final String? reason;

  const AuthorizationResult._(this.allowed, this.reason);

  const AuthorizationResult.allow() : this._(true, null);

  const AuthorizationResult.deny(String reason) : this._(false, reason);
}
