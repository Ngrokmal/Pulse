import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../profile/data/datasources/profile_local_data_source.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/presentation/widgets/photo_placeholder.dart';

class GroupFriendListTile extends StatefulWidget {
  const GroupFriendListTile({
    super.key,
    required this.memberUid,
    required this.cacheVersion,
    required this.subtitleOverride,
    required this.trailing,
  });

  final String memberUid;

  final ValueListenable<int> cacheVersion;

  final String? subtitleOverride;

  final Widget? trailing;

  @override
  State<GroupFriendListTile> createState() => _GroupFriendListTileState();
}

class _GroupFriendListTileState extends State<GroupFriendListTile> {
  final ProfileLocalDataSource _profileCache = di.sl<ProfileLocalDataSource>();
  ProfileEntity? _cached;
  int _lastReadVersion = -1;

  @override
  void initState() {
    super.initState();
    _readCache();
  }

  @override
  void didUpdateWidget(covariant GroupFriendListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memberUid != widget.memberUid) {
      _cached = null;
      _lastReadVersion = -1;
      _readCache();
    }
  }

  void _readCache() {
    final version = widget.cacheVersion.value;
    if (version == _lastReadVersion) return;
    _lastReadVersion = version;
    _profileCache.getCachedProfile(widget.memberUid).then((profile) {
      if (!mounted) return;
      setState(() => _cached = profile);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.cacheVersion,
      builder: (context, version, _) {
        if (version != _lastReadVersion) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _readCache());
        }
        final profile = _cached;
        final hasName = profile != null && profile.displayName.isNotEmpty;
        final hasAvatar = profile?.avatarUrl != null && profile!.avatarUrl!.isNotEmpty;

        return ListTile(
          leading: CircleAvatar(
            child: ClipOval(
              child: SizedBox(
                width: 40,
                height: 40,
                child: hasAvatar
                    ? PhotoPlaceholder(
                        imageUrl: profile!.avatarUrl,
                        iconSize: 20,
                      )
                    : const PhotoPlaceholder(icon: Icons.person, iconSize: 20),
              ),
            ),
          ),
          title: Text(hasName ? profile!.displayName : widget.memberUid),
          subtitle: widget.subtitleOverride != null ? Text(widget.subtitleOverride!) : null,
          trailing: widget.trailing,
        );
      },
    );
  }
}
