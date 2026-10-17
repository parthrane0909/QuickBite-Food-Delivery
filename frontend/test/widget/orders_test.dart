/// Orders widget tests (M5 §3): 202 acknowledgement fallback, live order
/// tracking (2s polling while visible, terminal-state stop, error backoff),
/// per-order notifications, failure presentation and the paginated/filtered
/// order history. No polling test ends without unmounting the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/core/network/api_exception.dart';
import 'package:quickbite/domain/order_status.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

void main() {
  setUpAll(initTestLocale);
  setUp(resetPrefs);

  group('Acknowledgement', () {
    testWidgets('deep-linked ack without acceptance state forwards to tracking',
        (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      backend.orders.detail = fixtureOrderDetail();

      await pumpApp(tester, backend, route: '/orders/order-1/accepted');
      await tester.pump();
      await tester.pump();

      // The acceptance payload is in-memory only (never persisted): the
      // screen hands off to the live tracking view.
      expect(find.text('Order accepted!'), findsNothing);
      expect(find.text('Order details'), findsOneWidget);
      await unmountApp(tester);
    });
  });

  group('Live tracking', () {
    testWidgets('polls every 2 seconds and stops at the terminal state',
        (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      backend.orders.detail = fixtureOrderDetail(status: OrderStatus.pending);
      backend.orders.historyEntries = [fixtureHistoryEntry()];
      backend.orders.notificationEntries = [fixtureNotification()];

      await pumpApp(
        tester,
        backend,
        route: '/orders/order-1',
        surfaceSize: const Size(600, 1600), // reveal the whole scroll view
      );
      await tester.pump();
      await tester.pump();

      expect(backend.orders.orderCalls, 1, reason: 'initial authoritative load');
      expect(find.text('Pending'), findsWidgets);
      expect(
        find.textContaining('Polling every 2s'),
        findsOneWidget,
        reason: 'the polling cadence is disclosed to the user',
      );

      // First scheduled tick at +2s.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(backend.orders.orderCalls, 2);

      // Server advances to the successful terminal state.
      backend.orders.detail =
          fixtureOrderDetail(status: OrderStatus.driverAssigned);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(backend.orders.orderCalls, 3);
      expect(find.text('Driver assigned'), findsWidgets);
      expect(
        find.textContaining('A driver has been assigned'),
        findsOneWidget,
        reason: '202/DRIVER_ASSIGNED is the assignment success end-state',
      );

      // Terminal: polling stops — no further requests.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(backend.orders.orderCalls, 3, reason: 'no polls after terminal');
      await unmountApp(tester);
    });

    testWidgets('polling backs off exponentially while errors persist',
        (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      backend.orders.detail = fixtureOrderDetail(status: OrderStatus.pending);

      await pumpApp(tester, backend, route: '/orders/order-1');
      await tester.pump();
      await tester.pump();
      expect(backend.orders.orderCalls, 1);

      backend.orders.orderError = const ApiException(
        code: 'network_error',
        statusCode: null,
        message: 'Connection lost',
      );

      // Tick 1 at +2s fails: 1 consecutive error => next delay 4s.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(backend.orders.orderCalls, 2);

      // +2s later: only halfway through the backed-off interval.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(backend.orders.orderCalls, 2, reason: 'backoff defers the retry');

      // +4s after the failure the next tick fires.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(backend.orders.orderCalls, 3);
      await unmountApp(tester);
    });

    testWidgets('a failed order surfaces the server failure reason',
        (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      backend.orders.detail = fixtureOrderDetail(
        status: OrderStatus.paymentFailed,
        failureReason: 'Your card was declined.',
        failureCode: 'PAYMENT_REJECTED',
      );
      backend.orders.historyEntries = [
        fixtureHistoryEntry(
          version: 2,
          status: OrderStatus.paymentFailed,
          fromStatus: OrderStatus.pending,
        ),
      ];

      await pumpApp(tester, backend, route: '/orders/order-1');
      await tester.pump();
      await tester.pump();

      expect(find.text('Payment failed'), findsWidgets);
      expect(
        find.text('Your card was declined.'),
        findsWidgets,
        reason: 'banner + details card both surface the server reason',
      );

      // The poll timer is scheduled at mount, so exactly one tick can fire
      // before the terminal state is observed — after that, polling stops.
      final callsBeforeStop = backend.orders.orderCalls;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(
        backend.orders.orderCalls,
        callsBeforeStop + 1,
        reason: 'the in-flight scheduled tick fires once',
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(backend.orders.orderCalls, callsBeforeStop + 1,
          reason: 'terminal stops polling');
      await unmountApp(tester);
    });

    testWidgets('manual refresh re-fetches immediately', (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      backend.orders.detail = fixtureOrderDetail(status: OrderStatus.pending);

      await pumpApp(tester, backend, route: '/orders/order-1');
      await tester.pump();
      await tester.pump();
      expect(backend.orders.orderCalls, 1);

      await tester.tap(find.byTooltip('Refresh now'));
      await tester.pump();
      await tester.pump();
      expect(backend.orders.orderCalls, 2);
      await unmountApp(tester);
    });

    testWidgets('per-order notifications are shown', (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      backend.orders.detail = fixtureOrderDetail(status: OrderStatus.pending);
      backend.orders.notificationEntries = [
        fixtureNotification(seq: 1),
        fixtureNotification(seq: 2, type: 'payment.failed'),
      ];

      await pumpApp(tester, backend, route: '/orders/order-1');
      await tester.pump();
      await tester.pump();

      expect(find.text('Notifications'), findsOneWidget);
      expect(
        find.text('Your order was created and is queued for processing.'),
        findsWidgets,
      );
      expect(backend.orders.notificationCalls, greaterThanOrEqualTo(1));
      await unmountApp(tester);
    });
  });

  group('Order history', () {
    testWidgets('lists the customer orders and applies the status filter',
        (tester) async {
      final backend = TestBackend()
        ..orders.orderList = [
          fixtureOrderSummary(id: 'order-1', status: OrderStatus.pending),
          fixtureOrderSummary(
            id: 'order-2',
            status: OrderStatus.confirmed,
            restaurantName: 'Roma Trattoria',
          ),
        ];
      await backend.signIn();
      await pumpApp(tester, backend, route: '/orders');
      await tester.pump();
      await tester.pump();

      expect(find.text('Order history'), findsOneWidget);
      expect(find.text('Bella Napoli'), findsOneWidget);
      expect(find.text('Roma Trattoria'), findsOneWidget);
      expect(backend.orders.orderStatusFilters.first, isNull);

      // Server-side filter: only where the contract supports it.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Confirmed'));
      await tester.pump();
      await tester.pump();

      expect(backend.orders.orderStatusFilters, contains('CONFIRMED'));
      expect(find.text('Roma Trattoria'), findsOneWidget);
      expect(find.text('Bella Napoli'), findsNothing);
    });

    testWidgets('shows the empty state when no orders were placed',
        (tester) async {
      final backend = TestBackend();
      await backend.signIn();
      await pumpApp(tester, backend, route: '/orders');
      await tester.pump();
      await tester.pump();

      expect(find.text('No orders yet'), findsOneWidget);
    });

    testWidgets('shows a filter-specific empty state', (tester) async {
      final backend = TestBackend()
        ..orders.orderList = [
          fixtureOrderSummary(id: 'order-1', status: OrderStatus.pending),
        ];
      await backend.signIn();
      await pumpApp(tester, backend, route: '/orders');
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(ChoiceChip, 'Confirmed'));
      await tester.pump();
      await tester.pump();

      expect(find.text('No confirmed orders'), findsOneWidget);
    });
  });
}
