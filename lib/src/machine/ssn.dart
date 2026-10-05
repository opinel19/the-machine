import 'dart:math' as math;

/// A random, validly formatted social security number such as 527-81-3309:
/// the area is never 000, 666 or 900+, the group never 00, the serial never
/// 0000. The Machine gave out numbers like these.
String randomSsn(math.Random random) {
  int area;
  do {
    area = 1 + random.nextInt(899);
  } while (area == 666);
  final group = 1 + random.nextInt(99);
  final serial = 1 + random.nextInt(9999);
  return '${area.toString().padLeft(3, '0')}-'
      '${group.toString().padLeft(2, '0')}-'
      '${serial.toString().padLeft(4, '0')}';
}
