/// Checkout (M5 §3, CRITICAL idempotency requirements):
///
/// - Address entry with inline validation (backend bounds) + counter.
/// - Cart summary from the canonical snapshot; subtotal is a UI preview —
///   the SERVER's 202 total is what the acknowledgement shows.
/// - One `Idempotency-Key` per distinct attempt, persisted with the exact
///   request it describes (checkout_controller) and RETAINED across
///   uncertain outcomes: a timeout keeps the button on "retry the same
///   request safely" — never a fresh key, never a duplicate order.
/// - Submit button locked while in flight; 409 conflict surfaces with an
///   explicit "start over" instead of silent re-keying; definite 4xx
///   rejections release the attempt so the cart can be fixed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/validation.dart';
import '../../state/auth_controller.dart';
import '../../state/cart_controller.dart';
import '../../state/checkout_controller.dart';
import '../../ui/widgets/app_banner.dart';
import '../../ui/widgets/async_state_view.dart';
import '../../ui/widgets/money_text.dart';
import '../../ui/widgets/primary_button.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Prefill from a restored pending attempt (address is then locked).
    final pending = ref.read(checkoutControllerProvider).pending;
    if (pending != null) _addressController.text = pending.deliveryAddress;
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder({
    required bool hasPending,
    required CartState cart,
    required String restaurantName,
  }) async {
    final notifier = ref.read(checkoutControllerProvider.notifier);
    if (!hasPending) {
      final form = _formKey.currentState;
      if (form == null || !form.validate()) return;
      notifier.prepareAttempt(
        cart: cart,
        restaurantName: restaurantName,
        deliveryAddress: _addressController.text,
      );
    }
    await notifier.submit();
  }

  Future<void> _discardAttempt() async {
    final uncertain =
        ref.read(checkoutControllerProvider).lastError?.isUncertainOutcome ?? false;
    if (uncertain) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard the pending attempt?'),
          content: const Text(
            'The server may have received your order even though the response '
            'never arrived. Check your order history before discarding — a new '
            'attempt will use a NEW key and could create a duplicate order.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep retrying'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(minimumSize: const Size(150, 44)),
              child: const Text('Discard attempt'),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false)) return;
    }
    if (!mounted) return;
    await ref.read(checkoutControllerProvider.notifier).discardPending();
    if (!mounted) return;
    // The snapshot is gone — the address field is editable again; if there
    // is nothing left to buy, return to the (empty) cart.
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) context.go('/cart');
  }

  ({String title, String message, AppBannerKind kind})? _errorBanner(
    ApiException? error,
    bool hasPendingAttempt,
  ) {
    if (error == null) return null;
    if (error.isUncertainOutcome || (error.statusCode ?? 0) >= 500) {
      return (
        kind: AppBannerKind.warning,
        title: 'No response from the server',
        message:
            'Your order was NOT confirmed, but it may still be processing. '
            'Retrying re-sends the exact same request with the same key, so '
            'it cannot create a duplicate order.',
      );
    }
    if (error.isConflict) {
      return (
        kind: AppBannerKind.danger,
        title: 'Idempotency conflict',
        message:
            'This key was already used with a different request. Discard the '
            'attempt and start a new checkout.',
      );
    }
    if (error.isUnauthorized) {
      return (
        kind: AppBannerKind.warning,
        title: 'Session expired',
        message:
            'Sign in again to continue — this attempt is saved and can be '
            'retried safely with the same key.',
      );
    }
    return (
      kind: AppBannerKind.danger,
      title: hasPendingAttempt ? 'The server rejected the order' : 'Order not placed',
      message: error.message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final checkout = ref.watch(checkoutControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final text = Theme.of(context).textTheme;

    ref.listen(checkoutControllerProvider.select((state) => state.accepted),
        (previous, next) {
      if (next != null) {
        context.pushReplacement('/orders/${next.orderId}/accepted');
      }
    });

    final pending = checkout.pending;
    final hasPending = pending != null;
    final sentPending = pending != null && pending.hasBeenSent;
    final lines = pending?.lines ?? cart.lines;
    final restaurantName = (pending?.restaurantName.isNotEmpty ?? false)
        ? pending!.restaurantName
        : (cart.restaurantName ?? '');
    final subtotal = pending?.subtotalMinor ?? cart.subtotalMinor;
    final currency = pending?.currency ?? cart.currency;

    if (!hasPending && cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: EmptyState(
          icon: Icons.shopping_cart_outlined,
          title: 'Nothing to check out',
          message: 'Add items to your cart first.',
          actionLabel: 'Browse restaurants',
          onAction: () => context.go('/restaurants'),
        ),
      );
    }

    final banner = _errorBanner(checkout.lastError, hasPending);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          // canPop guard: a deep-link reload starts with an empty stack.
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/cart');
            }
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              if (sentPending) ...[
                AppBanner(
                  kind: checkout.submitting
                      ? AppBannerKind.info
                      : AppBannerKind.warning,
                  message: checkout.submitting
                      ? 'Sending your order…'
                      : 'Retrying your previous attempt: the SAME request with '
                          'the SAME idempotency key is re-sent, so the server '
                          'replays the original outcome instead of duplicating it.',
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (banner != null) ...[
                Semantics(
                  liveRegion: true,
                  child: AppBanner(
                    kind: banner.kind,
                    message: '${banner.title}. ${banner.message}',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // --- Delivery address ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Delivery address', style: text.titleMedium),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _addressController,
                          readOnly: sentPending || checkout.submitting,
                          enabled: !checkout.submitting,
                          maxLines: 3,
                          maxLength: 500,
                          minLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Flat / street / city — where should the '
                                'driver deliver?',
                            counterText:
                                sentPending ? 'Locked while retrying' : null,
                            helperText: sentPending
                                ? 'Locked: a retry must resend the identical request.'
                                : null,
                          ),
                          validator: (value) => validateDeliveryAddress(value ?? ''),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // --- Order summary ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              restaurantName,
                              style: text.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${lines.length} item${lines.length == 1 ? '' : 's'}',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                      const Divider(height: AppSpacing.xl),
                      for (final line in lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${line.quantity} × ${line.name}',
                                  style: text.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              MoneyText(
                                line.lineTotalMinor,
                                currency: line.currency,
                                style: text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: AppSpacing.xl),
                      // Flexible label: narrow screens must never overflow.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'Subtotal (preview)',
                              style: text.bodyLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          MoneyText(subtotal, currency: currency, style: text.titleMedium),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'The final order total is computed by the QuickBite '
                        'server when your order is accepted — prices on this '
                        'screen are a preview.',
                        style: text.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // --- Actions ---
              PrimaryButton(
                label: sentPending
                    ? (checkout.submitting ? 'Retrying…' : 'Retry same order (safe)')
                    : 'Place order',
                loading: checkout.submitting,
                onPressed: checkout.submitting
                    ? null
                    : () => _placeOrder(
                          hasPending: sentPending,
                          cart: cart,
                          restaurantName: restaurantName,
                        ),
              ),
              if (hasPending && !checkout.submitting) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Discard attempt & start over'),
                  onPressed: _discardAttempt,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: checkout.submitting
                    ? null
                    : () => context.go('/cart'),
                child: const Text('Back to cart'),
              ),
              if (auth.isAdmin) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Admin accounts cannot place orders.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
