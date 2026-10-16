import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickbite/app/app.dart';
import 'package:quickbite/app/router.dart';

void main() {
  testWidgets('QuickBite app boots to the home shell', (WidgetTester tester) async {
    await tester.pumpWidget(const QuickBiteApp());
    await tester.pumpAndSettle();

    expect(find.text('QuickBite'), findsWidgets);
    expect(find.textContaining('Foundation scaffold'), findsOneWidget);
  });

  testWidgets('unknown deep link renders not-found with a recovery action',
      (WidgetTester tester) async {
    await tester.pumpWidget(const QuickBiteApp());
    await tester.pumpAndSettle();

    appRouter.go('/definitely/not/a/route');
    await tester.pumpAndSettle();

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Back to home'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Back to home'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Foundation scaffold'), findsOneWidget);
  });
}
