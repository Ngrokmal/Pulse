/// The callee's response to an incoming call, passed to
/// `CallRepository.respondToCall`. Kept separate from [CallStatus] because
/// not every status is a valid *response* (e.g. 'ringing'/'ended' are never
/// something a callee "responds" with).
enum CallResponse { accept, decline, busy }
