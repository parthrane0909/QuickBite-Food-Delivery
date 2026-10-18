/// Milestone 5 evidence: a SCREENSHOT TOUR of the Android app on the real
/// emulator. Same stack as app_flow_test.dart, but it pauses at each screen
/// and saves a PNG of the device framebuffer.
///
/// Because `flutter test integration_test` runs INSIDE the app process, the
/// captures go through `binding.takeScreenshot()` (host-side screencap via the
/// test driver) and are written to the app's own cache dir
/// (`Directory.systemTemp` = `/data/user/0/<pkg>/cache/m5screens`). A fallback
/// drops a numbered `.request` marker and holds the screen still so a host
/// script may `adb exec-out screencap` instead. Either way the host pulls the
/// files afterwards (see scripts/pull_android_screens.sh).
///
/// Run (stack up, emulator booted, app data cleared):
///   adb shell pm clear dev.quickbite.quickbite
///   flutter test integration_test/screenshot_tour_test.dart -d emulator-5554
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickbite/main.dart' as app;

final _dir = Directory('${Directory.systemTemp.path}/m5screens');
int _shot = 0;

/// Signals a host-side screencap of the current device screen.
///
/// The test idles first so the surface finishes compositing the screen's
/// last change (entrance cascades, transitions): on the SwiftShader emulator,
/// `adb exec-out screencap` can otherwise read a stale or partially drawn
/// frame — that race produced blank list bodies and missing labels in early
/// evidence runs. It then holds the marker for 6 s while the host watcher
/// (`scripts/watch_android_screens.sh`) takes several frames and keeps the
/// freshest ones.
Future<void> _snap(WidgetTester tester, String name) async {
  _shot += 1;
  final prefix = _shot.toString().padLeft(2, '0');
  await tester.pump(const Duration(milliseconds: 1200));
  final marker = File('${_dir.path}/${prefix}_$name.request');
  await marker.writeAsString('screencap');
  await tester.pump(const Duration(milliseconds: 6000));
  await marker.delete();
  debugPrint('captured ${prefix}_$name.png (host screencap marker)');
}

/// Bounded wait (never pumpAndSettle — tracking schedules polling frames).
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String label = 'widget',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  if (finder.evaluate().isEmpty) {
    fail('Timed out after ${timeout.inSeconds}s waiting for $label');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('screenshot tour: customer journey + admin overview', (
    tester,
  ) async {
    _dir.createSync(recursive: true);
    app.main();

    // ---- Welcome + login --------------------------------------------------
    await _waitFor(
      tester,
      find.text('Great food, from kitchens near you.'),
      label: 'welcome screen',
    );
    await _snap(tester, 'welcome');
    final welcomeSignIn = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(welcomeSignIn);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(welcomeSignIn);

    await _waitFor(tester, find.text('Sign In'), label: 'login screen');
    await _snap(tester, 'login');

    await tester.enterText(
      find.byType(TextFormField).first,
      'alice@quickbite.dev',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'quickbite!alice1',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));

    // ---- Catalog ---------------------------------------------------------
    await _waitFor(tester, find.text('Bella Napoli'), label: 'restaurant list');
    await _snap(tester, 'restaurant_list');

    await tester.tap(find.text('Bella Napoli'));

    // ---- Menu + item detail -----------------------------------------------
    await _waitFor(tester, find.text('Add'), label: 'menu items');
    await _snap(tester, 'menu');

    // The first menu row opens the NEW item detail screen.
    final firstItemRow = find.text('Margherita Pizza').first;
    await tester.ensureVisible(firstItemRow);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(firstItemRow);
    await _waitFor(tester, find.text('Add to cart'), label: 'item detail');
    await tester.pump(const Duration(milliseconds: 600));
    await _snap(tester, 'item_detail');

    await tester.tap(find.widgetWithText(FilledButton, 'Add to cart'));
    await _waitFor(
      tester,
      find.text('Added to cart'),
      label: 'add-to-cart confirmation',
    );
    await _snap(tester, 'item_detail_added');

    // Back to the menu — the floating cart bar now shows the line.
    await tester.tap(find.byTooltip('Back'));
    await _waitFor(
      tester,
      find.textContaining('View cart'),
      label: 'floating cart bar',
    );
    await _snap(tester, 'menu_item_added');

    // ---- Cart -------------------------------------------------------------
    await tester.tap(find.textContaining('View cart'));
    await _waitFor(
      tester,
      find.text('Proceed to checkout'),
      label: 'cart screen',
    );
    await _snap(tester, 'cart');

    // ---- Checkout ---------------------------------------------------------
    await tester.tap(find.text('Proceed to checkout'));
    await _waitFor(tester, find.text('Place order'), label: 'checkout');
    await _snap(tester, 'checkout');

    await tester.enterText(
      find.byType(TextFormField).first,
      '12 Lake Road, Bengaluru',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _snap(tester, 'checkout_filled');

    await tester.tap(find.widgetWithText(FilledButton, 'Place order'));

    // ---- Acceptance (202) -------------------------------------------------
    await _waitFor(
      tester,
      find.text('Order accepted!'),
      label: 'acceptance',
      timeout: const Duration(seconds: 30),
    );
    await _snap(tester, 'order_accepted');

    // ---- Live tracking (early state, then terminal) -----------------------
    await tester.tap(find.widgetWithText(FilledButton, 'Track this order'));
    await _waitFor(
      tester,
      find.text('Order details'),
      label: 'tracking screen',
    );
    await tester.pump(const Duration(seconds: 2));
    await _snap(tester, 'tracking_early');

    await _waitFor(
      tester,
      find.text('Driver assigned'),
      label: 'terminal status',
      timeout: const Duration(seconds: 90),
    );
    await _snap(tester, 'tracking_terminal');

    // Notifications sit at the bottom of the scroll view.
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 10; i++) {
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 150));
    }
    await _snap(tester, 'tracking_notifications');

    // ---- Order history (back button exits tracking) -----------------------
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 500));
    if (find.text('Order history').evaluate().isEmpty &&
        find.text('View order history').evaluate().isNotEmpty) {
      await tester.tap(find.text('View order history'));
    }
    await _waitFor(tester, find.text('Order history'), label: 'order history');
    // Wait for the first page to actually land (the fetch can take a second
    // under load) so the shot shows cards, not the data-arrival frame with
    // entrance fades still at zero.
    await _waitFor(
      tester,
      find.textContaining('Order order_'),
      label: 'order cards',
      timeout: const Duration(seconds: 15),
    );
    // Let the entrance cascade settle before the snap.
    await tester.pump(const Duration(milliseconds: 900));
    await _snap(tester, 'order_history');

    // ---- Account tab, sign out, then admin overview -----------------------
    final accountTab = find.text('Account');
    await tester.ensureVisible(accountTab);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(accountTab);
    await _waitFor(tester, find.text('Customer'), label: 'account screen');
    await _snap(tester, 'account');

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await _waitFor(tester, find.text('Sign out?'), label: 'sign-out dialog');
    await _snap(tester, 'sign_out_dialog');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Sign out'),
      ),
    );
    await _waitFor(
      tester,
      find.text('Great food, from kitchens near you.'),
      label: 'welcome after sign-out',
    );
    // Let the fade transition fully settle so the landing is captured clean.
    await tester.pump(const Duration(milliseconds: 800));
    await _snap(tester, 'welcome_after_signout');

    final adminSignIn = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(adminSignIn);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(adminSignIn);
    await _waitFor(tester, find.text('Sign In'), label: 'login for admin');

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
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));

    await _waitFor(
      tester,
      find.text('Admin overview'),
      label: 'admin dashboard',
    );
    await tester.pump(const Duration(seconds: 2));
    await _snap(tester, 'admin_overview');

    // Cross-customer status filter (target the chip, not the summary card).
    final confirmedChip = find.widgetWithText(ChoiceChip, 'Confirmed');
    await tester.ensureVisible(confirmedChip);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(confirmedChip);
    await tester.pump(const Duration(seconds: 1));
    await _snap(tester, 'admin_filter_confirmed');

    debugPrint('screenshot tour complete: $_shot captures in ${_dir.path}');
  });
}
