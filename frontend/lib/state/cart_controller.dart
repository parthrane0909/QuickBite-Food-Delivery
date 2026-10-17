/// Cart controller: a client-side DRAFT with the server's exact bounds
/// (quantity 1..20, at most 20 distinct items, single restaurant). Money
/// stays in integer minor units. The cart is a PREVIEW only — FastAPI
/// re-validates and re-prices authoritatively at checkout (assignment §6).
///
/// Draft persistence uses shared_preferences (non-secret UI state — allowed
/// on every platform; tokens never live here).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/dto/catalog_dto.dart';

const int kQuantityMin = 1;
const int kQuantityMax = 20; // backend QUANTITY_MAX
const int kMaxDistinctItems = 20; // backend MAX_DISTINCT_ITEMS
const String _cartPrefsKey = 'quickbite.cart.v1';

class CartLine {
  const CartLine({
    required this.menuItemId,
    required this.name,
    required this.priceMinor,
    required this.currency,
    required this.isAvailable,
    required this.quantity,
  });

  final String menuItemId;
  final String name;
  final int priceMinor;
  final String currency;
  final bool isAvailable;
  final int quantity;

  int get lineTotalMinor => priceMinor * quantity;

  CartLine withQuantity(int quantity) => CartLine(
        menuItemId: menuItemId,
        name: name,
        priceMinor: priceMinor,
        currency: currency,
        isAvailable: isAvailable,
        quantity: quantity,
      );

  Map<String, dynamic> toJson() => {
        'menu_item_id': menuItemId,
        'name': name,
        'price_minor': priceMinor,
        'currency': currency,
        'is_available': isAvailable,
        'quantity': quantity,
      };

  factory CartLine.fromJson(Map<String, dynamic> json) => CartLine(
        menuItemId: json['menu_item_id'] as String,
        name: json['name'] as String,
        priceMinor: json['price_minor'] as int,
        currency: json['currency'] as String,
        isAvailable: json['is_available'] as bool? ?? true,
        quantity: json['quantity'] as int,
      );
}

class CartState {
  const CartState({
    this.restaurantId,
    this.restaurantName,
    this.lines = const [],
  });

  static const CartState empty = CartState();

  final String? restaurantId;
  final String? restaurantName;
  final List<CartLine> lines;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);
  int get subtotalMinor => lines.fold(0, (sum, line) => sum + line.lineTotalMinor);
  String get currency => lines.isEmpty ? 'INR' : lines.first.currency;

  CartLine? line(String menuItemId) {
    for (final line in lines) {
      if (line.menuItemId == menuItemId) return line;
    }
    return null;
  }
}

/// Outcome of `add` — the screen maps each case to UI (dialog/snackbar).
enum CartAddResult { added, restaurantConflict, tooManyDistinctItems, quantityMaxed }

class CartController extends Notifier<CartState> {
  @override
  CartState build() {
    _restoreDraft();
    return CartState.empty;
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cartPrefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final lines = (decoded['lines'] as List<dynamic>? ?? [])
          .map((raw) => CartLine.fromJson(raw as Map<String, dynamic>))
          .where((line) => line.quantity >= kQuantityMin && line.quantity <= kQuantityMax)
          .toList();
      if (!ref.mounted || lines.isEmpty) return;
      state = CartState(
        restaurantId: decoded['restaurant_id'] as String?,
        restaurantName: decoded['restaurant_name'] as String?,
        lines: lines,
      );
    } catch (_) {
      // Corrupt draft — start clean rather than crash.
    }
  }

  void _persist() {
    // Fire-and-forget: a draft save failure must never break the UI.
    SharedPreferences.getInstance().then((prefs) {
      final payload = jsonEncode({
        'restaurant_id': state.restaurantId,
        'restaurant_name': state.restaurantName,
        'lines': state.lines.map((line) => line.toJson()).toList(),
        'saved_at': DateTime.now().toUtc().toIso8601String(),
      });
      return prefs.setString(_cartPrefsKey, payload);
    }).catchError((Object _) => false);
  }

  void _update(CartState next) {
    if (!ref.mounted) return;
    state = next;
    _persist();
  }

  CartAddResult add(
    MenuItem item, {
    required String restaurantId,
    required String restaurantName,
  }) {
    if (state.restaurantId != null &&
        state.restaurantId != restaurantId &&
        state.lines.isNotEmpty) {
      return CartAddResult.restaurantConflict;
    }
    final existing = state.line(item.id);
    if (existing != null) {
      if (existing.quantity >= kQuantityMax) return CartAddResult.quantityMaxed;
      _update(state.copyWith(
        lines: [
          for (final line in state.lines)
            if (line.menuItemId == item.id)
              line.withQuantity(existing.quantity + 1)
            else
              line,
        ],
      ));
      return CartAddResult.added;
    }
    if (state.lines.length >= kMaxDistinctItems) {
      return CartAddResult.tooManyDistinctItems;
    }
    _update(CartState(
      restaurantId: restaurantId,
      restaurantName: restaurantName,
      lines: [
        ...state.lines,
        CartLine(
          menuItemId: item.id,
          name: item.name,
          priceMinor: item.priceMinor,
          currency: item.currency,
          isAvailable: item.isAvailable,
          quantity: kQuantityMin,
        ),
      ],
    ));
    return CartAddResult.added;
  }

  /// Single-restaurant rule: replace the cart, then add (explicit user
  /// confirmation happens in the UI before calling this).
  CartAddResult replaceAndAdd(
    MenuItem item, {
    required String restaurantId,
    required String restaurantName,
  }) {
    clear();
    return add(item, restaurantId: restaurantId, restaurantName: restaurantName);
  }

  void setQuantity(String menuItemId, int quantity) {
    final existing = state.line(menuItemId);
    if (existing == null) return;
    if (quantity < kQuantityMin) {
      remove(menuItemId);
      return;
    }
    if (quantity > kQuantityMax) return;
    _update(state.copyWith(
      lines: [
        for (final line in state.lines)
          if (line.menuItemId == menuItemId) line.withQuantity(quantity) else line,
      ],
    ));
  }

  void increment(String menuItemId) {
    final existing = state.line(menuItemId);
    if (existing == null) return;
    setQuantity(menuItemId, existing.quantity + 1);
  }

  void decrement(String menuItemId) {
    final existing = state.line(menuItemId);
    if (existing == null) return;
    setQuantity(menuItemId, existing.quantity - 1);
  }

  void remove(String menuItemId) {
    _update(state.copyWith(
      lines: state.lines.where((line) => line.menuItemId != menuItemId).toList(),
    ));
  }

  void clear() {
    _update(CartState.empty);
  }

  /// After a confirmed checkout: drop exactly the lines that were ordered —
  /// if the user kept editing the cart during retries, their newer edits
  /// survive for a fresh attempt (and a completely different cart, e.g.
  /// another restaurant started meanwhile, is left untouched).
  void clearFulfilled(String restaurantId, List<String> fulfilledItemIds) {
    final remaining =
        state.lines.where((line) => !fulfilledItemIds.contains(line.menuItemId)).toList();
    if (remaining.isEmpty) {
      _update(CartState.empty);
      return;
    }
    if (state.restaurantId == restaurantId) {
      _update(CartState(
        restaurantId: state.restaurantId,
        restaurantName: state.restaurantName,
        lines: remaining,
      ));
    }
    // else: the live cart belongs to another restaurant — keep it intact.
  }
}

final cartControllerProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);

extension on CartState {
  CartState copyWith({String? restaurantId, String? restaurantName, List<CartLine>? lines}) =>
      CartState(
        restaurantId: lines == null ? restaurantId : (restaurantId ?? this.restaurantId),
        restaurantName:
            lines == null ? restaurantName : (restaurantName ?? this.restaurantName),
        lines: lines ?? this.lines,
      );
}
