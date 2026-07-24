enum VerificationStatus { verified, pending, notVerified }

VerificationStatus verificationStatusFromString(String? value) {
  switch (value) {
    case 'verified':
      return VerificationStatus.verified;
    case 'pending':
      return VerificationStatus.pending;
    default:
      return VerificationStatus.notVerified;
  }
}

String verificationStatusToString(VerificationStatus status) {
  switch (status) {
    case VerificationStatus.verified:
      return 'verified';
    case VerificationStatus.pending:
      return 'pending';
    case VerificationStatus.notVerified:
      return 'notVerified';
  }
}
