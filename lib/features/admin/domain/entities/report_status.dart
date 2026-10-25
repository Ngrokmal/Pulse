enum ReportStatus { pending, reviewed, resolved }

ReportStatus reportStatusFromString(String? value) {
  switch (value) {
    case 'reviewed':
      return ReportStatus.reviewed;
    case 'resolved':
      return ReportStatus.resolved;
    case 'pending':
    default:
      return ReportStatus.pending;
  }
}

String reportStatusToString(ReportStatus status) {
  switch (status) {
    case ReportStatus.reviewed:
      return 'reviewed';
    case ReportStatus.resolved:
      return 'resolved';
    case ReportStatus.pending:
      return 'pending';
  }
}
