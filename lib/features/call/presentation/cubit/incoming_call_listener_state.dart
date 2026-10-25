import '../../domain/entities/call_session_entity.dart';

/// State for the app-wide [IncomingCallListenerCubit]. Sealed-class style,
/// matching `AuthState`/`ChatBloc`'s state hierarchies rather than a single
/// mutable class, since there's no shared field between "nothing ringing"
/// and "here is the ringing session".
abstract class IncomingCallListenerState {
  const IncomingCallListenerState();
}

/// No incoming call currently awaiting the user's response.
class IncomingCallListenerIdle extends IncomingCallListenerState {
  const IncomingCallListenerIdle();
}

/// A call is ringing for the current user — the app-root listener reacts
/// to this by pushing [IncomingCallScreen] via `appNavigatorKey`.
class IncomingCallListenerRinging extends IncomingCallListenerState {
  final CallSessionEntity session;
  const IncomingCallListenerRinging(this.session);
}
