import 'package:cloud_firestore/cloud_firestore.dart';
import '../errors/exceptions.dart';

class ModerationGuard {
  final FirebaseFirestore firestore;
  const ModerationGuard(this.firestore);

  Future<void> ensureNotBlocked(String uid) async {
    final doc = await firestore.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return;

    final isDisabled = data['isDisabled'] as bool? ?? false;
    if (isDisabled) {
      throw const ModerationBlockedException(
        message: 'Your account has been disabled by an administrator.',
      );
    }

    final isBanned = data['isBanned'] as bool? ?? false;
    if (!isBanned) return;

    final banType = data['banType'] as String?;
    if (banType == 'temporary') {
      final expiresAt = data['banExpiresAt'];
      if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
        return;
      }
    }

    throw const ModerationBlockedException(
      message: 'Your account has been banned by an administrator.',
    );
  }
}
