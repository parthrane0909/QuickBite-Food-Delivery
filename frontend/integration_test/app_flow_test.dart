/// End-to-end customer flow on a REAL device/emulator against the live
/// Compose stack (assignment §14 "Frontend" row: sign-in -> menu ->
/// checkout -> tracking -> history). No fakes: the app talks to the seeded
/// backend over http://10.0.2.2:8000/api/v1 (the emulator's view of the
/// host loopback), the real payment/restaurant/delivery/notification
/// workers drive the order, and the UI polls tracking until the terminal
/// state.
///
/// Run (stack up, emulator booted, app data cleared for a cold start):
///   adb shell pm clear dev.quickbite.quickbite
///   flutter test integration_test/app_flow_test.dart -d emulator-5554
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickbite/main.dart' as app;

/// Anchored match for the raw order id (`order_...`) as rendered by the ack
/// screen's "Order ID" row and the history card — excludes prose that merely
/// mentions the id inside a sentence.
final _orderIdPattern = RegExp(r'^order_[0-9a-zA-Z_-]+$');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer journey: sign in, browse menu, checkout, watch live tracking, '
      'see history and notifications', (tester) async {
    app.main();

    // ---- 1. Sign in (real auth against the seeded demo account) ----------
    // Signed-out visitors land on the welcome page first (UI rehaul);
    // "Continue with email" leads to the login form.
    await _waitFor(
      tester,
      find.textContaining('Great food, from kitchens near you.'),
      label: 'welcome screen',
    );
    final welcomeSignIn = find.widgetWithText(FilledButton, 'Continue with email');
    await _scrollIntoView(tester, welcomeSignIn);
    await tester.tap(welcomeSignIn);

    await _waitFor(tester, find.text('Sign In'), label: 'login screen');
    await tester.enterText(
      find.byType(TextFormField).first,
      'alice@quickbite.dev',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'quickbite!alice1',
    );
    // Dismiss the IME so the submit button is hittable.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));

    // ---- 2. Browse the seeded catalog ------------------------------------
    // Sorted by name: Bella Napoli is the first card.
    await _waitFor(tester, find.text('Bella Napoli'), label: 'restaurant list');
    await tester.tap(find.text('Bella Napoli'));

    // ---- 3. Open the menu, add the first available item -------------------
    await _waitFor(tester, find.text('Add'), label: 'menu items');
    final addButtons = find.widgetWithText(FilledButton, 'Add');
    await _scrollIntoView(tester, addButtons.first);
    await tester.tap(addButtons.first);
    await _waitFor(
      tester,
      find.textContaining('View cart'),
      label: 'floating cart bar',
    );

    // ---- 4. Cart -> checkout -> place the order ---------------------------
    await tester.tap(find.textContaining('View cart'));
    await _waitFor(
      tester,
      find.text('Proceed to checkout'),
      label: 'cart screen',
    );
    await _scrollIntoView(tester, find.text('Proceed to checkout'));
    await tester.tap(find.text('Proceed to checkout'));

    await _waitFor(tester, find.text('Place order'), label: 'checkout form');
    await tester.enterText(
      find.byType(TextFormField).first,
      '12 Lake Road, Bengaluru',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _scrollIntoView(
      tester,
      find.widgetWithText(FilledButton, 'Place order'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Place order'));

    // ---- 5. 202 acceptance (NOT a paid/delivered claim) -------------------
    await _waitFor(
      tester,
      find.text('Order accepted!'),
      label: 'order acceptance',
      timeout: const Duration(seconds: 30),
    );

    // Capture the authoritative order id straight from the server response.
    // The ack row renders it with SelectableText (EditableText underneath),
    // so read the plain text from whichever widget type matched.
    final idFinder = find.textContaining(_orderIdPattern);
    await _waitFor(tester, idFinder, label: 'order id');
    final idWidget = idFinder.first.evaluate().first.widget;
    final orderId =
        (idWidget is EditableText
                ? idWidget.controller.text
                : (idWidget as Text).data)!
            .trim();
    expect(orderId, startsWith('order_'));
    expect(
      find.text('Accepted total'),
      findsOneWidget,
      reason: 'server-authoritative total is shown, no invented fees',
    );

    // ---- 6. Watch the asynchronous pipeline until the terminal state ------
    await tester.tap(find.widgetWithText(FilledButton, 'Track this order'));
    await _waitFor(
      tester,
      find.text('Order details'),
      label: 'tracking screen',
    );

    // The real workers drive PENDING -> ... -> DRIVER_ASSIGNED (terminal);
    // the status card is the first card, so no scrolling is needed here.
    await _waitFor(
      tester,
      find.text('Driver assigned'),
      label: 'terminal status',
      timeout: const Duration(seconds: 90),
    );
    expect(
      find.textContaining('final state'),
      findsWidgets,
      reason: 'terminal banner explains polling has stopped',
    );

    // Per-order notifications sit at the bottom of the scroll view, below
    // the (now stable) status/timeline/details cards.
    await _scrollToBottom(tester);
    await _waitFor(
      tester,
      find.textContaining('received —'),
      label: 'persisted notification',
      timeout: const Duration(seconds: 30),
    );

    // ---- 7. Back out to the order history; the order must be listed --------
    await tester.tap(find.byTooltip('Back'));
    // One frame for navigation to render, then see where we landed: the
    // tracking route falls back to the history shell (canPop is false after
    // a `go()`), but a pushed stack would pop to the acceptance screen.
    await tester.pump(const Duration(milliseconds: 500));
    if (find.text('Order history').evaluate().isEmpty &&
        find.text('View order history').evaluate().isNotEmpty) {
      await tester.tap(find.text('View order history'));
    }
    await _waitFor(tester, find.text('Order history'), label: 'order history');
    await _waitFor(
      tester,
      find.text('Order $orderId'),
      label: 'order in history',
      timeout: const Duration(seconds: 30),
    );
  });
}

/// Bounded wait: pumps short frames until [finder] matches. Never uses
/// pumpAndSettle — the tracking screen schedules polling frames on a timer.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String label = 'widget',
}) async {
  final deadline = DateTime.now().add(timeout);
  // Pump first, then evaluate: the finder and any subsequent widget reads
  // then observe the exact same frame (no tree change in between).
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  if (finder.evaluate().isEmpty) {
    fail('Timed out after ${timeout.inSeconds}s waiting for $label');
  }
}

/// Brings [finder] into the viewport (no-op when already visible; the
/// widget must already be built by a preceding wait).
Future<void> _scrollIntoView(WidgetTester tester, Finder finder) async {
  final element = finder.evaluate().first;
  await Scrollable.ensureVisible(element, alignment: 0.2);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Drags the screen's single scrollable to its end (the notifications feed
/// lives below the status/timeline/details cards).
Future<void> _scrollToBottom(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 200));
  }
}
