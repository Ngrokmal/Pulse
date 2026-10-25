/// Event kinds recorded in the call module's append-only audit log
/// (Phase 1 §8.2). Enum member names are used verbatim as the wire value
/// and must stay in sync with the `call_event_type_enum` values agreed for
/// the (not-yet-created) Supabase schema.
enum CallEventType { rang, accepted, declined, cancelled, missed, busy, ended }
