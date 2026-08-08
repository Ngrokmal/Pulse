enum BanType { permanent, temporary }

BanType banTypeFromString(String? value) {
  switch (value) {
    case 'temporary':
      return BanType.temporary;
    case 'permanent':
    default:
      return BanType.permanent;
  }
}

String banTypeToString(BanType type) {
  switch (type) {
    case BanType.temporary:
      return 'temporary';
    case BanType.permanent:
      return 'permanent';
  }
}
