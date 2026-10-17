/// Idempotency-Key generation for checkout (assignment: one key per
/// distinct checkout attempt, persisted until the outcome is known).
///
/// RFC 4122 v4 shaped key from a cryptographically secure RNG — the shape
/// matters only for uniqueness; the backend accepts 1..128 characters.
library;

import 'dart:math';

String generateIdempotencyKey() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10

  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
