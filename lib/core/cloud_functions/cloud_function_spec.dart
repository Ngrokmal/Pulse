import 'cloud_function_operation.dart';

/// Design-only record describing a future Cloud Function.
///
/// No field on this class causes any Cloud Function to be created or
/// called. It is documentation-as-code so the eventual migration has a
/// single, reviewable source of truth for name, data touched, auth, and
/// validation expectations.
class CloudFunctionSpec {
  final CloudFunctionOperation operation;
  final CloudFunctionCategory category;
  final String futureFunctionName;
  final CloudFunctionAuthRequirement authRequirement;
  final List<String> collectionsRead;
  final List<String> collectionsWritten;
  final List<String> validationRequirements;

  /// The id of the corresponding entry in kSecurityOperationRegistry
  /// (see lib/core/security/security_operation.dart), kept as a plain
  /// string to avoid coupling this design-only file to that enum.
  final String correspondingSecurityOperationId;

  const CloudFunctionSpec({
    required this.operation,
    required this.category,
    required this.futureFunctionName,
    required this.authRequirement,
    required this.collectionsRead,
    required this.collectionsWritten,
    required this.validationRequirements,
    required this.correspondingSecurityOperationId,
  });
}
