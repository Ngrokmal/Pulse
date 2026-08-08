import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class PushNotificationSenderService {
  final http.Client client;
  final SupabaseClient supabase;

  PushNotificationSenderService({required this.client, required this.supabase});

  Future<void> sendChatMessageNotification({
    required String targetUserId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    final accessToken = supabase.auth.currentSession?.accessToken;
    if (accessToken == null) return;

    try {
      final response = await client
          .post(
            Uri.parse(SupabaseConfig.sendPushNotificationFunctionUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({
              'targetUserId': targetUserId,
              'title': title,
              'body': body,
              if (data != null) 'data': data,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
      }
    } catch (_) {
    }
  }
}
