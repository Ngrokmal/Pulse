enum BanStatus { active, lifted }

BanStatus banStatusFromString(String? value) {
  switch (value) {
    case 'lifted':
      return BanStatus.lifted;
    case 'active':
    default:
      return BanStatus.active;
  }
}

String banStatusToString(BanStatus status) {
  switch (status) {
    case BanStatus.lifted:
      return 'lifted';
    case BanStatus.active:
      return 'active';
  }
}
