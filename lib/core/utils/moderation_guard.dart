import 'package:supabase_flutter/supabase_flutter.dart';
import '../errors/exceptions.dart';

class ModerationGuard {
  final SupabaseClient supabaseClient;
  const ModerationGuard(this.supabaseClient);

  Future<void> ensureNotBlocked(String uid) async {
    final data = await supabaseClient
        .from('users')
        .select('is_disabled, is_banned, ban_type, ban_expires_at')
        .eq('id', uid)
        .maybeSingle();

    if (data == null) return;

    final isDisabled = data['is_disabled'] as bool? ?? false;
    if (isDisabled) {
      throw const ModerationBlockedException(
        message: 'Your account has been disabled by an administrator.',
      );
    }

    final isBanned = data['is_banned'] as bool? ?? false;
    if (!isBanned) return;

    final banType = data['ban_type'] as String?;
    if (banType == 'temporary') {
      final expiresAtRaw = data['ban_expires_at'] as String?;
      final expiresAt = expiresAtRaw != null ? DateTime.tryParse(expiresAtRaw) : null;
      if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
        return;
      }
    }

    throw const ModerationBlockedException(
      message: 'Your account has been banned by an administrator.',
    );
  }
}
