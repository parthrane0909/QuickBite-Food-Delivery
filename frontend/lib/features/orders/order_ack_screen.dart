/// Order acknowledgement (M5 §3): shown after HTTP 202. Displays the
/// SERVER-issued order id, the server's accepted total + currency, the
/// initial status (PENDING) and the acceptance message — with explicit
/// wording that this is ASYNCHRONOUS ACCEPTANCE, not payment completion or
/// delivery (assignment: do not imply success beyond 202).
///
/// Deep-link / reload fallback: if the in-memory acceptance is gone (it is
/// deliberately never persisted — no order secrets in storage), forward to
/// the live tracking screen, which fetches authoritative state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../state/checkout_controller.dart';
import '../../ui/widgets/money_text.dart';
import '../../ui/widgets/status_chip.dart';

class OrderAckScreen extends ConsumerStatefulWidget {
  const OrderAckScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderAckScreen> createState() => _OrderAckScreenState();
}

class _OrderAckScreenState extends ConsumerState<OrderAckScreen> {
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFallback());
  }

  void _checkFallback() {
    final accepted = ref.read(checkoutControllerProvider).accepted;
    if (accepted == null && !_redirected && mounted) {
      _redirected = true;
      // No acceptance payload to show (page reload / deep link): the live
      // tracking screen shows the same facts from the server.
      context.go('/orders/${widget.orderId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final checkout = ref.watch(checkoutControllerProvider);
    final accepted = checkout.accepted;
    final text = Theme.of(context).textTheme;

    if (accepted == null) {
      // Handing off to tracking (or a brief build while redirecting).
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  // Confirmation mark (drawn — original, no external art).
                  Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.6, end: 1),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Container(
                        width: 104,
                        height: 104,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryTint,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 60,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Order accepted!',
                    textAlign: TextAlign.center,
                    style: text.headlineLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Your order has been accepted for processing. Payment and '
                    'restaurant confirmation follow asynchronously — we will '
                    'update you as each step completes.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          _DetailRow(
                            label: 'Order ID',
                            value: accepted.orderId,
                            selectable: true,
                            mono: true,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _DetailRow(
                            label: 'Accepted total',
                            child: MoneyText(
                              accepted.totalAmountMinor,
                              currency: accepted.currency,
                              style: text.titleMedium,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Status', style: text.bodyMedium),
                              StatusChip(accepted.status),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _DetailRow(label: 'Server message', value: accepted.message),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  FilledButton.icon(
                    onPressed: () => context.go('/orders/${accepted.orderId}'),
                    icon: const Icon(Icons.route_rounded),
                    label: const Text('Track this order'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/orders'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('View order history'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () => context.go('/restaurants'),
                    child: const Text('Back to restaurants'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    this.value,
    this.child,
    this.selectable = false,
    this.mono = false,
  });

  final String label;
  final String? value;
  final Widget? child;
  final bool selectable;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.bodyMedium),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: child ??
              SelectableText(
                value ?? '',
                textAlign: TextAlign.end,
                style: mono
                    ? text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )
                    : text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
        ),
      ],
    );
  }
}
