class ServerException implements Exception {
  final String message;
  const ServerException({required this.message});
  @override
  String toString() => "ServerException: $message";
}

class NetworkException implements Exception {
  final String message;
  const NetworkException({required this.message});
  @override
  String toString() => "NetworkException: $message";
}

class CacheException implements Exception {
  final String message;
  const CacheException({required this.message});
  @override
  String toString() => "CacheException: $message";
}

class UnknownException implements Exception {
  final String message;
  const UnknownException({required this.message});
  @override
  String toString() => "UnknownException: $message";
}

class ModerationBlockedException implements Exception {
  final String message;
  const ModerationBlockedException({required this.message});
  @override
  String toString() => "ModerationBlockedException: $message";
}

class UsernameTakenException implements Exception {
  final String message;
  const UsernameTakenException({this.message = "This username is already taken"});
  @override
  String toString() => "UsernameTakenException: $message";
}
