import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_theme.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';
import '../cubit/auth_ui_cubit.dart';
import '../cubit/auth_ui_state.dart';
import '../widgets/animated_bear_widget.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/premium_buttons.dart';
import '../../../home/presentation/pages/home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // স্টেবিলিটি ফিক্স: ফোকাস লিসেনার শুধুমাত্র একবার initState-এ যুক্ত করা হয়,
    // যাতে বারবার build() হলে ডুপ্লিকেট লিসেনার জমা না হয় (মেমোরি লিক/স্টেট কনফ্লিক্ট প্রতিরোধ)
    _passwordFocusNode.addListener(_onPasswordFocusChange);
  }

  void _onPasswordFocusChange() {
    context.read<AuthUiCubit>().setCovered(_passwordFocusNode.hasFocus);
  }

  @override
  void dispose() {
    // স্টেবিলিটি ফিক্স: কন্ট্রোলার ও ফোকাস নোড আগে কখনো ডিসপোজ হতো না (StatelessWidget-এ
    // dispose() লাইফসাইকেল নেই ছিল) — এখন সঠিকভাবে ক্লিনআপ হচ্ছে
    _passwordFocusNode.removeListener(_onPasswordFocusChange);
    _passwordFocusNode.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        body: BlocListener<AuthCubit, AuthState>(
          listener: (context, state) {
            if (state is AuthAuthenticated) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("সফলভাবে লগইন হয়েছে! স্বাগতম: ${state.user.displayName}")));
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => HomeScreen(currentUserId: state.user.uid),
                ),
              );
            } else if (state is AuthFailureState) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.failure.message), backgroundColor: AppColors.error));
            }
          },
          child: Container(
            width: double.infinity, height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [AppColors.backgroundTop, AppColors.backgroundMiddle, AppColors.backgroundBottom]
              )
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.large),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420.0),
                    child: Form(
                      key: _formKey,
                      child: BlocBuilder<AuthUiCubit, AuthUiState>(
                        builder: (context, uiState) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(child: AnimatedBearWidget(isCovered: uiState.isCovered, lookX: uiState.lookX)),
                              const SizedBox(height: AppSpacing.extraLarge),
                              Text(uiState.isLoginView ? "Welcome Back" : "Create Account", style: AppTypography.title, textAlign: TextAlign.center),
                              const SizedBox(height: AppSpacing.small),
                              Text("Log in to continue", style: AppTypography.body, textAlign: TextAlign.center),
                              const SizedBox(height: 36),
                              if (!uiState.isLoginView) ...[
                                CustomTextField(
                                  controller: _fullNameController,
                                  hint: "Full Name",
                                  icon: Icons.person_outline,
                                  validator: (v) => (v == null || v.trim().isEmpty) ? "Full name is required" : null,
                                ),
                                const SizedBox(height: 16),
                                CustomTextField(
                                  controller: _usernameController,
                                  hint: "Username",
                                  icon: Icons.alternate_email,
                                  validator: (v) => (v == null || v.trim().isEmpty) ? "Username is required" : null,
                                ),
                                const SizedBox(height: 16),
                              ],
                              CustomTextField(
                                controller: _emailController,
                                hint: "Email",
                                icon: Icons.email_outlined,
                                onChanged: context.read<AuthUiCubit>().updateLookX,
                                validator: (v) {
                                  final value = v?.trim() ?? '';
                                  if (value.isEmpty) return "Email is required";
                                  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                                  if (!emailRegex.hasMatch(value)) return "Enter a valid email address";
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                controller: _passwordController,
                                hint: "Password",
                                icon: Icons.lock_outline,
                                isPassword: true,
                                focusNode: _passwordFocusNode,
                                validator: (v) {
                                  if (v == null || v.isEmpty) return "Password is required";
                                  if (!uiState.isLoginView && v.length < 6) return "Password must be at least 6 characters";
                                  return null;
                                },
                              ),
                              if (!uiState.isLoginView) ...[
                                const SizedBox(height: 16),
                                CustomTextField(
                                  controller: _confirmPasswordController,
                                  hint: "Confirm Password",
                                  icon: Icons.lock_outline,
                                  isPassword: true,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) return "Please confirm your password";
                                    if (v != _passwordController.text) return "Passwords do not match";
                                    return null;
                                  },
                                ),
                              ],
                              const SizedBox(height: 24),
                              BlocBuilder<AuthCubit, AuthState>(
                                builder: (context, authState) {
                                  return PrimaryButton(
                                    label: uiState.isLoginView ? "Log In" : "Sign Up",
                                    isLoading: authState is AuthLoading,
                                    onPressed: () {
                                      if (_formKey.currentState!.validate()) {
                                        final email = _emailController.text.trim();
                                        final password = _passwordController.text;
                                        if (uiState.isLoginView) {
                                          context.read<AuthCubit>().login(email, password);
                                        } else {
                                          context.read<AuthCubit>().register(
                                                fullName: _fullNameController.text.trim(),
                                                username: _usernameController.text.trim(),
                                                email: email,
                                                password: password,
                                              );
                                        }
                                      }
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => context.read<AuthUiCubit>().toggleView(),
                                child: Text(
                                  uiState.isLoginView ? "Don't have an account? Sign Up" : "Already have an account? Log In",
                                  style: AppTypography.body,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
