import 'ride_monitor.dart';

/// Heuristic for a suspected accident, never a confirmed crash diagnosis.
class AccidentDetector {
  final List<DateTime> _peaks = [];
  DateTime? _lastPeak;
  DateTime? _lastTrigger;
  DateTime? _lastSample;
  void reset() {
    _peaks.clear();
    _lastPeak = _lastTrigger = _lastSample = null;
  }

  String? add(MotionSample sample, {required double speedKph}) {
    if (!sample.acceleration.isFinite || !sample.rotation.isFinite) return null;
    final now = sample.recordedAt;
    if (_lastSample != null && !now.isAfter(_lastSample!)) return null;
    _lastSample = now;
    _peaks.removeWhere((t) => now.difference(t).inMilliseconds > 2500);
    if (_lastTrigger != null && now.difference(_lastTrigger!).inSeconds < 60) {
      return null;
    }
    if (sample.acceleration >= 12 &&
        (_lastPeak == null ||
            now.difference(_lastPeak!).inMilliseconds >= 180)) {
      _peaks.add(now);
      _lastPeak = now;
    }
    final severeImpact =
        sample.acceleration >= 45 ||
        (sample.acceleration >= 30 && (sample.rotation >= 2 || speedKph >= 8));
    final repeatedVibration =
        _peaks.length >= 8 &&
        now.difference(_peaks.first).inMilliseconds >= 1400;
    if (!severeImpact && !repeatedVibration) return null;
    _lastTrigger = now;
    _peaks.clear();
    return severeImpact
        ? 'Strong impact detected by phone sensors'
        : 'Repeated strong vibrations detected by phone sensors';
  }
}
