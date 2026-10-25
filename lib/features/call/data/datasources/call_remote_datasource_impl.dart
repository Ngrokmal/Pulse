import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/exceptions.dart';
import '../dto/agora_token_dto.dart';
import '../dto/call_session_dto.dart';
import 'call_remote_datasource.dart';

/// Concrete [CallRemoteDataSource]: Supabase Postgrest CRUD on
/// `call_sessions`/`call_events`, plus a raw-http call to the
/// `generate-agora-token` Edge Function.
///
/// IMPORTANT — SCHEMA DEPENDENCY (see this milestone's runtime-risk notes):
/// this class assumes the `call_sessions`/`call_events` tables and the
/// `generate-agora-token` Edge Function exist, exactly as specified in the
/// frozen Phase 1 architecture (§7/§9). Per your instruction, THIS
/// MILESTONE DOES NOT CREATE THAT SCHEMA OR FUNCTION — no migration, no
/// Edge Function deployment. Every method here will fail at runtime with a
/// Postgrest "relation does not exist" (or equivalent) error until that
/// backend work is separately approved and applied. This is a data-layer
/// implementation written against an agreed contract, not a claim that the
/// contract's backend half currently exists.
///
/// Mirrors `ChatRepositoryImpl`/`FriendRepositoryImpl`'s convention of
/// letting Supabase exceptions (`PostgrestException`, etc.) propagate
/// un-caught from the datasource — the repository layer (`CallRepositoryImpl`)
/// is where those get caught and mapped to `Failure` subtypes, matching the
/// existing FailureMapper-style try/catch used throughout the project.
class CallRemoteDataSourceImpl implements CallRemoteDataSource {
  final SupabaseClient supabase;
  final http.Client client;

  CallRemoteDataSourceImpl({required this.supabase, required this.client});

  @override
  Future<CallSessionDto> createCallSession({
    required String callerId,
    required String calleeId,
    required String channelName,
    required String callType,
    required int agoraUidCaller,
    required int agoraUidCallee,
  }) async {
    final row = await supabase
        .from('call_sessions')
        .insert({
          'caller_id': callerId,
          'callee_id': calleeId,
          'channel_name': channelName,
          'call_type': callType,
          'agora_uid_caller': agoraUidCaller,
          'agora_uid_callee': agoraUidCallee,
          // status defaults to 'ringing' at the DB level (Phase 1 §7).
        })
        .select()
        .single();
    return CallSessionDto.fromJson(row);
  }

  @override
  Future<void> updateCallStatus({
    required String callId,
    required String status,
    String? endReason,
  }) async {
    final payload = <String, dynamic>{'status': status};
    if (endReason != null) payload['end_reason'] = endReason;

    // Timestamp columns are set here, as an implementation detail of this
    // datasource, rather than being exposed as extra parameters on the
    // (frozen, Milestone 1) CallRemoteDataSource interface — Phase 1 §7
    // defines accepted_at/ended_at as columns, but the abstract contract
    // only exposes status+endReason, so this is the one place that maps
    // "which status" to "which timestamp column" for the write.
    if (status == 'accepted') {
      payload['accepted_at'] = DateTime.now().toUtc().toIso8601String();
    } else if (status == 'declined' ||
        status == 'cancelled' ||
        status == 'missed' ||
        status == 'busy' ||
        status == 'ended') {
      payload['ended_at'] = DateTime.now().toUtc().toIso8601String();
    }

    await supabase.from('call_sessions').update(payload).eq('id', callId);
  }

  @override
  Future<CallSessionDto?> getCallSession(String callId) async {
    final row = await supabase.from('call_sessions').select().eq('id', callId).maybeSingle();
    if (row == null) return null;
    return CallSessionDto.fromJson(row);
  }

  @override
  Future<List<CallSessionDto>> getCallHistory({
    required String userId,
    String? cursor,
    int limit = 20,
  }) async {
    var query = supabase
        .from('call_sessions')
        .select()
        .or('caller_id.eq.$userId,callee_id.eq.$userId');

    if (cursor != null) {
      query = query.lt('created_at', cursor);
    }

    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map((row) => CallSessionDto.fromJson(row)).toList();
  }

  @override
  Future<void> insertCallEvent({
    required String callId,
    required String eventType,
    String? actorId,
    Map<String, dynamic>? metadata,
  }) async {
    await supabase.from('call_events').insert({
      'call_id': callId,
      'event_type': eventType,
      'actor_id': actorId,
      'metadata': metadata,
    });
  }

  @override
  Future<AgoraTokenDto> fetchAgoraToken({
    required String callId,
    required String channelName,
    required int uid,
  }) async {
    final accessToken = supabase.auth.currentSession?.accessToken;
    if (accessToken == null) {
      throw const ServerException(message: 'Not signed in — cannot request an Agora token.');
    }

    // Mirrors PushNotificationSenderService's raw-http Edge Function call
    // convention (Bearer token + JSON body against a full function URL),
    // rather than supabase_flutter's FunctionsClient — no other Edge
    // Function call site in this project uses FunctionsClient, so this
    // keeps the call module consistent with the one existing precedent.
    final response = await client
        .post(
          Uri.parse(SupabaseConfig.generateAgoraTokenFunctionUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'callId': callId,
            'channelName': channelName,
            'uid': uid,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw ServerException(
        message: 'generate-agora-token returned ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AgoraTokenDto.fromJson(json);
  }
}
