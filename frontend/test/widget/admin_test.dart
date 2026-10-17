/// Admin dashboard widget tests (M5 §5): role-aware routing (admins land
/// on /admin, customers are blocked, admins are kept out of customer
/// surfaces), read-only summary counts straight from the server, the
/// cross-customer order list with its status filter, and error states.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/core/network/api_exception.dart';
import 'package:quickbite/domain/order_status.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

/// The dashboard scrolls; its orders section sits below the summary cards, so
/// the tests that assert on cross-customer orders need a tall viewport.
const _tallSurface = Size(700, 1600);

void main() {
  setUpAll(initTestLocale);
  setUp(resetPrefs);

  testWidgets('an admin lands on the overview with server summary counts',
      (tester) async {
    final backend = TestBackend()
      ..admin.orderItems = [
        fixtureAdminOrderItem(customerEmail: 'alice@quickbite.dev'),
        fixtureAdminOrderItem(
          id: 'order-2',
          status: OrderStatus.paid,
          customerEmail: 'bob@quickbite.dev',
        ),
      ];
    await backend.signIn(role: 'admin');
    await pumpApp(tester, backend, surfaceSize: _tallSurface);
    await tester.pump();
    await tester.pump();

    expect(find.text('Admin overview'), findsOneWidget);
    expect(find.text('Orders (all customers)'), findsOneWidget);

    // Summary: every count is server-provided, zeros included.
    expect(find.text('Pending outbox events'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Retry backlog'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('Quarantine records'), findsOneWidget);
    expect(find.text('Driver assigned'), findsWidgets, reason: 'status stat card');
    expect(
      find.textContaining('read-only'),
      findsOneWidget,
      reason: 'the dashboard states it never mutates state',
    );

    // Cross-customer order cards show the ordering customer's email.
    expect(find.text('alice@quickbite.dev'), findsOneWidget);
    expect(find.text('bob@quickbite.dev'), findsOneWidget);
  });

  testWidgets('the admin status filter queries the server with apiValue',
      (tester) async {
    final backend = TestBackend()
      ..admin.orderItems = [
        fixtureAdminOrderItem(customerEmail: 'alice@quickbite.dev'),
        fixtureAdminOrderItem(
          id: 'order-2',
          status: OrderStatus.paid,
          customerEmail: 'bob@quickbite.dev',
        ),
      ];
    await backend.signIn(role: 'admin');
    await pumpApp(tester, backend, surfaceSize: _tallSurface);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Paid'));
    await tester.pump();
    await tester.pump();

    expect(backend.admin.statusFilters, contains('PAID'));
    expect(find.text('bob@quickbite.dev'), findsOneWidget);
    expect(find.text('alice@quickbite.dev'), findsNothing);
  });

  testWidgets('admin orders show a filter-specific empty state', (tester) async {
    final backend = TestBackend()
      ..admin.orderItems = [
        fixtureAdminOrderItem(customerEmail: 'alice@quickbite.dev'),
      ];
    await backend.signIn(role: 'admin');
    await pumpApp(tester, backend, surfaceSize: _tallSurface);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Confirmed'));
    await tester.pump();
    await tester.pump();

    expect(find.text('No orders match'), findsOneWidget);
    expect(find.text('No orders with status Confirmed.'), findsOneWidget);
  });

  testWidgets('a 403 on admin data surfaces an error state with retry',
      (tester) async {
    final backend = TestBackend()
      ..admin.ordersError = const ApiException(
        code: 'FORBIDDEN',
        statusCode: 403,
        message: 'Admin access required',
      );
    await backend.signIn(role: 'admin');
    await pumpApp(tester, backend, surfaceSize: _tallSurface);
    await tester.pump();
    await tester.pump();

    expect(find.text('Something went wrong'), findsWidgets);
    expect(find.text('Admin access required'), findsOneWidget);

    // Retry recovers once the server allows it again.
    backend.admin.ordersError = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('Something went wrong'), findsNothing);
  });

  testWidgets('a customer is redirected away from /admin', (tester) async {
    final backend = TestBackend();
    await backend.signIn(); // customer
    await pumpApp(tester, backend, route: '/admin');
    await tester.pump();

    expect(find.text('Admin overview'), findsNothing);
    expect(find.text('Bella Napoli'), findsOneWidget, reason: 'catalog home');
  });

  testWidgets('an admin is redirected away from customer surfaces',
      (tester) async {
    final backend = TestBackend();
    await backend.signIn(role: 'admin');

    await pumpApp(tester, backend, route: '/orders');
    await tester.pump();
    expect(find.text('Order history'), findsNothing);
    expect(find.text('Admin overview'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    resetPrefs();
    await pumpApp(tester, backend, route: '/cart');
    await tester.pump();
    expect(find.text('My Cart'), findsNothing);
    expect(find.text('Admin overview'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('tapping an admin order card opens the shared tracking view',
      (tester) async {
    final backend = TestBackend()
      ..admin.orderItems = [
        fixtureAdminOrderItem(id: 'order-1', customerEmail: 'alice@quickbite.dev'),
      ]
      ..orders.detail = fixtureOrderDetail(id: 'order-1');
    await backend.signIn(role: 'admin');
    await pumpApp(tester, backend, surfaceSize: _tallSurface);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('alice@quickbite.dev'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Order details'), findsOneWidget);
    await unmountApp(tester);
  });
}
