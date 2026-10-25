import 'profile_bulk_warmup_service.dart';

class GroupProfileBulkWarmupService {
  final ProfileBulkWarmupService profileWarmupService;
  const GroupProfileBulkWarmupService(this.profileWarmupService);

  Future<void> warmUpVisibleMembers(Iterable<String> visibleMemberUids) {
    return profileWarmupService.warmUpProfiles(visibleMemberUids);
  }
}
