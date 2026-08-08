import '../../../../core/errors/failures.dart';
import '../../domain/entities/moderation_report.dart';

abstract class ModerationQueueState {
  const ModerationQueueState();
}

class ModerationQueueLoading extends ModerationQueueState {}

class ModerationQueueLoaded extends ModerationQueueState {
  final List<ModerationReport> reports;
  final bool actionInProgress;
  const ModerationQueueLoaded(this.reports, {this.actionInProgress = false});
}

class ModerationQueueErrorState extends ModerationQueueState {
  final Failure failure;
  const ModerationQueueErrorState(this.failure);
}
