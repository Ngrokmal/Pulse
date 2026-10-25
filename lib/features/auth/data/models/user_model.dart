import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.uid,
    required super.email,
    super.displayName,
    super.fullName,
    super.username,
    super.emailVerified,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      fullName: json['fullName'] as String?,
      username: json['username'] as String?,
      emailVerified: json['emailVerified'] as bool? ?? false,
    );
  }

  factory UserModel.fromSupabaseUser(sb.User user) {
    final meta = user.userMetadata ?? const {};
    return UserModel(
      uid: user.id,
      email: user.email ?? '',
      displayName: meta['full_name'] as String?,
      fullName: meta['full_name'] as String?,
      username: meta['username'] as String?,
      emailVerified: user.emailConfirmedAt != null,
    );
  }

  factory UserModel.fromSignup(sb.User user, {required String fullName, required String username}) {
    return UserModel(
      uid: user.id,
      email: user.email ?? '',
      displayName: fullName,
      fullName: fullName,
      username: username,
      emailVerified: user.emailConfirmedAt != null,
    );
  }
}
