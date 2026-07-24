import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/admin_repository.dart';

class ReportMessageUseCase {
  final AdminRepository repository;
  const ReportMessageUseCase(this.repository);

  Future<Either<Failure, void>> call({
    required String reporterUid,
    required String messageId,
    required String chatId,
    required String reason,
  }) {
    return repository.reportMessage(
      reporterUid: reporterUid,
      messageId: messageId,
      chatId: chatId,
      reason: reason,
    );
  }
}
