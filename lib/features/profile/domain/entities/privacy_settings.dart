import 'profile_visibility.dart';

enum PrivacyOption { public, friendsOnly, private }

enum FriendRequestPrivacy { everyone, friendsOfFriends, nobody }

PrivacyOption privacyOptionFromString(String? value) {
  switch (value) {
    case 'friendsOnly':
      return PrivacyOption.friendsOnly;
    case 'private':
      return PrivacyOption.private;
    default:
      return PrivacyOption.public;
  }
}

String privacyOptionToString(PrivacyOption option) {
  switch (option) {
    case PrivacyOption.public:
      return 'public';
    case PrivacyOption.friendsOnly:
      return 'friendsOnly';
    case PrivacyOption.private:
      return 'private';
  }
}

FriendRequestPrivacy friendRequestPrivacyFromString(String? value) {
  switch (value) {
    case 'friendsOfFriends':
      return FriendRequestPrivacy.friendsOfFriends;
    case 'nobody':
      return FriendRequestPrivacy.nobody;
    default:
      return FriendRequestPrivacy.everyone;
  }
}

String friendRequestPrivacyToString(FriendRequestPrivacy option) {
  switch (option) {
    case FriendRequestPrivacy.everyone:
      return 'everyone';
    case FriendRequestPrivacy.friendsOfFriends:
      return 'friendsOfFriends';
    case FriendRequestPrivacy.nobody:
      return 'nobody';
  }
}

bool isVisibleUnder(PrivacyOption option, ProfileVisibility viewerRelation) {
  switch (viewerRelation) {
    case ProfileVisibility.owner:
      return true;
    case ProfileVisibility.blocked:
      return false;
    case ProfileVisibility.friend:
      return option != PrivacyOption.private;
    case ProfileVisibility.nonFriend:
      return option == PrivacyOption.public;
  }
}
