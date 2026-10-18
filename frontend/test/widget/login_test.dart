/// Login screen widget tests (M5 §3): inline validation, distinct
/// invalid-credential vs timeout vs network messaging, success navigation
/// via the role redirect, session-expiry notice and sign-out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/core/network/api_exception.dart';
import 'package:quickbite/state/auth_controller.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

Future<void> _openLogin(WidgetTester tester, TestBackend backend) async {
  // The signed-out landing page is /welcome; login is an explicit step.
  await pumpApp(tester, backend, route: '/login');
  await settleAuth(tester);
  expect(
    find.byType(TextFormField),
    findsNWidgets(2),
    reason: 'email + password',
  );
}

Future<void> _submit(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), password);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await settleAuth(tester);
}

void main() {
  setUpAll(initTestLocale);
  setUp(resetPrefs);

  testWidgets('validates email and password before any network call', (
    tester,
  ) async {
    final backend = TestBackend();
    await _openLogin(tester, backend);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pump();

    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(backend.auth.loginCalls, 0, reason: 'no call on invalid form');
  });

  testWidgets('development demo buttons only prefill credentials', (
    tester,
  ) async {
    final backend = TestBackend();
    await _openLogin(tester, backend);

    final customerDemo = find.text('Customer demo');
    expect(customerDemo, findsOneWidget);
    await tester.tap(customerDemo);
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'alice@quickbite.dev',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      'quickbite!alice1',
    );
    expect(backend.auth.loginCalls, 0, reason: 'autofill never bypasses auth');
    await unmountApp(tester);
  });

  testWidgets('rejects a malformed email address', (tester) async {
    final backend = TestBackend();
    await _openLogin(tester, backend);

    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(backend.auth.loginCalls, 0);
  });

  testWidgets('shows the invalid-credentials message for INVALID_CREDENTIALS', (
    tester,
  ) async {
    final backend = TestBackend()
      ..auth.loginError = const ApiException(
        code: 'INVALID_CREDENTIALS',
        statusCode: 401,
        message: 'Invalid email or password',
      );
    await _openLogin(tester, backend);

    await _submit(
      tester,
      email: 'alice@quickbite.dev',
      password: 'wrong-password',
    );

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(backend.auth.loginCalls, 1);
    expect(
      find.byType(TextFormField),
      findsNWidgets(2),
      reason: 'still on login',
    );
  });

  testWidgets('distinguishes a timeout from other failures', (tester) async {
    final backend = TestBackend()
      ..auth.loginError = const ApiException(
        code: 'timeout',
        statusCode: null,
        message: 'No response within 15s',
      );
    await _openLogin(tester, backend);

    await _submit(
      tester,
      email: 'alice@quickbite.dev',
      password: 'quickbite!alice1',
    );

    expect(
      find.text('The server took too long to respond. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('distinguishes a network failure from other failures', (
    tester,
  ) async {
    final backend = TestBackend()
      ..auth.loginError = const ApiException(
        code: 'network_error',
        statusCode: null,
        message: 'Connection refused',
      );
    await _openLogin(tester, backend);

    await _submit(
      tester,
      email: 'alice@quickbite.dev',
      password: 'quickbite!alice1',
    );

    expect(
      find.text('Cannot reach the server. Check your connection.'),
      findsOneWidget,
    );
  });

  testWidgets('successful sign-in lands the customer on discovery', (
    tester,
  ) async {
    final backend = TestBackend();
    await _openLogin(tester, backend);

    await _submit(
      tester,
      email: 'alice@quickbite.dev',
      password: 'quickbite!alice1',
    );

    expect(backend.auth.loginCalls, 1);
    expect(
      find.text('Find your next favourite.'),
      findsOneWidget,
      reason: 'catalog home',
    );
  });

  testWidgets('a global 401 returns to login with the expiry notice', (
    tester,
  ) async {
    final backend = TestBackend();
    await backend.signIn();
    final container = await pumpApp(tester, backend);
    expect(
      find.text('Find your next favourite.'),
      findsOneWidget,
      reason: 'signed in',
    );

    container.read(authControllerProvider.notifier).handleUnauthorized();
    await tester.pump();
    await settleAuth(tester);

    expect(
      find.text('Your session expired. Please sign in again.'),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('sign out asks for confirmation and returns to welcome', (
    tester,
  ) async {
    final backend = TestBackend();
    await backend.signIn();
    await pumpApp(tester, backend);
    expect(find.text('Find your next favourite.'), findsOneWidget);

    // Sign out lives on the Account tab (new IA: Home / Orders / Account).
    await tester.tap(find.text('Account'));
    await tester.pump();
    await settleAuth(tester);

    final signOutButton = find.widgetWithText(FilledButton, 'Sign out');
    await tester.ensureVisible(signOutButton);
    await tester.pumpAndSettle();
    await tester.tap(signOutButton);
    await tester.pump();
    expect(find.text('Sign out?'), findsOneWidget);
    expect(
      find.text('You will need to sign in again to browse QuickBite.'),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Sign out'),
      ),
    );
    await tester.pump();
    await settleAuth(tester);

    // Signed-out landing page (welcome) — sign-in still one tap away.
    // (The pitch can extend below the fold on short viewports — scroll it up.)
    expect(find.textContaining('Welcome to'), findsOneWidget);
    final signInButton = find.widgetWithText(
      FilledButton,
      'Continue with email',
    );
    await tester.ensureVisible(signInButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(signInButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await settleAuth(tester);
    expect(
      find.byType(TextFormField),
      findsNWidgets(2),
      reason: 'login from welcome',
    );
    await unmountApp(tester);
  });
}
