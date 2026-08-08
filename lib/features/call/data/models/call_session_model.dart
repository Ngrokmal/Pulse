import '../../domain/entities/call_session_entity.dart';
import '../../domain/entities/call_status.dart';
import '../../domain/entities/call_type.dart';
import '../dto/call_session_dto.dart';

/// Data-layer model: extends the domain entity (matches this project's
/// existing model/entity convention elsewhere) and adds the
/// DTO<->entity mapping. This is the only place `CallSessionDto`'s string
/// wire values are parsed into/out of the domain's `CallType`/`CallStatus`
/// enums.
class CallSessionModel extends CallSessionEntity {
  const CallSessionModel({
    required super.id,
    required super.callerId,
    required super.calleeId,
    required super.channelName,
    required super.callType,
    required super.status,
    required super.createdAt,
    required super.ringingStartedAt,
    super.acceptedAt,
    super.endedAt,
    super.endReason,
    required super.agoraUidCaller,
    required super.agoraUidCallee,
  });

  factory CallSessionModel.fromDto(CallSessionDto dto) {
    return CallSessionModel(
      id: dto.id,
      callerId: dto.callerId,
      calleeId: dto.calleeId,
      channelName: dto.channelName,
      callType: _parseCallType(dto.callType),
      status: _parseCallStatus(dto.status),
      createdAt: DateTime.parse(dto.createdAt),
      ringingStartedAt: DateTime.parse(dto.ringingStartedAt),
      acceptedAt: dto.acceptedAt != null ? DateTime.parse(dto.acceptedAt!) : null,
      endedAt: dto.endedAt != null ? DateTime.parse(dto.endedAt!) : null,
      endReason: dto.endReason,
      agoraUidCaller: dto.agoraUidCaller,
      agoraUidCallee: dto.agoraUidCallee,
    );
  }

  CallSessionDto toDto() {
    return CallSessionDto(
      id: id,
      callerId: callerId,
      calleeId: calleeId,
      channelName: channelName,
      callType: callType.name,
      status: status.name,
      createdAt: createdAt.toIso8601String(),
      ringingStartedAt: ringingStartedAt.toIso8601String(),
      acceptedAt: acceptedAt?.toIso8601String(),
      endedAt: endedAt?.toIso8601String(),
      endReason: endReason,
      agoraUidCaller: agoraUidCaller,
      agoraUidCallee: agoraUidCallee,
    );
  }

  static CallType _parseCallType(String raw) {
    return CallType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => CallType.audio,
    );
  }

  static CallStatus _parseCallStatus(String raw) {
    return CallStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => CallStatus.ended,
    );
  }
}
