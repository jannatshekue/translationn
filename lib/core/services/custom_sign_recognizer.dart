import 'package:hand_detection/hand_detection.dart';

import '../../models/custom_sign.dart';
import 'database_service.dart';
import 'hand_pose_matcher.dart';

class CustomSignMatch {
  final CustomSign sign;
  final double distance;

  const CustomSignMatch(this.sign, this.distance);
}

/// Matches a live hand pose against saved custom signs. Call [loadTemplates]
/// once per screen session (custom signs rarely change mid-session), then
/// [match] per detected hand.
class CustomSignRecognizer {
  CustomSignRecognizer._internal();

  static final CustomSignRecognizer instance = CustomSignRecognizer._internal();

  /// Cutoff on the normalized 42-value landmark distance (palm lengths).
  /// Live landmark jitter alone is ~0.5 here, so the old 0.5 cutoff rejected
  /// nearly every real attempt; clearly different hand shapes are > 2.
  static const matchThreshold = 1.2;

  /// A sign's recorded poses, thinned to at most this many frames.
  static const _maxFramesPerSign = 20;

  List<MapEntry<CustomSign, List<List<double>>>> _templates = [];

  Future<void> loadTemplates() async {
    final signs = await DatabaseService.instance.getCustomSigns();
    final templates = <MapEntry<CustomSign, List<List<double>>>>[];
    for (final sign in signs) {
      try {
        final vectors = sign.decodedFrames
            .map(HandPoseMatcher.normalizeFrameFromMaps)
            .whereType<List<double>>()
            .toList();
        if (vectors.isEmpty) continue;
        final step = (vectors.length / _maxFramesPerSign).ceil().clamp(1, vectors.length);
        templates.add(MapEntry(sign, [for (var i = 0; i < vectors.length; i += step) vectors[i]]));
      } catch (_) {
        // A corrupt saved sign must not break recognition of the others.
      }
    }
    _templates = templates;
  }

  CustomSignMatch? match(List<HandLandmark> landmarks) {
    if (_templates.isEmpty) return null;
    final vector = HandPoseMatcher.normalizeFrame(landmarks);
    if (vector == null) return null;

    CustomSign? bestSign;
    var bestDistance = double.infinity;
    for (final entry in _templates) {
      // Compare with each recorded pose and keep the closest: averaging a
      // 2s recording blurs the sign into a pose the user never makes.
      var d = double.infinity;
      for (final frame in entry.value) {
        final fd = HandPoseMatcher.distance(vector, frame);
        if (fd < d) d = fd;
      }
      if (d < bestDistance) {
        bestDistance = d;
        bestSign = entry.key;
      }
    }
    if (bestSign == null || bestDistance > matchThreshold) return null;
    return CustomSignMatch(bestSign, bestDistance);
  }
}
