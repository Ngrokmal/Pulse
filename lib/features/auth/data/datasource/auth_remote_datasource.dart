import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
}

/// Phase 8.5G (Real Firebase Authentication Migration).
///
/// Replaces the previous mock implementation — every call here goes
/// through `FirebaseAuth.instance`. `FirebaseAuth.currentUser` /
/// `authStateChanges()` are the single source of truth for identity;
/// this class never fabricates a user.
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final FirebaseFirestore firestore;
  const AuthRemoteDataSourceImpl({required this.firestore});

  @override
  Future<UserModel> loginWithEmailPassword(String email, String password) async {
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Sign in did not return a user.',
        );
      }
      return UserModel.fromFirebaseUser(user);
    } on FirebaseAuthException catch (e) {
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
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Registration did not return a user.',
        );
      }
      createdUser = user;

      // Username reservation + profile creation must be atomic: either both
      // usernames/{usernameLower} and users/{uid} are created together, or
      // neither is — this is a single Firestore transaction, never a
      // separate query-then-write (which would be racy under concurrent
      // signups for the same username).
      final usernameRef = firestore.collection('usernames').doc(usernameLower);
      final userRef = firestore.collection('users').doc(user.uid);

      await firestore.runTransaction((tx) async {
        final usernameSnap = await tx.get(usernameRef);
        if (usernameSnap.exists) {
          throw const UsernameTakenException();
        }
        tx.set(usernameRef, {'uid': user.uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.set(userRef, {
          'uid': user.uid,
          'fullName': fullName.trim(),
          'username': usernameLower,
          'email': user.email ?? email,
          'photoUrl': null,
          'createdAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
        });
      });

      return UserModel.fromSignup(user, fullName: fullName.trim(), username: usernameLower);
    } on UsernameTakenException {
      await _rollbackOrphanUser(createdUser);
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw Exception(_messageForAuthError(e));
    } catch (e) {
      // Any other failure during the username/profile reservation step must
      // not leave an orphan FirebaseAuth account behind.
      await _rollbackOrphanUser(createdUser);
      throw Exception('Signup failed. Please try again.');
    }
  }

  /// Deletes a just-created FirebaseAuth user when username reservation /
  /// profile creation fails, so we never leave an Auth account with no
  /// matching Firestore profile.
  Future<void> _rollbackOrphanUser(User? user) async {
    if (user == null) return;
    try {
      await user.delete();
    } catch (_) {
      // Best-effort: if delete fails (e.g. requires-recent-login edge case),
      // there's nothing further we can safely do client-side here.
    }
  }

  @override
  Future<void> signOut() async {
    // Phase 8.5H: pending OfflineQueueManager tasks are closures bound to
    // the outgoing user's uid-scoped Firestore paths — drop them here so
    // they can't be replayed against the next signed-in session. See
    // OfflineQueueManager.clear() for the full rationale.
    OfflineQueueManager.instance.clear();
    // Bug fix (stale friend presence across accounts): friend profile cache
    // entries are already owner-scoped by uid (see
    // FriendProfileCacheService._ownerScopedKey), so a different account can
    // never read this account's entries. This call is disk hygiene on top
    // of that — without it, every account that ever signs in on this device
    // would leave its cached friend profiles on disk permanently.
    await FriendProfileCacheService.instance.clearAll();
    await FirebaseAuth.instance.signOut();
  }

  String _messageForAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'That password is too weak.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }
}
