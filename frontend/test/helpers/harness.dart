/// Widget-test harness: pumps the REAL app (router, theme, controllers)
/// over faked repositories — presentation + state layers under test, data
/// layer faked at its interface boundary (integration tests cover the real
/// HTTP path on the emulator).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:quickbite/app/app.dart';
import 'package:quickbite/app/router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<void> initTestLocale() => initializeDateFormatting('en');

/// Pump the full app with [backend]'s overrides, then optionally navigate to
/// [route]. Returns the provider container for direct controller access.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  TestBackend backend, {
  String? route,
  Size? surfaceSize,
}) async {
  if (surfaceSize != null) {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: backend.overrides,
      child: const QuickBiteApp(),
    ),
  );
  await settleAuth(tester);

  if (route != null) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(QuickBiteApp)),
      listen: false,
    );
    container.read(appRouterProvider).go(route);
    await tester.pump();
  }
  return ProviderScope.containerOf(
    tester.element(find.byType(QuickBiteApp)),
    listen: false,
  );
}

/// Let the splash -> auth-restore -> redirect chain resolve. Never uses
/// pumpAndSettle (polling screens would hang it).
Future<void> settleAuth(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Reset the shared-preferences mock between tests (cart/checkout drafts).
void resetPrefs() {
  SharedPreferences.setMockInitialValues(<String, Object>{});
}

/// Unmount the app so polling timers are disposed before test teardown.
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

bool hasOverflowErrors(FlutterErrorDetails details) =>
    details.exception.toString().contains('overflowed');
