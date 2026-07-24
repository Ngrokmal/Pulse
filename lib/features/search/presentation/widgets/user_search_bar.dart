import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class UserSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const UserSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search by username or name',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  controller.clear();
                  onClear();
                },
              );
            },
          ),
          isDense: true,
          filled: true,
          fillColor: AppColors.inputBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
