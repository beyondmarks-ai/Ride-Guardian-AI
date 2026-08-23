import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

class MotionSample {
  const MotionSample({
    required this.acceleration,
    required this.rotation,
    required this.recordedAt,
  });

  final double acceleration;
  final double rotation;
  final DateTime recordedAt;
}

class RideMonitor {
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<UserAccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  double _rotation = 0;

  Future<void> start({
    required void Function(Position position) onPosition,
    required void Function(MotionSample sample) onMotion,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on Location Services to begin a ride.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required for ride safety.');
    }

    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: Duration(seconds: 2),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'RideGuardian protection is active',
          notificationText: 'Monitoring speed, location and ride safety',
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      );
    }
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(onPosition);

    // Seed the UI immediately instead of waiting for the stream's distance
    // filter to emit after the rider starts moving.
    try {
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: settings,
      ).timeout(const Duration(seconds: 12));
      onPosition(initialPosition);
    } on TimeoutException {
      // The position stream remains active and will update when GPS locks.
    }

    _gyroscopeSubscription =
        gyroscopeEventStream(
          samplingPeriod: SensorInterval.gameInterval,
        ).listen((event) {
          _rotation = math.sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );
        });
    _accelerometerSubscription =
        userAccelerometerEventStream(
          samplingPeriod: SensorInterval.gameInterval,
        ).listen((event) {
          final acceleration = math.sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );
          onMotion(
            MotionSample(
              acceleration: acceleration,
              rotation: _rotation,
              recordedAt: DateTime.now(),
            ),
          );
        });
  }

  Future<void> stop() async {
    await _positionSubscription?.cancel();
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    _positionSubscription = null;
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _rotation = 0;
  }
}
