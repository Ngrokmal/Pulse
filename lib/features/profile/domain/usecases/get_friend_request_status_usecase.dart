import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/friend_request_status.dart';
import '../repositories/friend_repository.dart';

class GetFriendRequestStatusUseCase {
  final FriendRepository repository;
  const GetFriendRequestStatusUseCase(this.repository);

  Future<Either<Failure, FriendRequestStatus>> call({required String viewerUid, required String profileUid}) {
    return repository.getFriendRequestStatus(viewerUid: viewerUid, profileUid: profileUid);
  }
}
