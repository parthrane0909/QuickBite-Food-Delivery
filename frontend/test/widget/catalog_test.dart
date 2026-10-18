/// Catalog widget tests (M5 §3): restaurant list + menu — loading, empty,
/// error-with-retry, real item rendering, unavailable items and the
/// single-restaurant cart conflict dialog. No category filter exists in the
/// backend, so none is exercised here.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/core/network/api_exception.dart';
import 'package:quickbite/state/cart_controller.dart';
import 'package:quickbite/ui/motion/shimmer.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

void main() {
  setUpAll(initTestLocale);
  setUp(resetPrefs);

  group('Restaurant list', () {
    testWidgets('shows the loading state until the page arrives', (
      tester,
    ) async {
      final backend = TestBackend();
      final gate = Completer<void>();
      backend.catalog.restaurantsGate = gate;
      await backend.signIn();
      await pumpApp(tester, backend);

      expect(
        find.byType(SkeletonRestaurantCard),
        findsWidgets,
        reason: 'shimmer skeleton until the page arrives',
      );

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Bella Napoli'), findsOneWidget);
    });

    testWidgets('renders the seeded restaurants', (tester) async {
      final backend = TestBackend(
        catalog: FakeCatalogRepository(
          restaurantList: [
            fixtureRestaurant(),
            fixtureRestaurant(id: 'rest_roma', name: 'Roma Trattoria'),
          ],
        ),
      );
      await backend.signIn();
      await pumpApp(tester, backend);
      await tester.pump();

      expect(find.text('Bella Napoli'), findsOneWidget);
      expect(find.text('Roma Trattoria'), findsOneWidget);
    });

    testWidgets('shows the empty state when no restaurants are seeded', (
      tester,
    ) async {
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

      expect(
        find.byType(SkeletonListTile),
        findsWidgets,
        reason: 'shimmer row skeletons until the menu arrives',
      );

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Margherita Pizza'), findsOneWidget);
    });

    testWidgets('unavailable items are visible but not purchasable', (
      tester,
    ) async {
      final backend = TestBackend(
        catalog: FakeCatalogRepository(
          menuItemList: [
            fixtureMenuItem(),
            fixtureMenuItem(
              id: 'item_tiramisu',
              name: 'Tiramisu',
              isAvailable: false,
            ),
          ],
        ),
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

    testWidgets('shows the empty state when the menu has no items', (
      tester,
    ) async {
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

    testWidgets('adding shows the cart bar and updating quantity updates it', (
      tester,
    ) async {
      final backend = TestBackend();
      await backend.signIn();
      await pumpApp(tester, backend, route: '/menu/rest_bella_napoli');
      await tester.pump();

      // Image-led menu page: the first tile may sit below the fold, and once
      // the floating cart bar appears the body shrinks again — scroll each
      // control into the viewport before tapping (as a user would).
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      expect(find.textContaining('View cart'), findsOneWidget);
      expect(find.textContaining('1 item'), findsOneWidget);

      await tester.ensureVisible(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(find.textContaining('2 items'), findsOneWidget);
    });

    testWidgets('a cart from another restaurant prompts before replacing', (
      tester,
    ) async {
      final backend = TestBackend();
      await backend.signIn();
      final container = await pumpApp(tester, backend);
      // Seed a cart that belongs to a DIFFERENT restaurant.
      container
          .read(cartControllerProvider.notifier)
          .add(
            fixtureMenuItem(id: 'item_x', restaurantId: 'rest_other'),
            restaurantId: 'rest_other',
            restaurantName: 'Other Place',
          );
      await tester.pump();

      await navTo(tester, '/menu/rest_bella_napoli');
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Add'));
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

  group('Item detail', () {
    testWidgets('shows the item and adds the selected quantity to the cart', (
      tester,
    ) async {
      final backend = TestBackend();
      await backend.signIn();
      final container = await pumpApp(tester, backend);
      await navTo(tester, '/menu/rest_bella_napoli/item/item_margherita_pizza');
      await tester.pump();

      // Full detail rendering: hero + name + price + description + add bar.
      expect(find.text('Margherita Pizza'), findsOneWidget);
      expect(
        find.text('San Marzano tomato, mozzarella, basil'),
        findsOneWidget,
      );
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add to cart'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the add bar must not starve the body of height',
      );

      // The stepper adjusts the live line total, then adds that quantity.
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add to cart'));
      await tester.pump(const Duration(milliseconds: 400));

      final cart = container.read(cartControllerProvider);
      expect(cart.lines.single.menuItemId, 'item_margherita_pizza');
      expect(cart.lines.single.quantity, 2);
      expect(find.text('Added to cart'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountApp(tester);
    });

    testWidgets('an unknown item shows the not-found state', (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      await pumpApp(tester, backend);
      await navTo(tester, '/menu/rest_bella_napoli/item/item_missing');
      await tester.pump();
      await tester.pump();

      expect(find.text('Item not found'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      await unmountApp(tester);
    });
  });
}
