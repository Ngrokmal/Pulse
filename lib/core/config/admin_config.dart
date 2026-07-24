/// Phase 8.6A (Admin Foundation)
///
/// Client-side allowlist of admin UIDs. This gates the admin UI and
/// navigation entry point so regular users never see admin features.
///
/// This is a FOUNDATION-ONLY gate: it is not, by itself, a data-layer
/// security boundary. Firestore Security Rules are a known blocker for
/// this project (see HANDOFF.md) — until rules restrict the admin reads
/// and moderation writes below to these UIDs server-side, this allowlist
/// only controls what the app *shows*, not what a modified client could
/// attempt to call.
class AdminConfig {
  AdminConfig._();

  /// Add the app owner's Firebase Auth UID(s) here.
  static const Set<String> adminUids = <String>{};
}
