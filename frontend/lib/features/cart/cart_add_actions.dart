/// Shared add-to-cart result handling — ONE implementation used by the menu
/// rows and the item detail screen (no duplicated logic).
///
/// Handles every [CartAddResult]: silent success, the two server caps
/// (snackbars with the exact contract messages), and the single-restaurant
/// conflict (explicit confirm dialog — never silent data loss). Optional
/// [extraQuantity] performs additional increments after a successful add,
/// for "pick a quantity, then add" flows on item detail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/cart_controller.dart';
import '../../data/dto/catalog_dto.dart';

Future<void> handleCartAdd({
  required BuildContext context,
  required WidgetRef ref,
  required CartAddResult result,
  required MenuItem item,
  required String restaurantId,
  required String restaurantName,
  int extraQuantity = 0,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  switch (result) {
    case CartAddResult.added:
      _incrementExtra(ref, item.id, extraQuantity);
      return;
    case CartAddResult.quantityMaxed:
      messenger.showSnackBar(
        const SnackBar(content: Text('Maximum quantity per item is 20.')),
      );
      return;
    case CartAddResult.tooManyDistinctItems:
      messenger.showSnackBar(
        const SnackBar(content: Text('Cart holds up to 20 different items.')),
      );
      return;
    case CartAddResult.restaurantConflict:
      await _confirmConflict(
        context: context,
        ref: ref,
        item: item,
        restaurantId: restaurantId,
        restaurantName: restaurantName,
        extraQuantity: extraQuantity,
      );
  }
}

void _incrementExtra(WidgetRef ref, String itemId, int extra) {
  if (extra <= 0) return;
  final cart = ref.read(cartControllerProvider.notifier);
  for (var i = 0; i < extra; i++) {
    cart.increment(itemId);
  }
}

Future<void> _confirmConflict({
  required BuildContext context,
  required WidgetRef ref,
  required MenuItem item,
  required String restaurantId,
  required String restaurantName,
  required int extraQuantity,
}) async {
  final cart = ref.read(cartControllerProvider);
  final existingName =
      cart.restaurantName?.isNotEmpty == true ? cart.restaurantName! : 'another restaurant';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Start a new cart?'),
      content: Text(
        'Your cart has items from $existingName. '
        'Adding "${item.name}" from ${restaurantName.isEmpty ? 'this restaurant' : restaurantName} '
        'will clear it first.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size(150, 44)),
          child: const Text('Clear & add'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    final notifier = ref.read(cartControllerProvider.notifier);
    notifier.replaceAndAdd(
      item,
      restaurantId: restaurantId,
      restaurantName: restaurantName,
    );
    _incrementExtra(ref, item.id, extraQuantity);
  }
}
