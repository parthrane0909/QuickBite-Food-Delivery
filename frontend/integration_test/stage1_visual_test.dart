import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickbite/main.dart' as app;
import 'package:quickbite/core/storage/token_storage.dart';
import 'package:quickbite/ui/widgets/food_image.dart';

final _out = Directory('${Directory.systemTemp.path}/stage1screens');
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  String label = 'widget',
}) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  await snap(tester, 'diagnostic_failure');
  fail('Not found $label: $finder');
}

Future<void> snap(WidgetTester tester, String name) async {
  await tester.pump(const Duration(seconds: 2));
  final marker = File('${_out.path}/$name.request');
  await marker.writeAsString('capture');
  await tester.pump(const Duration(seconds: 5));
  await marker.delete();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  // Sliver/ListView children outside the viewport have not been built yet,
  // so waitFor alone cannot find dashboard actions farther down the page.
  if (finder.evaluate().isEmpty) {
    final scrollable = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.scrollUntilVisible(
      finder,
      280,
      scrollable: scrollable,
      maxScrolls: 16,
    );
  }
  await waitFor(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Stage 1 real API visual and navigation smoke; no checkout submission',
    (tester) async {
      _out.createSync(recursive: true);
      // Sign out the local test device; preserve its cart and all server data.
      await TokenStorage.platform().deleteToken();
      app.main();
      await waitFor(tester, find.textContaining('Welcome to'));
      await snap(tester, '01_welcome');
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Continue with email'),
      );
      await waitFor(tester, find.byType(TextFormField));
      await snap(tester, '02_login');
      await tester.enterText(
        find.byType(TextFormField).first,
        'alice@quickbite.dev',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'quickbite!alice1',
      );
      await snap(tester, '03_login_keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Sign In'));
      await waitFor(tester, find.text('Explore the kitchens'));
      await snap(tester, '04_discovery');
      // Search from the image-led top of the page before the CTA scrolls to
      // the restaurant grid (which moves the search field out of the sliver).
      await tester.enterText(find.byType(TextField).first, 'Bella Napoli');
      await tester.pump(const Duration(milliseconds: 500));
      await waitFor(tester, find.text('Bella Napoli'));
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Explore the kitchens'),
      );
      // The showcase catalogue is paginated by name and contains thousands
      // of records, so reach the protected fixture through real server search
      // instead of assuming it appears on page one.
      await waitFor(tester, find.text('Bella Napoli'));
      await snap(tester, '05_discovery_restaurants');
      await tapVisible(tester, find.text('Bella Napoli'));
      await waitFor(tester, find.text('Margherita Pizza'));
      await snap(tester, '06_menu');
      await tapVisible(tester, find.byType(FoodImage).first);
      await waitFor(tester, find.text('About this dish'));
      await snap(tester, '06b_dish_smoke');
      await tapVisible(tester, find.byTooltip('Back'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Add').first);
      await snap(tester, '07_menu_added');
      await tapVisible(tester, find.textContaining('View cart'));
      await waitFor(tester, find.text('Proceed to checkout'));
      await snap(tester, '08_cart_smoke');
      await tapVisible(tester, find.text('Proceed to checkout'));
      await waitFor(tester, find.text('Place order'));
      expect(find.byType(TextFormField), findsOneWidget);
      // Never tap Place order: this stage's tour must not write an order.
      await tapVisible(tester, find.byTooltip('Back'));
      await tapVisible(tester, find.byTooltip('Back'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
      await tester.pump(const Duration(seconds: 1));
      await waitFor(tester, find.text('On the menu'));
      await tapVisible(tester, find.byTooltip('Back'));
      await waitFor(tester, find.text('Account'));
      await tapVisible(tester, find.text('Orders'));
      await waitFor(tester, find.text('Order history'));
      await tapVisible(tester, find.text('Account'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Sign out'));
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Sign out').last,
      );
      await waitFor(tester, find.textContaining('Welcome to'));
      await snap(tester, '09_signed_out');

      // Read-only admin-tour for the extended management portal. No forms are
      // saved and no account, menu, or order data is mutated.
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Continue with email'),
      );
      await waitFor(tester, find.byType(TextFormField));
      await tester.enterText(
        find.byType(TextFormField).first,
        'admin@quickbite.dev',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'quickbite!admin1',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Sign In'));
      await waitFor(
        tester,
        find.text('Admin overview'),
        label: 'admin overview',
      );
      await snap(tester, '10_admin_dashboard');

      await tapVisible(tester, find.text('Restaurants & menus'));
      await waitFor(
        tester,
        find.text('Restaurants'),
        label: 'admin restaurants',
      );
      await snap(tester, '11_admin_restaurants');
      final restaurantSearch = find.byType(TextField).first;
      await tester.enterText(restaurantSearch, 'Bella Napoli');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await waitFor(
        tester,
        find.text('Bella Napoli'),
        label: 'admin restaurant search',
      );
      await tapVisible(tester, find.byTooltip('Manage menu'));
      await waitFor(tester, find.text('Menu management'), label: 'admin menu');
      await snap(tester, '12_admin_menu');

      await tapVisible(tester, find.byTooltip('Admin dashboard'));
      await waitFor(tester, find.text('Admin overview'));
      await tapVisible(tester, find.text('Customers'));
      await waitFor(tester, find.text('Customers'), label: 'admin customers');
      await snap(tester, '13_admin_customers');
      await tester.tap(find.byTooltip('View customer orders').first);
      await tester.pump(const Duration(milliseconds: 500));
      await waitFor(
        tester,
        find.textContaining('· Orders'),
        label: 'customer orders',
      );
      await snap(tester, '14_admin_customer_orders');

      // Close the read-only order inspection and return to the shell. An
      // administrator shops only under their own identity and can return to
      // management from the role-aware navigation bar.
      await tapVisible(tester, find.widgetWithText(TextButton, 'Close'));
      await tapVisible(tester, find.byTooltip('Admin dashboard'));
      await waitFor(tester, find.text('Admin overview'));
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Shop as customer'),
      );
      await waitFor(tester, find.text('Explore the kitchens'));
      await snap(tester, '15_admin_shopping_mode');
      await tapVisible(tester, find.text('Admin').last);
      await waitFor(tester, find.text('Admin overview'));
      await snap(tester, '16_return_to_admin');
      expect(tester.takeException(), isNull);
    },
  );
}
