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

import 'package:flutter/foundation.dart' show kDebugMode;
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
import '../../ui/widgets/brand_stage.dart';

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
    if (error.isTimeout) {
      return 'The server took too long to respond. Try again.';
    }
    if (error.isNetwork) {
      return 'Cannot reach the server. Check your connection.';
    }
    return error.message;
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/welcome');
    }
  }

  void _fillDemo(String email, String password) {
    setState(() {
      _emailController.text = email;
      _passwordController.text = password;
      _error = null;
    });
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
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    ref.listen(authControllerProvider, (previous, next) {
      // Clear field errors when the session-expiry banner changes state.
      if (previous?.sessionExpired != next.sessionExpired) setState(() {});
    });

    final form = Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (auth.sessionExpired) ...[
            AppBanner(
              kind: AppBannerKind.warning,
              message: 'Your session expired. Please sign in again.',
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
                kind: _error!.code == 'INVALID_CREDENTIALS'
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
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'you@example.com',
              fillColor: AppColors.surfaceWarm,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              border: _pillBorder(),
              enabledBorder: _pillBorder(),
              focusedBorder: _pillBorder(
                borderSide: AppColors.primary,
                width: 1.8,
              ),
              errorBorder: _pillBorder(borderSide: AppColors.danger),
              focusedErrorBorder: _pillBorder(
                borderSide: AppColors.danger,
                width: 1.8,
              ),
            ),
            validator: (value) => validateEmail(value ?? ''),
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
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: _pillBorder(),
              enabledBorder: _pillBorder(),
              focusedBorder: _pillBorder(
                borderSide: AppColors.primary,
                width: 1.8,
              ),
              errorBorder: _pillBorder(borderSide: AppColors.danger),
              focusedErrorBorder: _pillBorder(
                borderSide: AppColors.danger,
                width: 1.8,
              ),
            ),
            validator: (value) => validatePassword(value ?? ''),
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Sign In',
            loading: _submitting,
            onPressed: _submit,
          ),
          if (kDebugMode) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _fillDemo(
                            'alice@quickbite.dev',
                            'quickbite!alice1',
                          ),
                    icon: const Icon(Icons.person_outline_rounded),
                    label: const Text('Customer demo'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _fillDemo(
                            'admin@quickbite.dev',
                            'quickbite!admin1',
                          ),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Admin demo'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    final sheet = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadow.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sign in', style: text.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Your next favourite is waiting.',
            style: text.bodyMedium?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 24),
          form,
        ],
      ),
    );
    final headline = Semantics(
      header: true,
      child: Text(
        'Good to\nsee you.',
        style: TextStyle(
          color: Colors.white,
          fontSize: MediaQuery.sizeOf(context).width >= 900 ? 76 : 48,
          height: .98,
          letterSpacing: -2,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    return Scaffold(
      backgroundColor: AppColors.brandRed,
      body: BrandStage(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 900;
              final keyboard = keyboardVisible;
              final intro = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: _goBack,
                        color: Colors.white,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          'QuickBite',
                          style: AppTypography.wordmark(
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: keyboard
                            ? const Text(
                                'Welcome back',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : Entrance(child: headline),
                      ),
                      if (!wide &&
                          !keyboard &&
                          MediaQuery.textScalerOf(context).scale(16) < 21)
                        const Expanded(
                          flex: 2,
                          child: SizedBox(height: 132, child: BurgerHero()),
                        ),
                    ],
                  ),
                  if (wide) const SizedBox(height: 320, child: BurgerHero()),
                ],
              );
              return Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.all(wide ? 48 : 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: wide
                        ? Row(
                            children: [
                              Expanded(child: intro),
                              const SizedBox(width: 64),
                              Expanded(child: Entrance(index: 1, child: sheet)),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              intro,
                              const SizedBox(height: 24),
                              Entrance(index: 1, child: sheet),
                              const SizedBox(height: 16),
                              const Text(
                                'Fresh choices. One QuickBite.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
