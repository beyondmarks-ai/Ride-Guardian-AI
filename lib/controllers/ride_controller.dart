import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../models/ride_models.dart';
import '../services/app_backend.dart';
import '../services/ride_monitor.dart';

enum HelmetCheckState {
  notChecked,
  checking,
  detected,
  notDetected,
  unavailable,
}

class RideController extends ChangeNotifier {
  RideController({AppBackend? backend, RideMonitor? monitor})
    : backend = backend ?? AppBackend(),
      _monitor = monitor ?? RideMonitor();

  final AppBackend backend;
  final RideMonitor _monitor;
  final ImagePicker _imagePicker = ImagePicker();

  bool isRiding = false;
  bool isStarting = false;
  bool backendOnline = false;
  String? errorMessage;
  DateTime? startedAt;
  Duration elapsed = Duration.zero;
  double speedKph = 0;
  double maxSpeedKph = 0;
  double distanceKm = 0;
  int safetyScore = 100;
  Position? currentPosition;
  HelmetCheckState helmetState = HelmetCheckState.notChecked;
  double? helmetConfidence;
  int? emergencyCountdown;
  bool emergencySent = false;
  List<NearbyPlace> nearbyHospitals = const [];
  bool hospitalsLoading = false;
  bool routeLoading = false;
  RoutePlan? activeRoute;
  bool familyLoading = false;
  String? familyMessage;
  SharedRiderStatus? watchedRider;

  final List<RidePoint> route = [];
  final List<RideEvent> events = [];
  final List<RideSummary> history = [];
  final List<FamilyMember> family = [];
  final List<FamilyMember> sharedRiders = [];
  final List<GuardianInvitation> invitations = [];
  final List<SafetyAlert> alerts = [];

  Timer? _elapsedTimer;
  Timer? _emergencyTimer;
  DateTime? _lastHeartbeat;
  DateTime? _lastBehaviorEvent;
  DateTime? _lastImpact;
  double _previousSpeedMps = 0;

  RidePoint? get latestPoint => route.isEmpty ? null : route.last;
  String get backendLabel => !backend.isConfigured
      ? 'Demo mode'
      : backendOnline
      ? 'Cloud connected'
      : 'Offline queue';

  Future<void> initialize() async {
    backendOnline = await backend.healthCheck();
    if (backend.hasAuthentication) {
      await refreshCloudData();
    }
    notifyListeners();
  }

  Future<void> refreshCloudData() async {
    familyLoading = true;
    notifyListeners();
    final cloudRides = await backend.fetchRides();
    final cloudGuardians = await backend.fetchGuardians();
    final cloudSharedRiders = await backend.fetchSharedRiders();
    final cloudInvitations = await backend.fetchInvitations();
    final cloudAlerts = await backend.fetchAlerts();
    history
      ..clear()
      ..addAll(cloudRides);
    family
      ..clear()
      ..addAll(cloudGuardians);
    sharedRiders
      ..clear()
      ..addAll(cloudSharedRiders);
    invitations
      ..clear()
      ..addAll(cloudInvitations);
    alerts
      ..clear()
      ..addAll(cloudAlerts);
    familyLoading = false;
    notifyListeners();
  }

  Future<void> toggleRide() async {
    if (isRiding) {
      await stopRide();
    } else {
      await startRide();
    }
  }

  Future<void> startRide() async {
    if (isStarting || isRiding) return;
    isStarting = true;
    errorMessage = null;
    emergencySent = false;
    notifyListeners();
    try {
      currentPosition = null;
      await _monitor.start(onPosition: _onPosition, onMotion: _onMotion);
      route.clear();
      events.clear();
      startedAt = DateTime.now();
      elapsed = Duration.zero;
      speedKph = 0;
      maxSpeedKph = 0;
      distanceKm = 0;
      safetyScore = 100;
      _previousSpeedMps = 0;
      isRiding = true;
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsed = DateTime.now().difference(startedAt!);
        notifyListeners();
      });
    } on StateError catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Unable to start safety monitoring on this device.';
    } finally {
      isStarting = false;
      notifyListeners();
    }
  }

  Future<void> stopRide() async {
    if (!isRiding) return;
    await _monitor.stop();
    _elapsedTimer?.cancel();
    _emergencyTimer?.cancel();
    emergencyCountdown = null;
    if (latestPoint != null) {
      await backend.publishLocation(latestPoint!, safetyScore, status: 'SAFE');
    }
    isRiding = false;
    speedKph = 0;
    final summary = RideSummary(
      id: 'ride-${DateTime.now().millisecondsSinceEpoch}',
      startedAt: startedAt ?? DateTime.now(),
      duration: elapsed,
      distanceKm: distanceKm,
      maxSpeedKph: maxSpeedKph,
      safetyScore: safetyScore,
      eventCount: events.length,
    );
    history.insert(0, summary);
    notifyListeners();
    await backend.saveRide(summary: summary, points: route, events: events);
  }

  void _onPosition(Position position) {
    if (!isRiding) return;
    final newSpeedMps = math.max(0.0, position.speed);
    speedKph = newSpeedMps * 3.6;
    maxSpeedKph = math.max(maxSpeedKph, speedKph);

    if (currentPosition != null) {
      final segmentMeters = Geolocator.distanceBetween(
        currentPosition!.latitude,
        currentPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (segmentMeters < 250) distanceKm += segmentMeters / 1000;
    }

    final speedDrop = _previousSpeedMps - newSpeedMps;
    if (speedDrop > 6 && _canAddBehaviorEvent()) {
      _addEvent(RideEventType.harshBrake, speedDrop);
    } else if (newSpeedMps - _previousSpeedMps > 5 && _canAddBehaviorEvent()) {
      _addEvent(
        RideEventType.harshAcceleration,
        newSpeedMps - _previousSpeedMps,
      );
    }
    if (speedKph > 80 && _canAddBehaviorEvent()) {
      _addEvent(RideEventType.overspeed, speedKph);
    }
    _previousSpeedMps = newSpeedMps;
    currentPosition = position;

    final point = RidePoint(
      latitude: position.latitude,
      longitude: position.longitude,
      speedKph: speedKph,
      recordedAt: DateTime.now(),
    );
    route.add(point);
    final now = DateTime.now();
    if (_lastHeartbeat == null ||
        now.difference(_lastHeartbeat!).inSeconds >= 10) {
      _lastHeartbeat = now;
      unawaited(backend.publishLocation(point, safetyScore));
    }
    notifyListeners();
  }

  void _onMotion(MotionSample sample) {
    if (!isRiding) return;
    if (sample.rotation > 4.5 && speedKph > 12 && _canAddBehaviorEvent()) {
      _addEvent(RideEventType.sharpTurn, sample.rotation);
    }
    if (sample.acceleration > 22 &&
        (_lastImpact == null ||
            sample.recordedAt.difference(_lastImpact!).inSeconds > 45)) {
      _lastImpact = sample.recordedAt;
      _addEvent(RideEventType.impact, sample.acceleration);
      _beginEmergencyCountdown();
    }
  }

  bool _canAddBehaviorEvent() =>
      _lastBehaviorEvent == null ||
      DateTime.now().difference(_lastBehaviorEvent!).inSeconds >= 8;

  void _addEvent(RideEventType type, double value) {
    events.add(RideEvent(type: type, timestamp: DateTime.now(), value: value));
    _lastBehaviorEvent = DateTime.now();
    safetyScore = math.max(0, safetyScore - _penalty(type));
    notifyListeners();
  }

  int _penalty(RideEventType type) => switch (type) {
    RideEventType.impact => 15,
    RideEventType.overspeed => 4,
    RideEventType.harshBrake => 3,
    RideEventType.harshAcceleration => 2,
    RideEventType.sharpTurn => 3,
  };

  void _beginEmergencyCountdown() {
    if (emergencyCountdown != null) return;
    emergencyCountdown = 20;
    notifyListeners();
    _emergencyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      emergencyCountdown = (emergencyCountdown ?? 1) - 1;
      if (emergencyCountdown! <= 0) {
        timer.cancel();
        emergencyCountdown = null;
        emergencySent = true;
        unawaited(
          backend.publishEmergency(
            point: latestPoint,
            reason: 'Possible collision detected by device sensors',
          ),
        );
      }
      notifyListeners();
    });
  }

  void cancelEmergency() {
    _emergencyTimer?.cancel();
    emergencyCountdown = null;
    notifyListeners();
  }

  Future<void> sendSos() async {
    emergencySent = true;
    notifyListeners();
    await backend.publishEmergency(
      point: latestPoint,
      reason: 'Manual SOS requested by rider',
    );
  }

  Future<void> runHelmetCheck() async {
    final photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (photo == null) return;
    helmetState = HelmetCheckState.checking;
    notifyListeners();
    final confidence = await backend.checkHelmet(photo);
    helmetConfidence = confidence;
    if (confidence == null) {
      helmetState = HelmetCheckState.unavailable;
    } else {
      helmetState = confidence >= 80
          ? HelmetCheckState.detected
          : HelmetCheckState.notDetected;
    }
    notifyListeners();
  }

  Future<void> loadHospitals() async {
    if (currentPosition == null) {
      errorMessage =
          'Start a ride or enable location to find nearby hospitals.';
      notifyListeners();
      return;
    }
    hospitalsLoading = true;
    notifyListeners();
    nearbyHospitals = await backend.nearbyHospitals(
      currentPosition!.latitude,
      currentPosition!.longitude,
    );
    hospitalsLoading = false;
    notifyListeners();
  }

  Future<void> routeToHospital(NearbyPlace hospital) async {
    if (latestPoint == null) {
      errorMessage = 'Start a ride before calculating a scooter route.';
      notifyListeners();
      return;
    }
    routeLoading = true;
    activeRoute = null;
    notifyListeners();
    activeRoute = await backend.routeTo(
      origin: latestPoint!,
      destination: hospital,
    );
    routeLoading = false;
    if (activeRoute == null) {
      errorMessage = 'A route could not be calculated right now.';
    }
    notifyListeners();
  }

  Future<bool> inviteGuardian(String email) async {
    familyLoading = true;
    familyMessage = null;
    notifyListeners();
    final invited = await backend.inviteGuardian(email);
    familyLoading = false;
    familyMessage = invited
        ? 'Invitation sent. The guardian can accept it after signing in.'
        : 'The invitation could not be sent.';
    notifyListeners();
    return invited;
  }

  Future<void> acceptInvitation(GuardianInvitation invitation) async {
    familyLoading = true;
    notifyListeners();
    final accepted = await backend.acceptInvitation(invitation.riderId);
    familyMessage = accepted
        ? 'Rider sharing accepted.'
        : 'The invitation could not be accepted.';
    await refreshCloudData();
    familyLoading = false;
    notifyListeners();
  }

  Future<void> watchRider(FamilyMember rider) async {
    familyLoading = true;
    watchedRider = null;
    notifyListeners();
    watchedRider = await backend.fetchRiderStatus(rider);
    familyLoading = false;
    if (watchedRider == null) {
      familyMessage = 'The rider status is unavailable.';
    }
    notifyListeners();
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _emergencyTimer?.cancel();
    unawaited(_monitor.stop());
    backend.dispose();
    super.dispose();
  }
}
