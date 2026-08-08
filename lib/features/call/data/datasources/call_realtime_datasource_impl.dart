import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../dto/call_session_dto.dart';
import 'call_realtime_datasource.dart';

/// Concrete [CallRealtimeDataSource]: Postgres Changes subscriptions on
/// `call_sessions`, mirroring `ChatRepositoryImpl.streamMessages`'s exact
/// controller idiom — create the `StreamController`, define+call a `start()`
/// that sets up the channel and tracks it in a `Map<String, RealtimeChannel>`
/// (tearing down any previous channel under the same key first), then set
/// `controller.onCancel` to remove the channel. This is the same
/// stale-channel-avoidance shape flagged in Phase 1 §20/§21.
///
/// Same schema dependency note as [CallRemoteDataSourceImpl]: this assumes
/// `call_sessions` exists — no migration is part of this milestone.
class CallRealtimeDataSourceImpl implements CallRealtimeDataSource {
  final SupabaseClient supabase;

  final Map<String, RealtimeChannel> _channels = {};

  CallRealtimeDataSourceImpl({required this.supabase});

  @override
  Stream<CallSessionDto> subscribeToIncomingCalls(String userId) {
    final channelKey = 'incoming_calls_$userId';
    final controller = StreamController<CallSessionDto>.broadcast();

    void start() {
      final channel = supabase.channel(channelKey).onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'callee_id',
          value: userId,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          final dto = CallSessionDto.fromJson(row);
          // Only 'ringing' inserts are a genuine incoming call — defensive
          // filter per Phase 1 §20's exact subscription contract, in case a
          // future migration ever changes the default insert status.
          if (dto.status != 'ringing') return;
          if (!controller.isClosed) controller.add(dto);
        },
      );

      channel.subscribe();

      final existing = _channels[channelKey];
      if (existing != null) supabase.removeChannel(existing);
      _channels[channelKey] = channel;
    }

    start();

    controller.onCancel = () async {
      final channel = _channels[channelKey];
      if (channel != null) {
        await supabase.removeChannel(channel);
        if (identical(_channels[channelKey], channel)) {
          _channels.remove(channelKey);
        }
      }
    };

    return controller.stream;
  }

  @override
  Stream<CallSessionDto> subscribeToCallStatus(String callId) {
    final channelKey = 'call_status_$callId';
    final controller = StreamController<CallSessionDto>.broadcast();

    void start() {
      final channel = supabase.channel(channelKey).onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'call_sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: callId,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          if (!controller.isClosed) controller.add(CallSessionDto.fromJson(row));
        },
      );

      channel.subscribe();

      final existing = _channels[channelKey];
      if (existing != null) supabase.removeChannel(existing);
      _channels[channelKey] = channel;
    }

    start();

    controller.onCancel = () async {
      final channel = _channels[channelKey];
      if (channel != null) {
        await supabase.removeChannel(channel);
        if (identical(_channels[channelKey], channel)) {
          _channels.remove(channelKey);
        }
      }
    };

    return controller.stream;
  }

  @override
  Future<void> unsubscribe(String channelKey) async {
    final channel = _channels[channelKey];
    if (channel != null) {
      await supabase.removeChannel(channel);
      if (identical(_channels[channelKey], channel)) {
        _channels.remove(channelKey);
      }
    }
  }
}
