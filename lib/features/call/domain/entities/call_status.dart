/// Lifecycle status of a call, per the frozen Phase 1 architecture (§7/§8.1).
///
/// Enum member names are used verbatim as the wire value (see
/// CallSessionModel.toDto/.fromDto) and must stay in sync with the
/// `call_status_enum` values agreed for the (not-yet-created) Supabase
/// schema: 'ringing' | 'accepted' | 'declined' | 'cancelled' | 'missed' |
/// 'busy' | 'ended'.
enum CallStatus { ringing, accepted, declined, cancelled, missed, busy, ended }
