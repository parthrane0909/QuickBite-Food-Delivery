/// Money formatting: integer minor units -> localized currency text.
///
/// The backend contract stores money as integer minor units with an
/// explicit ISO currency (default INR: 1250 -> "₹1,250.00"). All arithmetic
/// stays in minor units; this file is the ONLY place conversion for display
/// happens. No client-side pricing decisions are ever made here.
library;

import 'package:intl/intl.dart';

String formatMinor(int minor, String currency) {
  final code = currency.toUpperCase();
  final format = NumberFormat.currency(
    name: code,
    symbol: _symbols[code] ?? '',
    decimalDigits: _minorDigits(code),
  );
  return format.format(minor / _minorDigitsScale(code));
}

/// Common currency symbol fallbacks for codes intl's locale data may miss.
const Map<String, String> _symbols = {'INR': '₹', 'USD': '\$', 'EUR': '€', 'GBP': '£'};

/// ISO 4217 minor-unit exponents for the currencies this app can serve.
int _minorDigits(String code) => switch (code) {
      'JPY' || 'KRW' => 0,
      'BHD' || 'KWD' || 'OMR' => 3,
      _ => 2,
    };

int _minorDigitsScale(String code) {
  final digits = _minorDigits(code);
  return digits == 0 ? 1 : digits == 3 ? 1000 : 100;
}
