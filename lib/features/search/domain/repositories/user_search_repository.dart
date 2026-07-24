import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../profile/domain/entities/profile_entity.dart';

abstract class UserSearchRepository {
  Future<Either<Failure, List<ProfileEntity>>> fetchSearchCandidates({
    required String excludeUid,
  });
}
