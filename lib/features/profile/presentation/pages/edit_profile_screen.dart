import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../blocs/profile_bloc.dart';
import '../models/profile_ui_data.dart';
import '../widgets/photo_placeholder.dart';
import '../widgets/profile_photo_flow.dart';

class EditProfileScreen extends StatefulWidget {
  final String uid;
  final ProfileUiData data;

  const EditProfileScreen({super.key, required this.uid, required this.data});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _locationController;
  late final TextEditingController _websiteController;

  String? _gender;
  DateTime? _birthday;
  bool _wasSaving = false;

  static const List<String> _genderOptions = ['Female', 'Male', 'Other', 'Prefer not to say'];

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _nameController = TextEditingController(text: d.name);
    _usernameController = TextEditingController(text: d.username);
    _bioController = TextEditingController(text: d.bio ?? '');
    _phoneController = TextEditingController(text: d.phone ?? '');
    _emailController = TextEditingController(text: d.email ?? '');
    _locationController = TextEditingController(text: d.location ?? '');
    _websiteController = TextEditingController(text: d.website ?? '');
    _gender = d.gender;
    _birthday = d.birthday;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  void _save() {
    context.read<ProfileBloc>().add(UpdateProfileRequested(
          uid: widget.uid,
          displayName: _nameController.text.trim(),
          username: _usernameController.text.trim().replaceFirst('@', ''),
          bio: _bioController.text.trim(),
          location: _locationController.text.trim(),
          gender: _gender,
          birthday: _birthday,
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          website: _websiteController.text.trim(),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProfileBloc, ProfileState>(
      listener: (context, state) {
        if (state is ProfileErrorState) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
        } else if (state is ProfileLoadedState && !state.isSaving && _wasSaving) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
          Navigator.of(context).pop();
        }
        if (state is ProfileLoadedState) _wasSaving = state.isSaving;
      },
      child: Scaffold(
      backgroundColor: AppColors.backgroundBottom,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundBottom,
        title: Text('Edit Profile', style: AppTypography.body.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.medium),
        children: [
          _PhotoEditRow(
            avatarUrl: widget.data.avatarUrl,
            coverUrl: widget.data.coverUrl,
            onEditAvatar: () => ProfilePhotoFlow.start(
              context,
              title: 'Profile Photo',
              isCircle: true,
              hasExistingPhoto: widget.data.avatarUrl != null,
              currentImageUrl: widget.data.avatarUrl,
              onPhotoSelected: (file) => context.read<ProfileBloc>().add(UpdatePhotoRequested(uid: widget.uid, slot: PhotoSlot.avatar, file: file)),
              onRemove: () => context.read<ProfileBloc>().add(RemovePhotoRequested(uid: widget.uid, slot: PhotoSlot.avatar)),
            ),
            onEditCover: () => ProfilePhotoFlow.start(
              context,
              title: 'Cover Photo',
              isCircle: false,
              hasExistingPhoto: widget.data.coverUrl != null,
              currentImageUrl: widget.data.coverUrl,
              onPhotoSelected: (file) => context.read<ProfileBloc>().add(UpdatePhotoRequested(uid: widget.uid, slot: PhotoSlot.cover, file: file)),
              onRemove: () => context.read<ProfileBloc>().add(RemovePhotoRequested(uid: widget.uid, slot: PhotoSlot.cover)),
            ),
          ),
          const SizedBox(height: AppSpacing.large),
          _Field(label: 'Name', controller: _nameController, icon: Icons.badge_outlined),
          _Field(label: 'Username', controller: _usernameController, icon: Icons.alternate_email_rounded),
          _Field(label: 'Bio', controller: _bioController, icon: Icons.info_outline_rounded, maxLines: 3),
          _GenderField(value: _gender, options: _genderOptions, onChanged: (v) => setState(() => _gender = v)),
          _DateField(label: 'Birthday', value: _birthday, onTap: _pickBirthday),
          _Field(label: 'Phone', controller: _phoneController, icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
          _Field(label: 'Email', controller: _emailController, icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
          _Field(label: 'Location', controller: _locationController, icon: Icons.location_on_outlined),
          _Field(label: 'Website', controller: _websiteController, icon: Icons.link_rounded, keyboardType: TextInputType.url),
          const SizedBox(height: AppSpacing.large),
          BlocBuilder<ProfileBloc, ProfileState>(
            builder: (context, state) {
              final isSaving = state is ProfileLoadedState && state.isSaving;
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isSaving ? null : _save,
                  icon: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: const Text('Save'),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.large),
        ],
      ),
    ),
    );
  }
}

class _PhotoEditRow extends StatelessWidget {
  final VoidCallback onEditAvatar;
  final VoidCallback onEditCover;
  final String? avatarUrl;
  final String? coverUrl;

  const _PhotoEditRow({required this.onEditAvatar, required this.onEditCover, this.avatarUrl, this.coverUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        GestureDetector(
          onTap: onEditCover,
          child: ClipRRect(
            borderRadius: AppRadius.button,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(height: 130, width: double.infinity, child: PhotoPlaceholder(icon: Icons.image_rounded, colors: const [AppColors.backgroundTop, AppColors.surface], imageUrl: coverUrl)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt_outlined, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Change Cover', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: -30,
          child: GestureDetector(
            onTap: onEditAvatar,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: AppColors.backgroundBottom, shape: BoxShape.circle),
              child: Stack(
                children: [
                  ClipOval(child: SizedBox(width: 76, height: 76, child: PhotoPlaceholder(iconSize: 32, imageUrl: avatarUrl))),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;

  const _Field({
    required this.label,
    required this.controller,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.medium),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: AppTypography.body.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _GenderField extends StatelessWidget {
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _GenderField({required this.value, required this.options, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.medium),
      child: DropdownButtonFormField<String>(
        value: value,
        dropdownColor: AppColors.surface,
        style: AppTypography.body.copyWith(color: AppColors.textPrimary),
        decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.wc_rounded, size: 20)),
        items: options.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = value == null ? '' : '${value!.day}/${value!.month}/${value!.year}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.input,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.cake_outlined, size: 20)),
          child: Text(
            text.isEmpty ? 'Select date' : text,
            style: AppTypography.body.copyWith(color: text.isEmpty ? AppColors.textSecondary : AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}
