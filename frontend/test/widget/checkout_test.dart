/// Checkout widget tests (M5 §3/§6 — the idempotency-critical screen):
/// address validation, the uncertain-outcome path keeping the SAME key and
/// payload across retries, 409 conflict surfacing with an explicit discard,
/// definite-rejection auto-discard, 401 resume, and the 202 acknowledgement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/app/router.dart';
import 'package:quickbite/core/network/api_exception.dart';
import 'package:quickbite/state/cart_controller.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

const _address = 'Flat 42, MG Road, Bengaluru';

Future<ProviderContainer> _openCheckout(
  WidgetTester tester,
  TestBackend backend, {
  int quantity = 1,
}) async {
  await backend.signIn();
  // Tall surface: the banners (retry/conflict notices) can push the action
  // button below the fold on a phone-sized viewport, and these tests are
  // about idempotency behaviour, not scrolling.
  final container = await pumpApp(
    tester,
    backend,
    surfaceSize: const Size(600, 1600),
  );
  final cart = container.read(cartControllerProvider.notifier);
  cart.add(
    fixtureMenuItem(),
    restaurantId: 'rest_bella_napoli',
    restaurantName: 'Bella Napoli',
  );
  if (quantity > 1) cart.setQuantity('item_margherita_pizza', quantity);
  await tester.pump();

  container.read(appRouterProvider).go('/checkout');
  await tester.pump();
  expect(find.text('Checkout'), findsOneWidget);
  return container;
}

Future<void> _placeOrder(WidgetTester tester, {String address = _address}) async {
  await tester.enterText(find.byType(TextFormField).first, address);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Place order'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(initTestLocale);
  setUp(resetPrefs);

  testWidgets('empty cart shows the nothing-to-check-out state', (tester) async {
    final backend = TestBackend();
    await backend.signIn();
    final container = await pumpApp(tester, backend);
    container.read(appRouterProvider).go('/checkout');
    await tester.pump();

    expect(find.text('Nothing to check out'), findsOneWidget);
    expect(find.text('Add items to your cart first.'), findsOneWidget);
  });

  testWidgets('address is required before any request is sent', (tester) async {
    final backend = TestBackend();
    await _openCheckout(tester, backend);

    await tester.tap(find.widgetWithText(FilledButton, 'Place order'));
    await tester.pump();

    expect(find.text('Enter a delivery address.'), findsOneWidget);
    expect(backend.orders.checkoutCalls, isEmpty, reason: 'no request sent');
  });

  testWidgets(
      'timeout keeps the key: retry re-sends the IDENTICAL request, then '
      'succeeds', (tester) async {
    final backend = TestBackend()
      ..orders.checkoutScript.add(const ApiException(
        code: 'timeout',
        statusCode: null,
        message: 'No response within 15s',
      ));
    await _openCheckout(tester, backend);
    await _placeOrder(tester);

    // Uncertain outcome: the server may still be processing — the pending
    // attempt is kept, the UI says so, and retry reuses the SAME key.
    expect(backend.orders.checkoutCalls, hasLength(1));
    expect(
      find.textContaining('No response from the server'),
      findsOneWidget,
      reason: 'uncertain outcome is never presented as failure or success',
    );
    expect(
      find.textContaining('Retrying your previous attempt'),
      findsOneWidget,
    );
    final retryButton = find.widgetWithText(FilledButton, 'Retry same order (safe)');
    expect(retryButton, findsOneWidget);

    await tester.tap(retryButton);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Second call: identical key + identical payload => server-side replay.
    expect(backend.orders.checkoutCalls, hasLength(2));
    final first = backend.orders.checkoutCalls[0];
    final second = backend.orders.checkoutCalls[1];
    expect(first.idempotencyKey, isNotEmpty);
    expect(second.idempotencyKey, first.idempotencyKey);
    expect(second.restaurantId, first.restaurantId);
    expect(second.deliveryAddress, first.deliveryAddress);
    expect(second.items, hasLength(first.items.length));
    expect(second.items.single.menuItemId, first.items.single.menuItemId);
    expect(second.items.single.quantity, first.items.single.quantity);

    // 202 acknowledgement screen: acceptance, NOT payment/delivery.
    expect(find.text('Order accepted!'), findsOneWidget);
    expect(
      find.textContaining('Order accepted for asynchronous processing'),
      findsOneWidget,
    );
  });

  testWidgets('discarding an uncertain attempt asks for confirmation',
      (tester) async {
    final backend = TestBackend()
      ..orders.checkoutScript.add(const ApiException(
        code: 'timeout',
        statusCode: null,
        message: 'No response within 15s',
      ));
    await _openCheckout(tester, backend);
    await _placeOrder(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Discard attempt & start over'));
    await tester.pump();

    expect(find.text('Discard the pending attempt?'), findsOneWidget);
    expect(find.text('Keep retrying'), findsOneWidget);

    // Cancelling keeps the safe retry available.
    await tester.tap(find.text('Keep retrying'));
    await tester.pump();
    expect(
      find.widgetWithText(FilledButton, 'Retry same order (safe)'),
      findsOneWidget,
    );

    // Confirming releases the key and returns to a fresh attempt.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Discard attempt & start over'));
    await tester.pump();
    await tester.tap(find.text('Discard attempt'));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Place order'), findsOneWidget);
    expect(find.textContaining('No response from the server'), findsNothing);
  });

  testWidgets('a 409 idempotency conflict surfaces and can be discarded',
      (tester) async {
    final backend = TestBackend()
      ..orders.checkoutScript.add(const ApiException(
        code: 'IDEMPOTENCY_CONFLICT',
        statusCode: 409,
        message: 'This idempotency key was used with a different request',
        details: {'current_order_id': 'order_9'},
      ));
    await _openCheckout(tester, backend);
    await _placeOrder(tester);

    expect(find.textContaining('Idempotency conflict'), findsOneWidget);
    expect(
      find.textContaining('This key was already used with a different request'),
      findsOneWidget,
    );
    // A 409 is a DEFINITE server answer — no uncertainty dialog on discard.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Discard attempt & start over'));
    await tester.pump();
    expect(find.text('Discard the pending attempt?'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Place order'), findsOneWidget);
    expect(backend.orders.checkoutCalls, hasLength(1));
  });

  testWidgets('a definite 4xx rejection auto-discards the attempt',
      (tester) async {
    final backend = TestBackend()
      ..orders.checkoutScript.add(const ApiException(
        code: 'VALIDATION_ERROR',
        statusCode: 422,
        message: 'Address is outside the delivery zone',
      ));
    await _openCheckout(tester, backend);
    await _placeOrder(tester);

    // No order exists after a 4xx: the key is released automatically and a
    // fresh attempt is possible immediately.
    expect(find.textContaining('Order not placed'), findsOneWidget);
    expect(find.textContaining('Address is outside the delivery zone'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Place order'), findsOneWidget);
    expect(find.textContaining('Retry same order'), findsNothing);
    expect(backend.orders.checkoutCalls, hasLength(1));
  });

  testWidgets('a 401 keeps the attempt so it can resume after re-login',
      (tester) async {
    final backend = TestBackend()
      ..orders.checkoutScript.add(const ApiException(
        code: 'TOKEN_EXPIRED',
        statusCode: 401,
        message: 'Token expired',
      ));
    await _openCheckout(tester, backend);
    await _placeOrder(tester);

    expect(find.textContaining('Session expired'), findsOneWidget);
    expect(
      find.textContaining('this attempt is saved and can be retried safely'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Retry same order (safe)'),
      findsOneWidget,
      reason: 'the pending attempt survives the 401',
    );
    expect(backend.orders.checkoutCalls, hasLength(1));
  });

  testWidgets('a successful checkout clears the ordered lines', (tester) async {
    final backend = TestBackend();
    final container = await _openCheckout(tester, backend);
    await _placeOrder(tester);

    expect(find.text('Order accepted!'), findsOneWidget);
    expect(container.read(cartControllerProvider).lines, isEmpty);

    // The acknowledgement offers the live tracking screen.
    await tester.tap(find.widgetWithText(FilledButton, 'Track this order'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Order details'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the server-issued total is shown on the acknowledgement',
      (tester) async {
    final backend = TestBackend();
    await _openCheckout(tester, backend, quantity: 2);
    await _placeOrder(tester);

    expect(find.text('Order accepted!'), findsOneWidget);
    expect(
      find.text('₹700.00'),
      findsOneWidget,
      reason: 'server-authoritative total (2 x 350.00), not the preview',
    );
  });
}
