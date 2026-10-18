/// Sign-in screen (assignment §7 / Milestone 5 §3): email + password with
/// inline validation, busy state, distinct invalid-credential vs network vs
/// timeout messaging, session-expiry notice, keyboard-friendly flow and
/// accessible controls. POST /api/v1/auth/login via the auth controller;
/// post-login navigation is the router's role-based redirect.
///
/// Design: an immersive brand-red field (reference-led) with oversized brand
/// typography, a short entrance cascade and a raised white sheet holding
/// pill-shaped email/password controls and the coral **Sign In** pill. Logic,
/// field labels, error copy and the action label are unchanged (integration
/// contract).
///
/// Registration and password reset are intentionally NOT implemented
/// (optional per assignment, out of scope for M5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart' show AppTypography;
import '../../core/network/api_exception.dart';
import '../../core/utils/validation.dart';
import '../../state/auth_controller.dart';
import '../../ui/motion/entrance.dart';
import '../../ui/widgets/app_banner.dart';
import '../../ui/widgets/primary_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  ApiException? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
      // Success: the router redirect navigates by role; nothing to do here.
    } on ApiException catch (exc) {
      if (!mounted) return;
      setState(() => _error = exc);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String get _errorMessage {
    final error = _error;
    if (error == null) return '';
    if (error.code == 'INVALID_CREDENTIALS') {
      return 'Email or password is incorrect.';
    }
    if (error.isTimeout) return 'The server took too long to respond. Try again.';
    if (error.isNetwork) return 'Cannot reach the server. Check your connection.';
    return error.message;
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/welcome');
    }
  }

  /// Pill-shaped field chrome (reference: rounded pill controls on a sheet).
  OutlineInputBorder _pillBorder({Color? borderSide, double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        borderSide: BorderSide(
          color: borderSide ?? AppColors.outlineSoft,
          width: width,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final text = Theme.of(context).textTheme;

    ref.listen(authControllerProvider, (previous, next) {
      // Clear field errors when the session-expiry banner changes state.
      if (previous?.sessionExpired != next.sessionExpired) setState(() {});
    });

    return Scaffold(
      backgroundColor: AppColors.brandRedDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.brandRedGradient),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.brandRedGlow),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Entrance(
                        index: 0,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              onPressed: _goBack,
                              color: AppColors.onBrandRed,
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const Spacer(),
                            Text(
                              'QuickBite',
                              style: AppTypography.wordmark(
                                size: 20,
                                color: AppColors.onBrandRed,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Entrance(
                        index: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                'Welcome back',
                                style: text.displaySmall?.copyWith(
                                  color: AppColors.onBrandRed,
                                  fontWeight: FontWeight.w800,
                                  height: 1.05,
                                  letterSpacing: -0.8,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Sign in to browse restaurants and track your '
                              'orders.',
                              style: text.bodyLarge?.copyWith(
                                color: AppColors.onBrandRedSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Entrance(
                        index: 2,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusXl,
                            ),
                            boxShadow: AppShadow.raised,
                          ),
                          child: Form(
                            key: _formKey,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (auth.sessionExpired) ...[
                                  AppBanner(
                                    kind: AppBannerKind.warning,
                                    message:
                                        'Your session expired. Please sign in again.',
                                    actionLabel: 'Got it',
                                    onAction: () => ref
                                        .read(authControllerProvider.notifier)
                                        .acknowledgeSessionExpiry(),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                ],
                                if (_error != null) ...[
                                  Semantics(
                                    liveRegion: true,
                                    child: AppBanner(
                                      kind:
                                          _error!.code == 'INVALID_CREDENTIALS'
                                          ? AppBannerKind.danger
                                          : AppBannerKind.warning,
                                      message: _errorMessage,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                ],
                                TextFormField(
                                  controller: _emailController,
                                  enabled: !_submitting,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.email,
                                    AutofillHints.username,
                                  ],
                                  autocorrect: false,
                                  decoration: InputDecoration(
                                    labelText: 'Email',
                                    hintText: 'you@example.com',
                                    fillColor: AppColors.surfaceWarm,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                      vertical: AppSpacing.lg,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.mail_outline_rounded,
                                    ),
                                    border: _pillBorder(),
                                    enabledBorder: _pillBorder(),
                                    focusedBorder: _pillBorder(
                                      borderSide: AppColors.primary,
                                      width: 1.8,
                                    ),
                                    errorBorder: _pillBorder(
                                      borderSide: AppColors.danger,
                                    ),
                                    focusedErrorBorder: _pillBorder(
                                      borderSide: AppColors.danger,
                                      width: 1.8,
                                    ),
                                  ),
                                  validator: (value) =>
                                      validateEmail(value ?? ''),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                TextFormField(
                                  controller: _passwordController,
                                  enabled: !_submitting,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    hintText: 'Enter your password',
                                    fillColor: AppColors.surfaceWarm,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                      vertical: AppSpacing.lg,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                    border: _pillBorder(),
                                    enabledBorder: _pillBorder(),
                                    focusedBorder: _pillBorder(
                                      borderSide: AppColors.primary,
                                      width: 1.8,
                                    ),
                                    errorBorder: _pillBorder(
                                      borderSide: AppColors.danger,
                                    ),
                                    focusedErrorBorder: _pillBorder(
                                      borderSide: AppColors.danger,
                                      width: 1.8,
                                    ),
                                  ),
                                  validator: (value) =>
                                      validatePassword(value ?? ''),
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                PrimaryButton(
                                  label: 'Sign In',
                                  loading: _submitting,
                                  onPressed: _submit,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Entrance(
                        index: 3,
                        child: Text(
                          'Customer and admin accounts sign in here.\n'
                          'Registration is not available in this build.',
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(
                            color: AppColors.onBrandRed.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
