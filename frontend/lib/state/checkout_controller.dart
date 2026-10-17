/// Checkout controller — IDEMPOTENT order submission (assignment's critical
/// requirement). Invariants enforced here:
///
///  1. One [PendingCheckout] = one canonical request + ONE Idempotency-Key.
///  2. The key and request snapshot are PERSISTED before the first send and
///     kept until the outcome is KNOWN (success or a definite rejection).
///  3. Timeout / connection failure / 5xx = UNCERTAIN outcome: the key and
///     snapshot are RETAINED; retry resends the exact same request with the
///     exact same key — the server replays the original acceptance instead
///     of creating a duplicate order.
///  4. The submit button is locked while a request is in flight.
///  5. 409 (same key, different payload) is surfaced, never silently
///     re-keyed; only an explicit "start over" discards a pending attempt.
///
/// A definite 4xx rejection (validation, unavailable item, unknown
/// restaurant — the server guarantees NO order was created) releases the
/// pending attempt so the user can fix the cart and start a new one.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/network/api_exception.dart';
import '../core/utils/idempotency_key.dart';
import '../data/dto/order_dto.dart';
import 'cart_controller.dart';
import 'providers.dart';

const String _pendingPrefsKey = 'quickbite.pending_checkout.v1';

/// Immutable snapshot of what will be sent — the canonical request bound to
/// a key. Serialized to prefs so an app restart can resume safely.
class PendingCheckout {
  const PendingCheckout({
    required this.idempotencyKey,
    required this.restaurantId,
    required this.restaurantName,
    required this.deliveryAddress,
    required this.lines,
    required this.createdAt,
    this.attempts = 0,
  });

  final String idempotencyKey;
  final String restaurantId;
  final String restaurantName;
  final String deliveryAddress;
  final List<CartLine> lines;
  final DateTime createdAt;

  /// Send attempts so far (any response after the first locks the payload).
  final int attempts;

  bool get hasBeenSent => attempts > 0;
  int get subtotalMinor => lines.fold(0, (sum, line) => sum + line.lineTotalMinor);
  String get currency => lines.isEmpty ? 'INR' : lines.first.currency;

  List<CheckoutItem> get checkoutItems => [
        for (final line in lines)
          CheckoutItem(menuItemId: line.menuItemId, quantity: line.quantity),
      ];

  /// True when the live cart still matches this attempt exactly (used to
  /// decide whether a confirmed checkout should clear the cart).
  bool matchesCart(CartState cart) {
    if (cart.lines.length != lines.length) return false;
    for (final line in lines) {
      final live = cart.line(line.menuItemId);
      if (live == null || live.quantity != line.quantity) return false;
    }
    return true;
  }

  PendingCheckout copyWith({String? deliveryAddress, int? attempts}) => PendingCheckout(
        idempotencyKey: idempotencyKey,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        deliveryAddress: deliveryAddress ?? this.deliveryAddress,
        lines: lines,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
      );

  Map<String, dynamic> toJson() => {
        'idempotency_key': idempotencyKey,
        'restaurant_id': restaurantId,
        'restaurant_name': restaurantName,
        'delivery_address': deliveryAddress,
        'lines': lines.map((line) => line.toJson()).toList(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
      };

  factory PendingCheckout.fromJson(Map<String, dynamic> json) => PendingCheckout(
        idempotencyKey: json['idempotency_key'] as String,
        restaurantId: json['restaurant_id'] as String,
        restaurantName: json['restaurant_name'] as String? ?? '',
        deliveryAddress: json['delivery_address'] as String,
        lines: (json['lines'] as List<dynamic>)
            .map((raw) => CartLine.fromJson(raw as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String),
        attempts: json['attempts'] as int? ?? 0,
      );
}

class CheckoutState {
  const CheckoutState({
    this.pending,
    this.submitting = false,
    this.accepted,
    this.lastError,
  });

  /// No in-flight or uncertain attempt.
  static const CheckoutState idle = CheckoutState();

  final PendingCheckout? pending;
  final bool submitting;

  /// Set exactly once when the server returned 202 (consumed by the
  /// acknowledgement screen, then cleared).
  final CheckoutAccepted? accepted;

  /// Last failure to show; `isUncertainOutcome` distinguishes "retry safely"
  /// from "fix and try again".
  final ApiException? lastError;

  bool get hasPendingAttempt => pending != null;
  bool get pendingIsUncertain => (pending?.hasBeenSent ?? false) && !submitting;

  CheckoutState copyWith({
    PendingCheckout? pending,
    bool clearPending = false,
    bool? submitting,
    CheckoutAccepted? accepted,
    bool clearAccepted = false,
    ApiException? lastError,
    bool clearError = false,
  }) =>
      CheckoutState(
        pending: clearPending ? null : (pending ?? this.pending),
        submitting: submitting ?? this.submitting,
        accepted: clearAccepted ? null : (accepted ?? this.accepted),
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

class CheckoutController extends Notifier<CheckoutState> {
  @override
  CheckoutState build() {
    _restorePending();
    return CheckoutState.idle;
  }

  Future<void> _restorePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final pending = PendingCheckout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!ref.mounted || pending.idempotencyKey.isEmpty) return;
      state = state.copyWith(pending: pending);
    } catch (_) {
      // Corrupt record — discard (it can never be matched to a payload).
    }
  }

  Future<void> _persist(PendingCheckout? pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pending == null) {
        await prefs.remove(_pendingPrefsKey);
      } else {
        await prefs.setString(_pendingPrefsKey, jsonEncode(pending.toJson()));
      }
    } catch (_) {
      // Best effort: in-memory state remains authoritative this run.
    }
  }

  /// Begin (or resume) an attempt for the current cart + address. Called
  /// from the checkout screen's submit action.
  void prepareAttempt({
    required CartState cart,
    required String restaurantName,
    required String deliveryAddress,
  }) {
    if (state.submitting || state.accepted != null) return;
    final existing = state.pending;
    if (existing != null && existing.hasBeenSent) {
      // A previous uncertain attempt owns this key — payload stays locked.
      state = state.copyWith(clearError: true);
      return;
    }
    final pending = PendingCheckout(
      idempotencyKey: existing?.idempotencyKey ?? generateIdempotencyKey(),
      restaurantId: cart.restaurantId ?? '',
      restaurantName: restaurantName,
      deliveryAddress: deliveryAddress.trim(),
      lines: cart.lines,
      createdAt: DateTime.now().toUtc(),
      attempts: 0,
    );
    state = state.copyWith(pending: pending, clearError: true, clearAccepted: true);
    _persist(state.pending);
  }

  /// Send the canonical request. Safe to call again after an uncertain
  /// outcome: identical key + identical payload => server-side replay.
  Future<void> submit() async {
    final pending = state.pending;
    if (pending == null || state.submitting || state.accepted != null) return;
    if (pending.deliveryAddress.trim().isEmpty || pending.lines.isEmpty) return;

    state = state.copyWith(submitting: true, clearError: true);
    final sent = pending.copyWith(attempts: pending.attempts + 1);
    state = state.copyWith(pending: sent);
    await _persist(sent);

    final repo = ref.read(orderRepositoryProvider);
    try {
      final accepted = await repo.checkout(
        idempotencyKey: sent.idempotencyKey,
        restaurantId: sent.restaurantId,
        deliveryAddress: sent.deliveryAddress,
        items: sent.checkoutItems,
      );
      if (!ref.mounted) return;
      // Success: release the key/pending record, clear the ordered lines.
      await _persist(null);
      ref.read(cartControllerProvider.notifier).clearFulfilled(
            sent.restaurantId,
            [for (final line in sent.lines) line.menuItemId],
          );
      state = state.copyWith(
        clearPending: true,
        clearError: true,
        submitting: false,
        accepted: accepted,
      );
    } on ApiException catch (exc) {
      if (!ref.mounted) return;
      _handleFailure(sent, exc);
    }
  }

  void _handleFailure(PendingCheckout sent, ApiException exc) {
    final uncertain = exc.isUncertainOutcome || (exc.statusCode ?? 0) >= 500;

    if (uncertain) {
      // NO order state is known — KEEP the key and snapshot for a safe retry.
      state = state.copyWith(
        pending: sent,
        submitting: false,
        lastError: exc,
      );
      _persist(sent);
      return;
    }

    if (exc.isConflict) {
      // Same key, different payload (should be impossible while locked) —
      // surface it; only an explicit user action releases the key.
      state = state.copyWith(submitting: false, lastError: exc);
      return;
    }

    if (exc.isUnauthorized) {
      // Session expired mid-request: the response PROVES no order was
      // created (auth runs before checkout logic), but keep the pending
      // attempt so the user can resume with the same key after re-login.
      state = state.copyWith(submitting: false, lastError: exc);
      return;
    }

    // Definite rejection (4xx validation, 404, 403): no order exists —
    // release the attempt so the user can fix and start a fresh one.
    _discard(silent: true);
    state = state.copyWith(submitting: false, lastError: exc);
  }

  /// Explicit user action: abandon a pending attempt (with its key).
  Future<void> discardPending() => _discard();

  Future<void> _discard({bool silent = false}) async {
    await _persist(null);
    if (!ref.mounted) return;
    // `silent` keeps any existing error message for the caller to replace.
    state = state.copyWith(
      clearPending: true,
      submitting: false,
      clearError: !silent,
    );
  }

  /// Acknowledgement screen consumed the accepted response.
  void acknowledgeAccepted() {
    if (state.accepted != null) {
      state = state.copyWith(clearAccepted: true, clearError: true);
    }
  }

  void clearError() {
    if (state.lastError != null) {
      state = state.copyWith(clearError: true);
    }
  }
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);
