import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../models/ride_models.dart';
import '../services/app_backend.dart';
import '../services/ride_monitor.dart';
import '../services/accident_detector.dart';

enum HelmetCheckState {
  notChecked,
  checking,
  detected,
  notDetected,
  unavailable,
}

class RideController extends ChangeNotifier {
  RideController({
    AppBackend? backend,
    RideMonitor? monitor,
    Future<XFile?> Function()? captureHelmet,
  }) : backend = backend ?? AppBackend(),
       _captureHelmet = captureHelmet,
       _monitor = monitor ?? RideMonitor();

  final AppBackend backend;
  final RideMonitor _monitor;
  final ImagePicker _imagePicker = ImagePicker();
  final Future<XFile?> Function()? _captureHelmet;
  final AccidentDetector _accidentDetector = AccidentDetector();
  String? _rolePreferenceKey;
  Future<void> restoreRole(String userId) async {
    _rolePreferenceKey = 'guardian-view:$userId';
    final preferences = await SharedPreferences.getInstance();
    isGuardianView = preferences.getBool(_rolePreferenceKey!) ?? false;
    notifyListeners();
  }

  Future<void> _saveRole() async {
    if (_rolePreferenceKey == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_rolePreferenceKey!, isGuardianView);
    } catch (_) {
      /* The role remains selected for the current session. */
    }
  }

  DateTime? helmetVerifiedAt;
  bool helmetStrapConfirmed = false;
  String? helmetMessage;
  String? hospitalError;
  String? accidentReason;
  bool get canStartRide =>
      helmetState == HelmetCheckState.detected &&
      helmetStrapConfirmed &&
      helmetVerifiedAt != null &&
      DateTime.now().difference(helmetVerifiedAt!) < const Duration(minutes: 5);

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
  bool emergencySending = false;
  String? emergencyMessage;
  String? _pendingSosId;
  String notificationStatus = 'Notifications not registered yet';
  int notificationOpenCount = 0;
  Future<void> Function()? enableNotifications;
  List<NearbyPlace> nearbyHospitals = const [];
  bool hospitalsLoading = false;
  bool routeLoading = false;
  RoutePlan? activeRoute;
  bool familyLoading = false;
  String? familyMessage;
  SharedRiderStatus? watchedRider;
  final List<RideSummary> watchedHistory = [];
  final List<SharingRequest> guardianRequests = [];
  final List<SharingRequest> pendingRequests = [];
  bool connectionBusy = false;
  String? connectionMessage;
  String? watchedHistoryError;

  final List<RidePoint> route = [];
  final List<RideEvent> events = [];
  final List<RideSummary> history = [];
  final List<FamilyMember> family = [];
  final List<FamilyMember> sharedRiders = [];
  final List<GuardianInvitation> invitations = [];
  final List<SafetyAlert> alerts = [];

  Timer? _elapsedTimer;
  Timer? _emergencyTimer;
  Timer? _familyTimer;
  Timer? _heartbeatTimer;
  FamilyMember? _selectedRider;
  bool _disposed = false;
  bool _publishing = false;
  bool isGuardianView = false;
  DateTime? _lastHeartbeat;
  DateTime? _lastBehaviorEvent;
  double _previousSpeedMps = 0;

  RidePoint? get latestPoint => route.isEmpty ? null : route.last;
  String get backendLabel => !backend.isConfigured
      ? 'Demo mode'
      : backendOnline
      ? 'Cloud connected'
      : 'Cloud unavailable';

  Future<void> initialize() async {
    backendOnline = await backend.healthCheck();
    if (backend.hasAuthentication) {
      await refreshCloudData();
      _familyTimer?.cancel();
      _familyTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        unawaited(refreshCloudData());
      });
    }
    notifyListeners();
  }

  Future<void> refreshCloudData() async {
    if (_disposed || familyLoading) return;
    familyLoading = true;
    notifyListeners();
    try {
      final (
        cloudRides,
        cloudGuardians,
        cloudSharedRiders,
        cloudInvitations,
        cloudAlerts,
        cloudRequests,
        cloudPending,
      ) = await (
        backend.fetchRides(),
        backend.fetchGuardians(),
        backend.fetchSharedRiders(),
        backend.fetchInvitations(),
        backend.fetchAlerts(),
        backend.fetchGuardianRequests(),
        backend.fetchPendingRequests(),
      ).wait;
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
      guardianRequests
        ..clear()
        ..addAll(cloudRequests);
      pendingRequests
        ..clear()
        ..addAll(cloudPending);
      if (_selectedRider != null &&
          !sharedRiders.any((r) => r.userId == _selectedRider!.userId)) {
        _selectedRider = null;
        watchedRider = null;
        watchedHistory.clear();
      }
      if (_selectedRider != null) {
        watchedRider = await backend.fetchRiderStatus(_selectedRider!);
      } else if (isGuardianView && sharedRiders.isNotEmpty) {
        _selectedRider = sharedRiders.first;
        watchedRider = await backend.fetchRiderStatus(_selectedRider!);
      }
      if (_selectedRider != null) await _loadWatchedHistory();
      backendOnline = true;
    } catch (error) {
      backendOnline = false;
      watchedHistory.clear();
      watchedHistoryError = 'Ride history unavailable. Pull down to retry.';
      familyMessage = error.toString();
    } finally {
      familyLoading = false;
      notifyListeners();
    }
  }

  void selectGuardianView(bool selected) {
    if (selected && isRiding) {
      errorMessage =
          'End your ride before switching to the guardian dashboard.';
      notifyListeners();
      return;
    }
    isGuardianView = selected;
    unawaited(_saveRole());
    if (selected && backend.hasAuthentication) unawaited(refreshCloudData());
    notifyListeners();
  }

  void openNotification({String? kind}) {
    notificationOpenCount++;
    if (!isRiding) {
      isGuardianView = kind != 'CONNECTION_REQUEST';
      unawaited(_saveRole());
    }
    unawaited(refreshCloudData());
    notifyListeners();
  }

  Future<void> _publishHeartbeat() async {
    if (_publishing || !isRiding || latestPoint == null) return;
    _publishing = true;
    try {
      final p = latestPoint!;
      // Keep the actual GPS observation timestamp; do not make stale GPS look fresh.
      await backend.publishLocation(p, safetyScore);
      backendOnline = true;
    } catch (error) {
      backendOnline = false;
      errorMessage = error.toString();
    } finally {
      _publishing = false;
      notifyListeners();
    }
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
    if (isGuardianView || !canStartRide) {
      errorMessage =
          'Complete a fresh helmet check and fasten your chin strap before starting a ride.';
      notifyListeners();
      return;
    }
    isStarting = true;
    errorMessage = null;
    emergencySent = false;
    notifyListeners();
    try {
      currentPosition = null;
      route.clear();
      events.clear();
      startedAt = DateTime.now();
      elapsed = Duration.zero;
      speedKph = 0;
      maxSpeedKph = 0;
      distanceKm = 0;
      safetyScore = 100;
      _accidentDetector.reset();
      _previousSpeedMps = 0;
      _lastHeartbeat = null;
      isRiding = true;
      await _monitor.start(onPosition: _onPosition, onMotion: _onMotion);
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(_publishHeartbeat()),
      );
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsed = DateTime.now().difference(startedAt!);
        notifyListeners();
      });
    } on StateError catch (error) {
      isRiding = false;
      await _monitor.stop();
      errorMessage = error.message;
    } catch (_) {
      isRiding = false;
      await _monitor.stop();
      errorMessage = 'Unable to start safety monitoring on this device.';
    } finally {
      isStarting = false;
      notifyListeners();
    }
  }

  Future<void> stopRide() async {
    if (!isRiding) return;
    isRiding = false;
    helmetVerifiedAt = null;
    helmetStrapConfirmed = false;
    helmetState = HelmetCheckState.notChecked;
    _heartbeatTimer?.cancel();
    await _monitor.stop();
    _elapsedTimer?.cancel();
    _emergencyTimer?.cancel();
    emergencyCountdown = null;
    if (latestPoint != null) {
      try {
        final p = latestPoint!;
        await backend.publishLocation(
          RidePoint(
            latitude: p.latitude,
            longitude: p.longitude,
            speedKph: 0,
            recordedAt: DateTime.now(),
          ),
          safetyScore,
          status: 'SAFE',
        );
      } catch (error) {
        errorMessage =
            'Ride stopped on this phone. Cloud update failed: $error';
      }
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
    try {
      await backend.saveRide(summary: summary, points: route, events: events);
    } catch (error) {
      errorMessage = 'Ride stopped. History could not be saved: $error';
      notifyListeners();
    }
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
      unawaited(_publishHeartbeat());
    }
    notifyListeners();
  }

  void _onMotion(MotionSample sample) {
    if (!isRiding) return;
    if (sample.rotation > 4.5 && speedKph > 12 && _canAddBehaviorEvent()) {
      _addEvent(RideEventType.sharpTurn, sample.rotation);
    }
    final suspected = _accidentDetector.add(sample, speedKph: speedKph);
    if (suspected != null) {
      accidentReason = suspected;
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
    unawaited(HapticFeedback.heavyImpact());
    unawaited(SystemSound.play(SystemSoundType.alert));
    notifyListeners();
    _emergencyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      emergencyCountdown = (emergencyCountdown ?? 1) - 1;
      if (emergencyCountdown! <= 0) {
        timer.cancel();
        emergencyCountdown = null;
        unawaited(
          sendSos(
            reason:
                'Suspected accident: ${accidentReason ?? 'unusual motion'}; rider did not cancel the 20-second check',
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

  Future<void> sendSos({
    String reason = 'Manual SOS requested by rider',
  }) async {
    if (emergencySending) return;
    _emergencyTimer?.cancel();
    emergencyCountdown = null;
    emergencySending = true;
    emergencySent = false;
    emergencyMessage = null;
    _pendingSosId ??= 'sos-${DateTime.now().microsecondsSinceEpoch}';
    notifyListeners();
    try {
      RidePoint? point = latestPoint;
      if (point == null) {
        try {
          point = await _getLocationPoint();
        } catch (_) {
          /* Send SOS even without GPS. */
        }
      }
      final result = await backend.sendEmergency(
        point: point,
        reason: reason,
        requestId: _pendingSosId,
      );
      emergencySent = result['saved'] == true;
      emergencyMessage = (result['guardians'] as num? ?? 0) == 0
          ? 'SOS saved, but no guardian is connected. Call 112 if you need urgent help.'
          : 'SOS saved for ${result['guardians']} guardian(s). Push notification queued; delivery depends on their connection and permissions.';
      _pendingSosId = null;
    } catch (error) {
      emergencyMessage = 'SOS was not confirmed. Retry or call 112. $error';
      errorMessage = emergencyMessage;
    } finally {
      emergencySending = false;
      notifyListeners();
    }
  }

  Future<RidePoint> _getLocationPoint() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location services.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Allow location access in phone settings.');
    }
    currentPosition = await Geolocator.getCurrentPosition().timeout(
      const Duration(seconds: 10),
    );
    final p = currentPosition!;
    return RidePoint(
      latitude: p.latitude,
      longitude: p.longitude,
      speedKph: 0,
      recordedAt: DateTime.now(),
    );
  }

  Future<void> runHelmetCheck() async {
    if (helmetState == HelmetCheckState.checking || isRiding) return;
    helmetVerifiedAt = null;
    helmetStrapConfirmed = false;
    helmetConfidence = null;
    helmetMessage = null;
    helmetState = HelmetCheckState.checking;
    notifyListeners();
    try {
      final photo = _captureHelmet != null
          ? await _captureHelmet()
          : await _imagePicker.pickImage(
              source: ImageSource.camera,
              preferredCameraDevice: CameraDevice.front,
              imageQuality: 88,
              maxWidth: 1600,
            );
      if (photo == null) {
        helmetState = HelmetCheckState.notChecked;
        helmetMessage =
            'Photo cancelled. A helmet check is required before riding.';
        return;
      }
      final result = await backend.checkHelmet(photo);
      helmetConfidence = result.confidence;
      helmetState = result.detected
          ? HelmetCheckState.detected
          : HelmetCheckState.notDetected;
      helmetMessage = result.reason;
      if (result.detected) helmetVerifiedAt = DateTime.now();
    } catch (error) {
      helmetState = HelmetCheckState.unavailable;
      helmetMessage = 'Could not verify the photo. $error';
    } finally {
      notifyListeners();
    }
  }

  void confirmHelmetStrap(bool confirmed) {
    helmetStrapConfirmed =
        confirmed && helmetState == HelmetCheckState.detected;
    notifyListeners();
  }

  Future<void> loadHospitals() async {
    if (hospitalsLoading) return;
    hospitalsLoading = true;
    hospitalError = null;
    nearbyHospitals = const [];
    notifyListeners();
    try {
      await _getLocationPoint();
      nearbyHospitals = await backend.nearbyHospitals(
        currentPosition!.latitude,
        currentPosition!.longitude,
      );
      if (nearbyHospitals.isEmpty) {
        hospitalError = 'No hospitals found within 10 km.';
      }
    } catch (error) {
      errorMessage = error.toString();
      hospitalError = error.toString();
    }
    hospitalsLoading = false;
    notifyListeners();
  }

  Future<void> routeToHospital(NearbyPlace hospital) async {
    routeLoading = true;
    activeRoute = null;
    notifyListeners();
    try {
      activeRoute = await backend.routeTo(
        origin: latestPoint ?? await _getLocationPoint(),
        destination: hospital,
      );
    } catch (error) {
      errorMessage = error.toString();
    }
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
    bool invited = false;
    try {
      invited = await backend.inviteGuardian(email);
    } catch (error) {
      familyMessage = error.toString();
    }
    familyLoading = false;
    familyMessage = invited
        ? 'Invitation sent. The guardian can accept it after signing in.'
        : familyMessage ?? 'The invitation could not be sent.';
    notifyListeners();
    return invited;
  }

  Future<void> acceptInvitation(GuardianInvitation invitation) async {
    familyLoading = true;
    notifyListeners();
    bool accepted = false;
    try {
      accepted = await backend.acceptInvitation(invitation.riderId);
    } catch (error) {
      familyMessage = error.toString();
    }
    familyMessage = accepted
        ? 'Rider sharing accepted.'
        : familyMessage ?? 'The invitation could not be accepted.';
    familyLoading = false;
    await refreshCloudData();
    familyLoading = false;
    notifyListeners();
  }

  Future<void> watchRider(FamilyMember rider) async {
    if (familyLoading) return;
    _selectedRider = rider;
    familyLoading = true;
    watchedRider = null;
    watchedHistory.clear();
    notifyListeners();
    try {
      watchedRider = await backend.fetchRiderStatus(rider);
      await _loadWatchedHistory();
    } catch (error) {
      familyMessage = error.toString();
    }
    familyLoading = false;
    if (watchedRider == null) {
      familyMessage = 'The rider status is unavailable.';
    }
    notifyListeners();
  }

  Future<void> _loadWatchedHistory() async {
    watchedHistoryError = null;
    try {
      final rides = await backend.fetchRiderHistory(_selectedRider!.userId!);
      watchedHistory
        ..clear()
        ..addAll(rides);
    } catch (error) {
      watchedHistory.clear();
      watchedHistoryError = error.toString();
    }
  }

  Future<void> requestRider(String contact) => _connectionAction(
    '/riders/request',
    {'contact': contact},
    'Request sent. Ask the rider to open Family and allow sharing.',
  );
  Future<void> cancelRiderRequest(SharingRequest request) => _connectionAction(
    '/riders/request/cancel',
    {'contact': request.contact},
    'Request cancelled.',
  );
  Future<void> respondToGuardian(SharingRequest request, bool accept) =>
      _connectionAction(
        '/guardian-requests/respond',
        {
          'guardianId': request.guardianId,
          'action': accept ? 'accept' : 'decline',
        },
        accept
            ? 'Guardian connected. You can remove sharing in Family.'
            : 'Connection request declined.',
      );
  Future<void> _connectionAction(
    String path,
    Map<String, Object?> body,
    String success,
  ) async {
    if (connectionBusy) return;
    connectionBusy = true;
    connectionMessage = null;
    notifyListeners();
    try {
      await backend.request(path, method: 'POST', body: body);
      connectionMessage = success;
      await refreshCloudData();
    } catch (error) {
      connectionMessage = error.toString();
    } finally {
      connectionBusy = false;
      notifyListeners();
    }
  }

  Future<void> removeGuardian(FamilyMember guardian) async {
    try {
      await backend.removeGuardian(guardian.userId!);
      familyMessage = 'Sharing removed.';
      await refreshCloudData();
    } catch (error) {
      familyMessage = error.toString();
      notifyListeners();
    }
  }

  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _familyTimer?.cancel();
    _heartbeatTimer?.cancel();
    _elapsedTimer?.cancel();
    _emergencyTimer?.cancel();
    unawaited(_monitor.stop());
    backend.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
