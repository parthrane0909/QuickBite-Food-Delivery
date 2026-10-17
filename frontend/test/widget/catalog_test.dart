/// Catalog widget tests (M5 §3): restaurant list + menu — loading, empty,
/// error-with-retry, real item rendering, unavailable items and the
/// single-restaurant cart conflict dialog. No category filter exists in the
/// backend, so none is exercised here.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/app/router.dart';
import 'package:quickbite/core/network/api_exception.dart';
import 'package:quickbite/state/cart_controller.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

void main() {
  setUpAll(initTestLocale);
  setUp(resetPrefs);

  group('Restaurant list', () {
    testWidgets('shows the loading state until the page arrives', (tester) async {
      final backend = TestBackend();
      final gate = Completer<void>();
      backend.catalog.restaurantsGate = gate;
      await backend.signIn();
      await pumpApp(tester, backend);

      expect(find.text('Loading restaurants…'), findsOneWidget);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Bella Napoli'), findsOneWidget);
    });

    testWidgets('renders the seeded restaurants', (tester) async {
      final backend = TestBackend(
        catalog: FakeCatalogRepository(restaurantList: [
          fixtureRestaurant(),
          fixtureRestaurant(id: 'rest_roma', name: 'Roma Trattoria'),
        ]),
      );
      await backend.signIn();
      await pumpApp(tester, backend);
      await tester.pump();

      expect(find.text('Bella Napoli'), findsOneWidget);
      expect(find.text('Roma Trattoria'), findsOneWidget);
    });

    testWidgets('shows the empty state when no restaurants are seeded',
        (tester) async {
      final backend = TestBackend(
        catalog: FakeCatalogRepository(restaurantList: const []),
      );
      await backend.signIn();
      await pumpApp(tester, backend);
      await tester.pump();

      expect(find.text('No restaurants yet'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('shows an error state whose retry recovers', (tester) async {
      final backend = TestBackend()
        ..catalog.restaurantsError = const ApiException(
          code: 'internal',
          statusCode: 500,
          message: 'Database hiccup',
        );
      await backend.signIn();
      await pumpApp(tester, backend);
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Database hiccup'), findsOneWidget);

      backend.catalog.restaurantsError = null;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Bella Napoli'), findsOneWidget);
    });

    testWidgets('tapping a restaurant opens its menu', (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      await pumpApp(tester, backend);
      await tester.pump();

      await tester.tap(find.text('Bella Napoli'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Margherita Pizza'), findsOneWidget);
      expect(find.text('₹350.00'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
    });
  });

  group('Restaurant menu', () {
    testWidgets('shows the menu loading state', (tester) async {
      final backend = TestBackend();
      final gate = Completer<void>();
      backend.catalog.menuGate = gate;
      await backend.signIn();
      await pumpApp(tester, backend, route: '/menu/rest_bella_napoli');
      await tester.pump();

      expect(find.text('Loading menu…'), findsOneWidget);

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Margherita Pizza'), findsOneWidget);
    });

    testWidgets('unavailable items are visible but not purchasable',
        (tester) async {
      final backend = TestBackend(
        catalog: FakeCatalogRepository(menuItemList: [
          fixtureMenuItem(),
          fixtureMenuItem(
            id: 'item_tiramisu',
            name: 'Tiramisu',
            isAvailable: false,
          ),
        ]),
      );
      await backend.signIn();
      await pumpApp(tester, backend, route: '/menu/rest_bella_napoli');
      await tester.pump();

      expect(find.text('Margherita Pizza'), findsOneWidget);
      expect(find.text('Tiramisu'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Add'),
        findsOneWidget,
        reason: 'only the available item can be added',
      );
    });

    testWidgets('shows the empty state when the menu has no items',
        (tester) async {
      final backend = TestBackend(
        catalog: FakeCatalogRepository(menuItemList: const []),
      );
      await backend.signIn();
      await pumpApp(tester, backend, route: '/menu/rest_bella_napoli');
      await tester.pump();

      expect(find.text('No menu items yet'), findsOneWidget);
    });

    testWidgets('menu error state retries successfully', (tester) async {
      final backend = TestBackend()
        ..catalog.menuError = const ApiException(
          code: 'internal',
          statusCode: 500,
          message: 'Menu service down',
        );
      await backend.signIn();
      await pumpApp(tester, backend, route: '/menu/rest_bella_napoli');
      await tester.pump();

      expect(find.text('Menu service down'), findsOneWidget);

      backend.catalog.menuError = null;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Margherita Pizza'), findsOneWidget);
    });

    testWidgets('adding shows the cart bar and updating quantity updates it',
        (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      await pumpApp(tester, backend, route: '/menu/rest_bella_napoli');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      expect(find.textContaining('View cart'), findsOneWidget);
      expect(find.textContaining('1 item'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(find.textContaining('2 items'), findsOneWidget);
    });

    testWidgets('a cart from another restaurant prompts before replacing',
        (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      final container = await pumpApp(tester, backend);
      // Seed a cart that belongs to a DIFFERENT restaurant.
      container.read(cartControllerProvider.notifier).add(
            fixtureMenuItem(id: 'item_x', restaurantId: 'rest_other'),
            restaurantId: 'rest_other',
            restaurantName: 'Other Place',
          );
      await tester.pump();

      container.read(appRouterProvider).go('/menu/rest_bella_napoli');
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      expect(find.text('Start a new cart?'), findsOneWidget);
      expect(
        find.textContaining('Your cart has items from Other Place'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Clear & add'));
      await tester.pump();

      final cart = container.read(cartControllerProvider);
      expect(cart.restaurantId, 'rest_bella_napoli');
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.name, 'Margherita Pizza');
    });
  });
}
