abstract class Failure {
  final String message;
  const Failure(this.message);
}

class FirebaseFailure extends Failure {
  const FirebaseFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = "ইন্টারনেট কানেকশন নেই। দয়া করে পুনরায় চেষ্টা করুন।"]);
}

class ModerationBlockedFailure extends Failure {
  const ModerationBlockedFailure(super.message);
}

class UsernameTakenFailure extends Failure {
  const UsernameTakenFailure([super.message = "This username is already taken"]);
}
