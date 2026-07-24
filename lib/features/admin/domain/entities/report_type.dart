enum ReportType { user, message, group }

ReportType reportTypeFromString(String? value) {
  switch (value) {
    case 'message':
      return ReportType.message;
    case 'group':
      return ReportType.group;
    case 'user':
    default:
      return ReportType.user;
  }
}

String reportTypeToString(ReportType type) {
  switch (type) {
    case ReportType.message:
      return 'message';
    case ReportType.group:
      return 'group';
    case ReportType.user:
      return 'user';
  }
}
