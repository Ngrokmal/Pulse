/// Whether a call is audio-only or audio+video.
///
/// Enum member names are used verbatim as the wire value (see
/// CallSessionModel.toDto/.fromDto) and must stay in sync with the
/// `call_type_enum` values agreed for the (not-yet-created) Supabase schema:
/// 'audio' | 'video'.
enum CallType { audio, video }
