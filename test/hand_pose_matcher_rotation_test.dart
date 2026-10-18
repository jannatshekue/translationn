import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:translation/core/services/hand_pose_matcher.dart';

List<HandLandmark> _hand(double angle) {
  final rng = Random(1);
  final pts = <List<double>>[
    for (var i = 0; i < HandLandmarkType.values.length; i++)
      [100 + rng.nextDouble() * 60, 100 + rng.nextDouble() * 60],
  ];
  final c = cos(angle), s = sin(angle);
  return [
    for (var i = 0; i < pts.length; i++)
      HandLandmark(
        type: HandLandmarkType.values[i],
        x: 300 + pts[i][0] * c - pts[i][1] * s,
        y: 300 + pts[i][0] * s + pts[i][1] * c,
        z: 0,
        visibility: 1,
      ),
  ];
}

void main() {
  test('rotated hand normalizes to the same vector', () {
    final upright = HandPoseMatcher.normalizeFrame(_hand(0))!;
    final tilted = HandPoseMatcher.normalizeFrame(_hand(0.6))!;
    expect(HandPoseMatcher.distance(upright, tilted), lessThan(1e-6));
  });
}
