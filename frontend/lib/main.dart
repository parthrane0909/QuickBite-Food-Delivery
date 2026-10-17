import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Deterministic date formatting everywhere (screens pin the 'en' locale).
  await initializeDateFormatting('en');
  runApp(const ProviderScope(child: QuickBiteApp()));
}
