import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:person_of_interest/src/machine/liveness.dart';
import 'package:person_of_interest/src/machine/ssn.dart';

void main() {
  BlinkDetector feed(List<double?> probabilities, {int stepMs = 35}) {
    final detector = BlinkDetector();
    for (var i = 0; i < probabilities.length; i++) {
      detector.add(probabilities[i], i * stepMs);
    }
    return detector;
  }

  test('a normal blink is detected', () {
    expect(feed([0.9, 0.95, 0.5, 0.1, 0.05, 0.2, 0.8, 0.9]).blinked, isTrue);
  });

  test('a still photo, closed eyes or missing data are not a blink', () {
    expect(feed(List.filled(60, 0.92)).blinked, isFalse);
    expect(feed([0.1, 0.1, 0.9, 0.9]).blinked, isFalse, reason: 'never seen open before closing');
    expect(feed([0.9, ...List.filled(40, 0.05), 0.9]).blinked, isFalse, reason: 'eyes shut far too long');
    expect(feed([null, null, null]).blinked, isFalse);
  });

  test('SSNs are validly formatted', () {
    final random = math.Random(1);
    final pattern = RegExp(r'^(\d{3})-(\d{2})-(\d{4})$');
    for (var i = 0; i < 2000; i++) {
      final match = pattern.firstMatch(randomSsn(random))!;
      final area = int.parse(match[1]!);
      expect(area, isNot(anyOf(0, 666)));
      expect(area, lessThan(900));
      expect(match[2], isNot('00'));
      expect(match[3], isNot('0000'));
    }
  });
}
