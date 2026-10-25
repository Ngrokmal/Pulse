import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/offline_queue.dart';
import '../../../../core/services/friend_profile_cache_service.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> loginWithEmailPassword(String email, String password);
  Future<UserModel> registerWithEmailPassword({
    required String fullName,
    required String username,
    required String email,
    required String password,
  });
  Future<void> signOut();
  Future<void> sendPasswordResetEmail(String email);
  Future<void> resendEmailVerification();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient supabaseClient;
  const AuthRemoteDataSourceImpl({required this.supabaseClient});

  GoTrueClient get _auth => supabaseClient.auth;

  @override
  Future<UserModel> loginWithEmailPassword(String email, String password) async {
    try {
      final response = await _auth.signInWithPassword(email: email, password: password);
      final user = response.user;
      if (user == null) {
        throw const AuthException('Sign in did not return a user.');
      }
      return UserModel.fromSupabaseUser(user);
    } on AuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    }
  }

  @override
  Future<UserModel> registerWithEmailPassword({
    required String fullName,
    required String username,
    required String email,
    required String password,
  }) async {
    final usernameLower = username.trim().toLowerCase();
    User? createdUser;
    try {
      final response = await _auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName.trim(), 'username': usernameLower},
      );
      final user = response.user;
      if (user == null) {
        throw const AuthException('Registration did not return a user.');
      }
      createdUser = user;

      try {
        await supabaseClient
            .from('users')
            .update({'full_name': fullName.trim(), 'username': usernameLower})
            .eq('id', user.id);
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          throw const UsernameTakenException();
        }
        rethrow;
      }

      return UserModel.fromSignup(user, fullName: fullName.trim(), username: usernameLower);
    } on UsernameTakenException {
      await _rollbackOrphanUser(createdUser);
      rethrow;
    } on AuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    } catch (e) {
      await _rollbackOrphanUser(createdUser);
      throw Exception('Signup failed. Please try again.');
    }
  }

  Future<void> _rollbackOrphanUser(User? user) async {
    if (user == null) return;
    try {
      await _auth.signOut();
    } catch (_) {
    }
  }

  @override
  Future<void> signOut() async {
    OfflineQueueManager.instance.clear();
    await FriendProfileCacheService.instance.clearAll();
    await _auth.signOut();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    }
  }

  @override
  Future<void> resendEmailVerification() async {
    final email = _auth.currentUser?.email;
    if (email == null) {
      throw Exception('No signed-in user to verify.');
    }
    try {
      await _auth.resend(type: OtpType.signup, email: email);
    } on AuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    }
  }

  String _messageForAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) return 'Incorrect email or password.';
    if (msg.contains('email not confirmed')) return 'Please verify your email before signing in.';
    if (msg.contains('user already registered')) return 'An account already exists for that email.';
    if (msg.contains('password') && msg.contains('least')) return 'That password is too weak.';
    if (msg.contains('rate limit')) return 'Too many attempts. Please try again later.';
    if (msg.contains('network')) return 'Network error. Please check your connection.';
    return e.message.isNotEmpty ? e.message : 'Authentication failed.';
  }
}
