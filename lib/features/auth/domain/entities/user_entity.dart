class UserEntity {
  final String uid;
  final String email;
  final String? displayName;
  final String? fullName;
  final String? username;

  const UserEntity({
    required this.uid,
    required this.email,
    this.displayName,
    this.fullName,
    this.username,
  });
}
