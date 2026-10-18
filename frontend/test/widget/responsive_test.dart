/// Responsive layout widget tests (M5 §6): the shell switches between
/// NavigationRail (>=900w) and NavigationBar below, and key screens render
/// at the narrowest supported width without overflow exceptions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/state/cart_controller.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

const _narrow = Size(360, 780);
const _wide = Size(1200, 900);

void main() {
  setUpAll(initTestLocale);
  setUp(resetPrefs);

  testWidgets('narrow width uses the bottom NavigationBar', (tester) async {
    final backend = TestBackend();
    await backend.signIn();
    await pumpApp(tester, backend, surfaceSize: _narrow);
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
  });

  testWidgets('wide width uses the NavigationRail', (tester) async {
    final backend = TestBackend();
    await backend.signIn();
    await pumpApp(tester, backend, surfaceSize: _wide);
    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('an admin gets a single-destination shell at both widths', (
    tester,
  ) async {
    final backend = TestBackend();
    await backend.signIn(role: 'admin');

    await pumpApp(tester, backend, surfaceSize: _narrow);
    await tester.pump();
    // One destination: a NavigationBar would assert (min 2 destinations) and
    // there is nothing to switch, so the shell renders the dashboard alone.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('Admin overview'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    resetPrefs();
    await pumpApp(tester, backend, surfaceSize: _wide);
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('key screens fit the narrowest supported width (no overflow)', (
    tester,
  ) async {
    final backend = TestBackend();
    await backend.signIn();
    final container = await pumpApp(tester, backend, surfaceSize: _narrow);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'restaurant list');

    container
        .read(cartControllerProvider.notifier)
        .add(
          fixtureMenuItem(),
          restaurantId: 'rest_bella_napoli',
          restaurantName: 'Bella Napoli',
        );
    await tester.pump();

    for (final route in [
      '/menu/rest_bella_napoli',
      '/menu/rest_bella_napoli/item/item_margherita_pizza',
      '/cart',
      '/checkout',
      '/orders',
    ]) {
      await navTo(tester, route);
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow on $route');
    }

    // Tracking screen (polling): mount, render, then dispose cleanly.
    backend.orders.detail = fixtureOrderDetail();
    await navTo(tester, '/orders/order-1');
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'overflow on /orders/:id');
    await unmountApp(tester);
  });

  testWidgets('the welcome page and login form fit the narrowest width', (
    tester,
  ) async {
    final backend = TestBackend();
    // Signed-out landing page at phone width — must not overflow.
    await pumpApp(tester, backend, surfaceSize: _narrow);
    await tester.pump();
    expect(find.text('Great food, from kitchens near you.'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'overflow on /welcome');

    await navTo(tester, '/login');
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull, reason: 'overflow on /login');
  });
}
