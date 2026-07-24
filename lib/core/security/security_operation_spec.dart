import 'security_operation.dart';

class SecurityOperationSpec {
  final SecurityOperation operation;
  final String currentImplementationPath;
  final bool crossUserWrite;
  final bool crossUserRead;
  final List<String> collectionsWritten;
  final List<String> collectionsRead;
  final String plannedCloudFunctionName;
  final SecurityOperationRisk risk;
  final SecurityMigrationStatus migrationStatus;

  const SecurityOperationSpec({
    required this.operation,
    required this.currentImplementationPath,
    required this.crossUserWrite,
    required this.crossUserRead,
    required this.collectionsWritten,
    required this.collectionsRead,
    required this.plannedCloudFunctionName,
    required this.risk,
    this.migrationStatus = SecurityMigrationStatus.clientSideOnly,
  });

  SecurityOperationSpec copyWith({SecurityMigrationStatus? migrationStatus}) {
    return SecurityOperationSpec(
      operation: operation,
      currentImplementationPath: currentImplementationPath,
      crossUserWrite: crossUserWrite,
      crossUserRead: crossUserRead,
      collectionsWritten: collectionsWritten,
      collectionsRead: collectionsRead,
      plannedCloudFunctionName: plannedCloudFunctionName,
      risk: risk,
      migrationStatus: migrationStatus ?? this.migrationStatus,
    );
  }
}
