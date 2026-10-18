import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/features/menu/widgets/menu_item_card.dart';
import 'package:quickbite/ui/widgets/pressable.dart';

import '../helpers/fakes.dart';
import '../helpers/harness.dart';

void main() {
  setUpAll(initTestLocale);
  setUp(resetPrefs);

  testWidgets('cards activate once with Enter and Space', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Pressable(
            onTap: () => taps++,
            child: const SizedBox(
              width: 180,
              height: 100,
              child: Text('Open kitchen'),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 2);
  });

  for (final size in [
    const Size(360, 640),
    const Size(393, 852),
    const Size(768, 1024),
    const Size(1280, 900),
    const Size(1440, 900),
    const Size(852, 393),
  ]) {
    testWidgets('four stage-one screens fit ${size.width}×${size.height}', (
      tester,
    ) async {
      final backend = TestBackend();
      await pumpApp(tester, backend, surfaceSize: size);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: 'welcome');
      await navTo(tester, '/login');
      expect(tester.takeException(), isNull, reason: 'login');
      await backend.signIn();
      await unmountApp(tester);
      await pumpApp(tester, backend, surfaceSize: size);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: 'discovery');
      await navTo(tester, '/menu/rest_bella_napoli');
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MenuItemCard), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'menu');
      await unmountApp(tester);
    });
  }

  testWidgets('large text and keyboard inset keep login usable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(
      tester,
      TestBackend(),
      surfaceSize: const Size(360, 640),
      route: '/login',
    );
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(TextFormField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(FilledButton, 'Sign In').hitTestable(),
      findsOneWidget,
    );
    await unmountApp(tester);
  });

  testWidgets('large text selects readable full-width menu cards', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = TestBackend();
    await backend.signIn();
    await pumpApp(
      tester,
      backend,
      surfaceSize: const Size(360, 640),
      route: '/menu/rest_bella_napoli',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(
      find.byType(MenuItemCard),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getSize(find.byType(MenuItemCard)).width, 328);
    expect(tester.takeException(), isNull);
    await unmountApp(tester);
  });

  testWidgets('reduced motion shows settled welcome and route content', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, TestBackend(), surfaceSize: const Size(393, 852));
    expect(find.text('Welcome to\nQuickBite').hitTestable(), findsOneWidget);
    await navTo(tester, '/login');
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await unmountApp(tester);
  });
}
