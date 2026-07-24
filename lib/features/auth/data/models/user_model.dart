import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.uid,
    required super.email,
    super.displayName,
    super.fullName,
    super.username,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      fullName: json['fullName'] as String?,
      username: json['username'] as String?,
    );
  }

  /// Phase 8.5G: builds a UserModel straight from the authenticated
  /// FirebaseAuth user — this is the only place a UserModel should
  /// originate from now that mock login is gone.
  factory UserModel.fromFirebaseUser(fb.User user) {
    return UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
    );
  }

  /// Signup feature: builds a UserModel from the just-created FirebaseAuth
  /// user plus the fullName/username captured on the signup form (these
  /// aren't available on `fb.User` itself since they live in the
  /// users/{uid} Firestore profile, not FirebaseAuth's own record).
  factory UserModel.fromSignup(fb.User user, {required String fullName, required String username}) {
    return UserModel(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      fullName: fullName,
      username: username,
    );
  }
}
