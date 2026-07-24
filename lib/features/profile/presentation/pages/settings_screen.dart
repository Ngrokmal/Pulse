import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/cache_inspector.dart';
import '../../../auth/domain/usecases/logout_usecase.dart';
import '../../../auth/presentation/pages/auth_screen.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/privacy_settings.dart';
import '../../domain/entities/profile_entity.dart';
import '../blocs/profile_bloc.dart';
import 'blocked_users_screen.dart';

class SettingsScreen extends StatelessWidget {
  final String uid;

  const SettingsScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<ProfileBloc>();

    return Scaffold(
      backgroundColor: AppColors.backgroundBottom,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundBottom,
        title: Text('Settings', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, state) {
          if (state is! ProfileLoadedState) {
            return const Center(child: CircularProgressIndicator());
          }

          final profile = state.profile;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.medium),
            children: [
              const _SectionLabel('Notifications'),
              _SettingsSwitchTile(
                icon: Icons.notifications_outlined,
                title: 'Notification Settings',
                subtitle: 'Receive alerts for messages and requests',
                value: profile.notificationsEnabled,
                onChanged: (v) => bloc.add(UpdateSettingsRequested(uid: uid, notificationsEnabled: v)),
              ),
              const SizedBox(height: AppSpacing.large),
              const _SectionLabel('Privacy'),
              _SettingsOptionTile(
                icon: Icons.lock_outline_rounded,
                title: 'Profile Privacy',
                valueLabel: _privacyLabel(profile.profilePrivacy),
                onTap: () async {
                  final selected = await _showPrivacyOptionSheet(context, 'Profile Privacy', profile.profilePrivacy);
                  if (selected != null) {
                    bloc.add(UpdateSettingsRequested(uid: uid, profilePrivacy: selected));
                  }
                },
              ),
              _SettingsOptionTile(
                icon: Icons.visibility_outlined,
                title: 'Last Seen Visibility',
                valueLabel: _privacyLabel(profile.lastSeenVisibility),
                onTap: () async {
                  final selected = await _showPrivacyOptionSheet(context, 'Last Seen Visibility', profile.lastSeenVisibility);
                  if (selected != null) {
                    bloc.add(UpdateSettingsRequested(uid: uid, lastSeenVisibility: selected));
                  }
                },
              ),
              _SettingsOptionTile(
                icon: Icons.circle,
                title: 'Online Status Visibility',
                valueLabel: _privacyLabel(profile.onlineStatusVisibility),
                onTap: () async {
                  final selected = await _showPrivacyOptionSheet(context, 'Online Status Visibility', profile.onlineStatusVisibility);
                  if (selected != null) {
                    bloc.add(UpdateSettingsRequested(uid: uid, onlineStatusVisibility: selected));
                  }
                },
              ),
              _SettingsOptionTile(
                icon: Icons.person_add_alt_outlined,
                title: 'Friend Request Privacy',
                valueLabel: _friendRequestPrivacyLabel(profile.friendRequestPrivacy),
                onTap: () async {
                  final selected = await _showFriendRequestPrivacySheet(context, profile.friendRequestPrivacy);
                  if (selected != null) {
                    bloc.add(UpdateSettingsRequested(uid: uid, friendRequestPrivacy: selected));
                  }
                },
              ),
              const SizedBox(height: AppSpacing.large),
              const _SectionLabel('Friends'),
              _SettingsOptionTile(
                icon: Icons.block_rounded,
                title: 'Blocked Users',
                valueLabel: '',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(value: bloc, child: BlockedUsersScreen(uid: uid)),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.large),
              const _SectionLabel('Theme'),
              _SettingsOptionTile(
                icon: Icons.brightness_6_outlined,
                title: 'App Theme',
                valueLabel: _themeModeLabel(profile.themeMode),
                onTap: () async {
                  final selected = await _showThemeModeSheet(context, profile.themeMode);
                  if (selected != null) {
                    bloc.add(UpdateSettingsRequested(uid: uid, themeMode: selected));
                  }
                },
              ),
              const SizedBox(height: AppSpacing.large),
              const _SectionLabel('Chat Preferences'),
              _SettingsSwitchTile(
                icon: Icons.keyboard_return_rounded,
                title: 'Enter to Send',
                subtitle: 'Send message by pressing Enter',
                value: profile.enterToSend,
                onChanged: (v) => bloc.add(UpdateSettingsRequested(uid: uid, enterToSend: v)),
              ),
              _SettingsSwitchTile(
                icon: Icons.done_all_rounded,
                title: 'Read Receipts',
                subtitle: 'Let others see when you read messages',
                value: profile.readReceiptsEnabled,
                onChanged: (v) => bloc.add(UpdateSettingsRequested(uid: uid, readReceiptsEnabled: v)),
              ),
              _SettingsSwitchTile(
                icon: Icons.more_horiz_rounded,
                title: 'Typing Indicator',
                subtitle: 'Let others see when you are typing',
                value: profile.typingIndicatorEnabled,
                onChanged: (v) => bloc.add(UpdateSettingsRequested(uid: uid, typingIndicatorEnabled: v)),
              ),
              const SizedBox(height: AppSpacing.large),
              const _SectionLabel('Media Auto Download'),
              _SettingsSwitchTile(
                icon: Icons.image_outlined,
                title: 'Auto Download Images',
                subtitle: 'Automatically download incoming images',
                value: profile.autoDownloadImages,
                onChanged: (v) => bloc.add(UpdateSettingsRequested(uid: uid, autoDownloadImages: v)),
              ),
              _SettingsSwitchTile(
                icon: Icons.videocam_outlined,
                title: 'Auto Download Videos',
                subtitle: 'Automatically download incoming videos',
                value: profile.autoDownloadVideos,
                onChanged: (v) => bloc.add(UpdateSettingsRequested(uid: uid, autoDownloadVideos: v)),
              ),
              _SettingsSwitchTile(
                icon: Icons.insert_drive_file_outlined,
                title: 'Auto Download Files',
                subtitle: 'Automatically download incoming files',
                value: profile.autoDownloadFiles,
                onChanged: (v) => bloc.add(UpdateSettingsRequested(uid: uid, autoDownloadFiles: v)),
              ),
              _SettingsSwitchTile(
                icon: Icons.wifi_rounded,
                title: 'Wi-Fi Only',
                subtitle: 'Only auto-download media on Wi-Fi',
                value: profile.mediaWifiOnly,
                onChanged: (v) => bloc.add(UpdateSettingsRequested(uid: uid, mediaWifiOnly: v)),
              ),
              const SizedBox(height: AppSpacing.large),
              const _SectionLabel('Storage'),
              const _StorageSection(),
              const SizedBox(height: AppSpacing.large),
              const _SectionLabel('Account'),
              _SettingsOptionTile(
                icon: Icons.badge_outlined,
                title: 'Account Information',
                valueLabel: '',
                onTap: () => _showAccountInfoSheet(context, profile),
              ),
              _SettingsOptionTile(
                icon: Icons.phone_android_outlined,
                title: 'Device Information',
                valueLabel: '',
                onTap: () => _showDeviceInfoSheet(context),
              ),
              _SettingsOptionTile(
                icon: Icons.logout_rounded,
                title: 'Logout',
                valueLabel: '',
                onTap: () => _confirmLogout(context),
              ),
              const SizedBox(height: AppSpacing.large),
            ],
          );
        },
      ),
    );
  }

  static String _themeModeLabel(AppThemeModePref mode) {
    switch (mode) {
      case AppThemeModePref.system:
        return 'System';
      case AppThemeModePref.light:
        return 'Light';
      case AppThemeModePref.dark:
        return 'Dark';
    }
  }

  static Future<AppThemeModePref?> _showThemeModeSheet(BuildContext context, AppThemeModePref current) {
    return showModalBottomSheet<AppThemeModePref>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: AppRadius.button.topLeft)),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.medium),
                child: Text('App Theme', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              ),
              for (final option in AppThemeModePref.values)
                RadioListTile<AppThemeModePref>(
                  value: option,
                  groupValue: current,
                  activeColor: AppColors.primary,
                  title: Text(_themeModeLabel(option), style: AppTypography.body.copyWith(color: AppColors.textPrimary)),
                  onChanged: (v) => Navigator.of(context).pop(v),
                ),
              const SizedBox(height: AppSpacing.small),
            ],
          ),
        );
      },
    );
  }

  static void _showAccountInfoSheet(BuildContext context, ProfileEntity profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: AppRadius.button.topLeft)),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.medium),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Account Information', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.medium),
                _InfoRow(label: 'Username', value: profile.username),
                _InfoRow(label: 'Display Name', value: profile.displayName),
                _InfoRow(label: 'Email', value: profile.email ?? 'Not set'),
                _InfoRow(label: 'User ID', value: profile.uid),
                const SizedBox(height: AppSpacing.small),
              ],
            ),
          ),
        );
      },
    );
  }

  static void _showDeviceInfoSheet(BuildContext context) {
    final platformName = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
            ? 'iOS'
            : Platform.isMacOS
                ? 'macOS'
                : Platform.isWindows
                    ? 'Windows'
                    : Platform.isLinux
                        ? 'Linux'
                        : Platform.operatingSystem;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: AppRadius.button.topLeft)),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.medium),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Device Information', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.medium),
                _InfoRow(label: 'Platform Name', value: platformName),
                _InfoRow(label: 'OS', value: Platform.operatingSystem),
                _InfoRow(label: 'OS Version', value: Platform.operatingSystemVersion),
                const SizedBox(height: AppSpacing.small),
                Text(
                  'Detailed device model and manufacturer information will be available with a future native integration.',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.small),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Logout', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to logout?', style: AppTypography.body.copyWith(color: AppColors.textPrimary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Logout')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await di.sl<LogoutUseCase>()();
    if (!context.mounted) return;
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AuthScreen()),
        (route) => false,
      ),
    );
  }

  static String _privacyLabel(PrivacyOption option) {
    switch (option) {
      case PrivacyOption.public:
        return 'Everyone';
      case PrivacyOption.friendsOnly:
        return 'Friends Only';
      case PrivacyOption.private:
        return 'Only Me';
    }
  }

  static String _friendRequestPrivacyLabel(FriendRequestPrivacy option) {
    switch (option) {
      case FriendRequestPrivacy.everyone:
        return 'Everyone';
      case FriendRequestPrivacy.friendsOfFriends:
        return 'Friends of Friends';
      case FriendRequestPrivacy.nobody:
        return 'Nobody';
    }
  }

  static Future<PrivacyOption?> _showPrivacyOptionSheet(BuildContext context, String title, PrivacyOption current) {
    return showModalBottomSheet<PrivacyOption>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: AppRadius.button.topLeft)),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.medium),
                child: Text(title, style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              ),
              for (final option in PrivacyOption.values)
                RadioListTile<PrivacyOption>(
                  value: option,
                  groupValue: current,
                  activeColor: AppColors.primary,
                  title: Text(_privacyLabel(option), style: AppTypography.body.copyWith(color: AppColors.textPrimary)),
                  onChanged: (v) => Navigator.of(context).pop(v),
                ),
              const SizedBox(height: AppSpacing.small),
            ],
          ),
        );
      },
    );
  }

  static Future<FriendRequestPrivacy?> _showFriendRequestPrivacySheet(BuildContext context, FriendRequestPrivacy current) {
    return showModalBottomSheet<FriendRequestPrivacy>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: AppRadius.button.topLeft)),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.medium),
                child: Text('Friend Request Privacy', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              ),
              for (final option in FriendRequestPrivacy.values)
                RadioListTile<FriendRequestPrivacy>(
                  value: option,
                  groupValue: current,
                  activeColor: AppColors.primary,
                  title: Text(_friendRequestPrivacyLabel(option), style: AppTypography.body.copyWith(color: AppColors.textPrimary)),
                  onChanged: (v) => Navigator.of(context).pop(v),
                ),
              const SizedBox(height: AppSpacing.small),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.small),
      child: Text(label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.small),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: AppSpacing.small),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.input),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.medium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
                Text(subtitle, style: AppTypography.caption),
              ],
            ),
          ),
          Switch(value: value, activeColor: AppColors.primary, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SettingsOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String valueLabel;
  final VoidCallback onTap;

  const _SettingsOptionTile({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.small),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.input),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.input,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.medium, vertical: AppSpacing.small + 4),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: AppSpacing.medium),
                Expanded(child: Text(title, style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500))),
                if (valueLabel.isNotEmpty) ...[
                  Text(valueLabel, style: AppTypography.caption),
                  const SizedBox(width: AppSpacing.small),
                ],
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.small),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppTypography.caption)),
          Expanded(
            flex: 2,
            child: Text(value, style: AppTypography.body.copyWith(color: AppColors.textPrimary), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  double size = bytes.toDouble();
  int unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
}

class _StorageSection extends StatefulWidget {
  const _StorageSection();

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  int? _mediaBytes;
  int? _voiceBytes;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final media = await CacheInspector.instance.mediaCacheSizeBytes();
    final voice = await CacheInspector.instance.voiceCacheSizeBytes();
    if (!mounted) return;
    setState(() {
      _mediaBytes = media;
      _voiceBytes = voice;
    });
  }

  Future<void> _clearMedia() async {
    setState(() => _isClearing = true);
    await CacheInspector.instance.clearMediaCache();
    await _refresh();
    if (!mounted) return;
    setState(() => _isClearing = false);
  }

  Future<void> _clearVoice() async {
    setState(() => _isClearing = true);
    await CacheInspector.instance.clearVoiceCache();
    await _refresh();
    if (!mounted) return;
    setState(() => _isClearing = false);
  }

  @override
  Widget build(BuildContext context) {
    final mediaLabel = _mediaBytes == null ? 'Calculating...' : _formatBytes(_mediaBytes!);
    final voiceLabel = _voiceBytes == null ? 'Calculating...' : _formatBytes(_voiceBytes!);
    return Column(
      children: [
        _SettingsOptionTile(
          icon: Icons.perm_media_outlined,
          title: 'Media Cache',
          valueLabel: mediaLabel,
          onTap: _isClearing ? () {} : _clearMedia,
        ),
        _SettingsOptionTile(
          icon: Icons.graphic_eq_rounded,
          title: 'Voice Cache',
          valueLabel: voiceLabel,
          onTap: _isClearing ? () {} : _clearVoice,
        ),
      ],
    );
  }
}
