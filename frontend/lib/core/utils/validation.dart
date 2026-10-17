/// Input validation mirroring the BACKEND contract bounds (the server
/// remains authoritative; these only give fast, accessible inline feedback).
/// Bounds verified in docs/api.md: email format, password 1..256,
/// delivery address 1..500 after trim.
library;

final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Enter your email address.';
  if (trimmed.length > 255 || !_emailRe.hasMatch(trimmed)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validatePassword(String value) {
  if (value.isEmpty) return 'Enter your password.';
  if (value.length > 256) return 'Password is too long.';
  return null;
}

String? validateDeliveryAddress(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Enter a delivery address.';
  if (trimmed.length > 500) return 'Address must be at most 500 characters.';
  return null;
}
