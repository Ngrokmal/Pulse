import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const Color primary = Color(0xff6c5ce7);
  static const Color primaryAccent = Color(0xffa29bfe);
  static const Color backgroundTop = Color(0xff181930);
  static const Color backgroundMiddle = Color(0xff101123);
  static const Color backgroundBottom = Color(0xff0d0e1a);
  static const Color surface = Color(0xff252846);
  static const Color inputBackground = Colors.white10;
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xff8b8ea9);
  static const Color eyeIris = Color(0xff101123);
  static const Color mouthColor = Color(0xffa55eea);
  static const Color error = Colors.redAccent;

  // Voice Message recording UI (WhatsApp-style Resume pill / send circle).
  static const Color whatsappGreen = Color(0xff25d366);

  // UI-polish pass (Day 6 M3 follow-up, presentation-layer only): message
  // bubble + status-icon tokens so chat/group screens stop hardcoding
  // Colors.grey/Colors.white and stay consistent with the dark theme.
  static const Color bubbleMine = primary;
  static const Color bubbleTheirs = surface;
  static const Color statusSent = textSecondary;
  static const Color statusRead = primaryAccent;
  static const Color divider = Colors.white12;
  static const Color shadow = Colors.black26;
}
