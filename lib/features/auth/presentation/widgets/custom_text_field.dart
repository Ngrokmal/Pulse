import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final FocusNode? focusNode;
  final Function(String)? onChanged;
  final String? Function(String?)? validator;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.focusNode,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: hint,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: isPassword,
        onChanged: onChanged,
        validator: validator,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20)),
      ),
    );
  }
}
