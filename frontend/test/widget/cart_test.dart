/// Cart widget tests (M5 §3): single-restaurant draft cart — quantity
/// stepper bounds (1..20), removal, clear confirmation, subtotal preview
/// (minor units, server-authoritative wording) and checkout hand-off.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/app/router.dart';
import 'package:quickbite/state/cart_controller.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

/// Sign in, pump the app once and seed the cart with one Margherita Pizza.
/// Returns the container; the caller navigates where it needs to go.
Future<ProviderContainer> _seedCart(
  WidgetTester tester,
  TestBackend backend, {
  int quantity = 1,
}) async {
  await backend.signIn();
  final container = await pumpApp(tester, backend);
  final cart = container.read(cartControllerProvider.notifier);
  cart.add(
    fixtureMenuItem(),
    restaurantId: 'rest_bella_napoli',
    restaurantName: 'Bella Napoli',
  );
  if (quantity > 1) {
    cart.setQuantity('item_margherita_pizza', quantity);
  }
  await tester.pump();
  return container;
}

Finder _plusButton() => find.ancestor(
      of: find.byIcon(Icons.add_rounded),
      matching: find.byType(IconButton),
    );

Finder _minusButton() => find.ancestor(
      of: find.byIcon(Icons.remove_rounded),
      matching: find.byType(IconButton),
    );

void main() {
  setUpAll(initTestLocale);
  setUp(resetPrefs);

  testWidgets('empty cart shows the empty state, not a checkout button',
      (tester) async {
    final backend = TestBackend();
    await backend.signIn();
    final container = await pumpApp(tester, backend);
    container.read(appRouterProvider).go('/cart');
    await tester.pump();

    expect(find.text('My Cart'), findsOneWidget);
    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(find.text('Proceed to checkout'), findsNothing);
  });

  testWidgets('renders the line, restaurant lock notice and subtotal preview',
      (tester) async {
    final backend = TestBackend();
    final container = await _seedCart(tester, backend);
    container.read(appRouterProvider).go('/cart');
    await tester.pump();

    expect(find.text('My Cart'), findsOneWidget);
    expect(find.text('Margherita Pizza'), findsOneWidget);
    expect(find.text('Bella Napoli'), findsOneWidget);
    expect(
      find.text('All cart items must be from one restaurant'),
      findsOneWidget,
    );
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('₹350.00'), findsWidgets, reason: 'unit line + subtotal preview');
    expect(
      find.textContaining('Preview only — the server computes'),
      findsOneWidget,
      reason: 'client never presents the preview as final',
    );
  });

  testWidgets('quantity stepper updates line and subtotal within 1..20',
      (tester) async {
    final backend = TestBackend();
    final container = await _seedCart(tester, backend);
    container.read(appRouterProvider).go('/cart');
    await tester.pump();

    // Increment to 2.
    await tester.tap(_plusButton());
    await tester.pump();
    expect(find.text('₹700.00'), findsWidgets, reason: 'line + subtotal');
    expect(find.text('2'), findsOneWidget);

    // Server max is 20: seed 19, one more tap reaches the cap, then the
    // plus control disables (no client-side inventing of a higher bound).
    container.read(cartControllerProvider.notifier)
        .setQuantity('item_margherita_pizza', 19);
    await tester.pump();
    await tester.tap(_plusButton());
    await tester.pump();
    expect(find.text('20'), findsOneWidget);
    expect(find.text('₹7,000.00'), findsWidgets, reason: 'line + subtotal');
    expect(tester.widget<IconButton>(_plusButton()).onPressed, isNull);

    // Decrement back down.
    await tester.tap(_minusButton());
    await tester.pump();
    expect(find.text('19'), findsOneWidget);
    expect(find.text('₹6,650.00'), findsWidgets, reason: 'line + subtotal');
  });

  testWidgets('decrementing below the minimum removes the line', (tester) async {
    final backend = TestBackend();
    final container = await _seedCart(tester, backend);
    container.read(appRouterProvider).go('/cart');
    await tester.pump();

    await tester.tap(_minusButton());
    await tester.pump();

    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(container.read(cartControllerProvider).lines, isEmpty);
  });

  testWidgets('the remove action deletes exactly that line', (tester) async {
    final backend = TestBackend();
    final container = await _seedCart(tester, backend);
    container.read(appRouterProvider).go('/cart');
    await tester.pump();

    await tester.tap(find.byTooltip('Remove Margherita Pizza'));
    await tester.pump();

    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('clearing the cart requires confirmation', (tester) async {
    final backend = TestBackend();
    final container = await _seedCart(tester, backend);
    container.read(appRouterProvider).go('/cart');
    await tester.pump();

    await tester.tap(find.byTooltip('Clear cart'));
    await tester.pump();
    expect(find.text('Clear the cart?'), findsOneWidget);
    expect(find.text('All items will be removed.'), findsOneWidget);

    // Cancel keeps the cart.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Margherita Pizza'), findsOneWidget);

    // Confirm clears it.
    await tester.tap(find.byTooltip('Clear cart'));
    await tester.pump();
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('proceeding to checkout carries the cart', (tester) async {
    final backend = TestBackend();
    final container = await _seedCart(tester, backend);
    container.read(appRouterProvider).go('/cart');
    await tester.pump();

    await tester.tap(find.text('Proceed to checkout'));
    await tester.pump();

    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('₹350.00'), findsWidgets, reason: 'line + preview subtotal');
  });
}
