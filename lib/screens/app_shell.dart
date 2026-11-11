import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:url_launcher/url_launcher.dart';

import '../config/project_identity.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';
import '../services/app_backend.dart';
import '../theme/app_theme.dart';
import 'guardian_dashboard.dart';
import 'hospital_sheet.dart';
import 'sharing_requests.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    this.username,
    this.onSignOut,
    this.mapTilesEnabled = true,
  });

  final RideController controller;
  final String? username;
  final Future<void> Function()? onSignOut;
  final bool mapTilesEnabled;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  int _lastNotification = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.notificationOpenCount != _lastNotification) {
          _lastNotification = controller.notificationOpenCount;
          index = 4;
        }
        if (controller.isGuardianView && !controller.isRiding) {
          return GuardianDashboard(
            controller: controller,
            mapTilesEnabled: widget.mapTilesEnabled,
            onSignOut: widget.onSignOut,
          );
        }
        return Scaffold(
          body: Stack(
            children: [
              IndexedStack(
                index: index,
                children: [
                  _HomeScreen(
                    controller: controller,
                    username: widget.username,
                  ),
                  _LiveScreen(
                    controller: controller,
                    mapTilesEnabled: widget.mapTilesEnabled,
                  ),
                  _SafetyScreen(controller: controller),
                  _HistoryScreen(controller: controller),
                  _FamilyScreen(
                    controller: controller,
                    onSignOut: widget.onSignOut,
                  ),
                ],
              ),
              if (controller.emergencyCountdown != null)
                _EmergencyOverlay(controller: controller),
            ],
          ),
          bottomNavigationBar: _BottomPanel(
            controller: controller,
            index: index,
            onSelect: (value) {
              if (value == 4) controller.refreshCloudData();
              setState(() => index = value);
            },
          ),
        );
      },
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.controller,
    required this.index,
    required this.onSelect,
  });
  final RideController controller;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 18,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: controller.isGuardianView && !controller.isRiding
                      ? () {
                          onSelect(4);
                        }
                      : controller.isStarting
                      ? null
                      : () async {
                          if (controller.isRiding) {
                            await controller.stopRide();
                          } else if (!controller.canStartRide) {
                            await _showHelmetCheck(context, controller);
                          } else {
                            await controller.startRide();
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: controller.isRiding
                        ? AppColors.danger
                        : AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  icon: controller.isStarting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          controller.isRiding
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                  label: Text(
                    controller.isStarting
                        ? 'Starting safety systems...'
                        : controller.isRiding
                        ? 'End ride - ${_duration(controller.elapsed)}'
                        : controller.isGuardianView
                        ? 'View my riders and SOS alerts'
                        : controller.canStartRide
                        ? 'Start ride safety systems'
                        : 'Check helmet to start ride',
                  ),
                ),
              ),
            ),
            NavigationBar(
              selectedIndex: index,
              onDestinationSelected: onSelect,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'Live',
                ),
                NavigationDestination(
                  icon: Icon(Icons.shield_outlined),
                  selectedIcon: Icon(Icons.shield),
                  label: 'Safety',
                ),
                NavigationDestination(
                  icon: Icon(Icons.route_outlined),
                  selectedIcon: Icon(Icons.route),
                  label: 'Rides',
                ),
                NavigationDestination(
                  icon: Icon(Icons.family_restroom_outlined),
                  selectedIcon: Icon(Icons.family_restroom),
                  label: 'Family',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.controller, this.username});
  final RideController controller;
  final String? username;

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Good evening, ${_displayName(username)}',
      subtitle: 'Ready for a safer ride?',
      children: [
        GuardianRequestInbox(controller: controller),
        if (controller.errorMessage != null) ...[
          _ErrorBanner(
            message: controller.errorMessage!,
            onClose: controller.clearError,
          ),
          const SizedBox(height: 14),
        ],
        _RideHero(controller: controller),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Safety score',
                value: '${controller.safetyScore}',
                unit: '/100',
                icon: Icons.shield_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                label: 'Current speed',
                value: controller.speedKph.toStringAsFixed(0),
                unit: 'km/h',
                icon: Icons.speed_rounded,
                color: AppColors.amber,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Pre-ride check', side: '3 essentials'),
        const SizedBox(height: 11),
        Card(
          child: Column(
            children: [
              _CheckRow(
                icon: Icons.sports_motorsports_rounded,
                title: 'Helmet check',
                detail: _helmetLabel(controller),
                done: controller.helmetState == HelmetCheckState.detected,
                onTap: () => _showHelmetCheck(context, controller),
              ),
              const Divider(height: 1, indent: 62),
              _CheckRow(
                icon: Icons.location_on_rounded,
                title: 'Precise location',
                detail: controller.currentPosition == null
                    ? 'Checked when ride starts'
                    : 'GPS signal acquired',
                done: controller.currentPosition != null,
              ),
              const Divider(height: 1, indent: 62),
              _CheckRow(
                icon: Icons.people_alt_rounded,
                title: 'Family sharing',
                detail: '${controller.family.length} connected guardians',
                done: controller.family.isNotEmpty,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Quick safety', side: 'On demand'),
        const SizedBox(height: 11),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                icon: Icons.local_hospital_rounded,
                label: 'Hospitals',
                color: AppColors.danger,
                onTap: () => _showOwnHospitals(context, controller),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.sports_motorsports_rounded,
                label: 'Helmet',
                color: AppColors.primary,
                onTap: () => _showHelmetCheck(context, controller),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickAction(
                icon: Icons.sos_rounded,
                label: 'Send SOS',
                color: AppColors.amber,
                onTap: () => _confirmSos(context, controller),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RideHero extends StatelessWidget {
  const _RideHero({required this.controller});
  final RideController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, Color(0xFF165246)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: .18),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(active: controller.isRiding),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  controller.isRiding
                      ? 'RIDE PROTECTION ACTIVE'
                      : 'READY TO PROTECT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.lime,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  controller.backendLabel,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 27),
          Text(
            controller.isRiding
                ? '${controller.speedKph.toStringAsFixed(0)} km/h'
                : controller.canStartRide
                ? 'Ready to begin'
                : 'Helmet check required',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 31,
              fontWeight: FontWeight.w800,
              letterSpacing: -.7,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            controller.isRiding
                ? '${controller.distanceKm.toStringAsFixed(1)} km covered · ${controller.events.length} risk events'
                : controller.canStartRide
                ? 'Start your ride to activate tracking and safety monitoring.'
                : 'Verify your helmet and fasten your chin strap before starting.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .68),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _HeroStat(value: _duration(controller.elapsed), label: 'TIME'),
              _HeroStat(
                value: controller.maxSpeedKph.toStringAsFixed(0),
                label: 'MAX KM/H',
              ),
              _HeroStat(
                value: '${controller.family.length}',
                label: 'GUARDIANS',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveScreen extends StatefulWidget {
  const _LiveScreen({required this.controller, required this.mapTilesEnabled});

  final RideController controller;
  final bool mapTilesEnabled;

  @override
  State<_LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<_LiveScreen> {
  static const _fallbackCenter = gmaps.LatLng(19.0760, 72.8777);
  gmaps.GoogleMapController? _mapController;
  gmaps.LatLng? _lastFollowedPosition;
  double _currentZoom = 11;
  bool _mapReady = false;
  bool _followRider = true;

  RideController get controller => widget.controller;

  gmaps.LatLng? get _riderPosition {
    final position = controller.currentPosition;
    if (position == null) return null;
    return gmaps.LatLng(position.latitude, position.longitude);
  }

  void _centerOnRider() {
    final rider = _riderPosition;
    if (!_mapReady || rider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start a ride to acquire your GPS position.'),
        ),
      );
      return;
    }
    setState(() => _followRider = true);
    _currentZoom = 16;
    _mapController?.animateCamera(gmaps.CameraUpdate.newLatLngZoom(rider, 16));
  }

  void _zoomBy(double amount) {
    if (!_mapReady) return;
    _currentZoom = (_currentZoom + amount).clamp(3, 20).toDouble();
    _mapController?.animateCamera(gmaps.CameraUpdate.zoomTo(_currentZoom));
  }

  void _followLatestPosition() {
    final rider = _riderPosition;
    if (!widget.mapTilesEnabled ||
        !_mapReady ||
        !_followRider ||
        rider == null ||
        rider == _lastFollowedPosition) {
      return;
    }
    _lastFollowedPosition = rider;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady || !_followRider) return;
      final zoom = _currentZoom < 16 ? 16.0 : _currentZoom;
      _currentZoom = zoom;
      _mapController?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(rider, zoom),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _followLatestPosition();
    final rider = _riderPosition;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header(
              title: 'Live ride',
              subtitle: 'Private location shared with your guardians',
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.mapTilesEnabled)
                      gmaps.GoogleMap(
                        initialCameraPosition: gmaps.CameraPosition(
                          target: rider ?? _fallbackCenter,
                          zoom: rider == null ? 11 : 16,
                        ),
                        minMaxZoomPreference: const gmaps.MinMaxZoomPreference(
                          3,
                          20,
                        ),
                        myLocationEnabled: rider != null,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                        onMapCreated: (mapController) {
                          _mapController = mapController;
                          _mapReady = true;
                          _currentZoom = rider == null ? 11 : 16;
                          if (rider != null) _lastFollowedPosition = rider;
                        },
                        onCameraMove: (position) {
                          _currentZoom = position.zoom;
                        },
                        markers: {
                          if (rider != null)
                            gmaps.Marker(
                              markerId: const gmaps.MarkerId('rider'),
                              position: rider,
                              infoWindow: const gmaps.InfoWindow(
                                title: 'Current rider location',
                              ),
                              icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                                gmaps.BitmapDescriptor.hueGreen,
                              ),
                            ),
                          ...controller.nearbyHospitals.map(
                            (place) => gmaps.Marker(
                              markerId: gmaps.MarkerId(
                                'hospital:${place.latitude}:${place.longitude}',
                              ),
                              position: gmaps.LatLng(
                                place.latitude,
                                place.longitude,
                              ),
                              infoWindow: gmaps.InfoWindow(
                                title: place.name,
                                snippet:
                                    '${place.distanceKm.toStringAsFixed(1)} km away',
                                onTap: () => controller.routeToHospital(place),
                              ),
                              onTap: () => controller.routeToHospital(place),
                              icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                                gmaps.BitmapDescriptor.hueRed,
                              ),
                            ),
                          ),
                        },
                        polylines: {
                          if (controller.route.length > 1)
                            gmaps.Polyline(
                              polylineId: const gmaps.PolylineId('ride-route'),
                              points: controller.route
                                  .map(
                                    (point) => gmaps.LatLng(
                                      point.latitude,
                                      point.longitude,
                                    ),
                                  )
                                  .toList(),
                              width: 6,
                              color: AppColors.primary,
                            ),
                        },
                      )
                    else
                      CustomPaint(painter: _MapPainter()),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _MapStatus(controller: controller),
                    ),
                    if (widget.mapTilesEnabled)
                      Positioned(
                        top: 94,
                        right: 14,
                        child: Column(
                          children: [
                            _MapControlButton(
                              tooltip: 'Follow my location',
                              icon: _followRider
                                  ? Icons.gps_fixed_rounded
                                  : Icons.gps_not_fixed_rounded,
                              active: _followRider,
                              onPressed: _centerOnRider,
                            ),
                            const SizedBox(height: 8),
                            _MapControlButton(
                              tooltip: 'Zoom in',
                              icon: Icons.add_rounded,
                              onPressed: () => _zoomBy(1),
                            ),
                            const SizedBox(height: 8),
                            _MapControlButton(
                              tooltip: 'Zoom out',
                              icon: Icons.remove_rounded,
                              onPressed: () => _zoomBy(-1),
                            ),
                          ],
                        ),
                      ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: _LocationPanel(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
            if (controller.nearbyHospitals.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 82,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.nearbyHospitals.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _HospitalCard(
                    place: controller.nearbyHospitals[i],
                    onTap: () => controller.routeToHospital(
                      controller.nearbyHospitals[i],
                    ),
                  ),
                ),
              ),
            ],
            if (controller.routeLoading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 3),
            ] else if (controller.activeRoute != null) ...[
              const SizedBox(height: 10),
              _RouteResult(plan: controller.activeRoute!),
            ],
          ],
        ),
      ),
    );
  }
}

class _SafetyScreen extends StatelessWidget {
  const _SafetyScreen({required this.controller});
  final RideController controller;

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Safety center',
      subtitle: 'Protection tools and ride intelligence',
      children: [
        _ScoreCard(
          score: controller.safetyScore,
          events: controller.events.length,
        ),
        const SizedBox(height: 15),
        _Tool(
          icon: Icons.sports_motorsports_rounded,
          color: AppColors.primary,
          title: 'AI helmet check',
          detail:
              controller.helmetMessage ??
              'Take a clear photo wearing your motorcycle helmet.',
          status: _helmetLabel(controller),
          onTap: () => _showHelmetCheck(context, controller),
        ),
        const SizedBox(height: 10),
        _Tool(
          icon: Icons.local_hospital_rounded,
          color: AppColors.danger,
          title: 'Nearby hospitals',
          detail: 'Medical care around your current position.',
          status: controller.hospitalsLoading ? 'Searching…' : 'Search',
          onTap: () => _showOwnHospitals(context, controller),
        ),
        const SizedBox(height: 10),
        _Tool(
          icon: Icons.notifications_active_rounded,
          color: AppColors.amber,
          title: 'Emergency SOS',
          detail: 'Alert every trusted guardian with your location.',
          status: controller.emergencySending
              ? 'Sending…'
              : controller.emergencySent
              ? 'SOS saved'
              : 'Send alert',
          onTap: () {
            if (!controller.emergencySending) _confirmSos(context, controller);
          },
        ),
        if (controller.emergencyMessage != null) ...[
          const SizedBox(height: 12),
          Text(controller.emergencyMessage!),
        ],
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.errorMessage!,
            style: const TextStyle(color: AppColors.danger),
          ),
        ],
        ...controller.nearbyHospitals.map(
          (hospital) => ListTile(
            title: Text(hospital.name),
            subtitle: Text('${hospital.distanceKm.toStringAsFixed(1)} km away'),
            trailing: const Icon(Icons.directions),
            onTap: () => launchUrl(
              Uri.parse(
                'https://www.google.com/maps/dir/?api=1&destination=${hospital.latitude},${hospital.longitude}',
              ),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Detection status', side: 'On-device'),
        const SizedBox(height: 11),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              children: [
                _SystemRow(
                  icon: Icons.speed_rounded,
                  name: 'Speed monitoring',
                  active: controller.isRiding,
                ),
                _SystemRow(
                  icon: Icons.vibration_rounded,
                  name: 'Impact detection',
                  active: controller.isRiding,
                ),
                _SystemRow(
                  icon: Icons.screen_rotation_alt_rounded,
                  name: 'Rider behavior',
                  active: controller.isRiding,
                ),
                _SystemRow(
                  icon: Icons.location_searching_rounded,
                  name: 'Family location updates',
                  active: controller.isRiding,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryScreen extends StatelessWidget {
  const _HistoryScreen({required this.controller});
  final RideController controller;

  @override
  Widget build(BuildContext context) {
    final km = controller.history.fold<double>(
      0,
      (sum, item) => sum + item.distanceKm,
    );
    return _Page(
      title: 'Ride history',
      subtitle: 'Progress built one safe ride at a time',
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Total distance',
                value: km.toStringAsFixed(0),
                unit: 'km',
                icon: Icons.route_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                label: 'Completed',
                value: '${controller.history.length}',
                unit: 'rides',
                icon: Icons.flag_rounded,
                color: AppColors.amber,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Recent rides', side: 'Newest first'),
        const SizedBox(height: 11),
        ...controller.history.map(
          (ride) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HistoryCard(ride: ride),
          ),
        ),
      ],
    );
  }
}

class _FamilyScreen extends StatelessWidget {
  const _FamilyScreen({required this.controller, this.onSignOut});
  final RideController controller;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Guardian circle',
      subtitle: 'You decide who can see your safety status',
      children: [
        GuardianRequestInbox(controller: controller),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('I am riding'),
              icon: Icon(Icons.two_wheeler),
            ),
            ButtonSegment(
              value: true,
              label: Text('I am a guardian'),
              icon: Icon(Icons.family_restroom),
            ),
          ],
          selected: {controller.isGuardianView},
          onSelectionChanged: (values) =>
              controller.selectGuardianView(values.first),
        ),
        const SizedBox(height: 12),
        const Text(
          'Rider: invite a verified email or phone. Guardian: sign in using that same contact, accept below, then select the rider. Status refreshes every 10 seconds.',
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_active_outlined),
          title: Text(
            controller.notificationStatus,
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(Icons.refresh),
          onTap: controller.enableNotifications,
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 25,
                backgroundColor: Color(0xFF204A41),
                child: Icon(Icons.visibility_rounded, color: AppColors.lime),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live sharing',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      controller.isRiding
                          ? 'Active for this ride'
                          : 'Starts automatically with your ride',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _Dot(active: controller.isRiding),
              IconButton(
                tooltip: 'Refresh family status',
                onPressed: controller.familyLoading
                    ? null
                    : controller.refreshCloudData,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
        if (controller.alerts.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...controller.alerts
              .take(10)
              .map(
                (alert) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    children: [
                      _GuardianAlertCard(alert: alert),
                      if (alert.latitude != null && alert.longitude != null)
                        TextButton.icon(
                          onPressed: () => _showHospitalsNear(
                            context,
                            controller.backend,
                            alert.latitude!,
                            alert.longitude!,
                          ),
                          icon: const Icon(Icons.local_hospital),
                          label: const Text('Hospitals near this SOS'),
                        ),
                    ],
                  ),
                ),
              ),
        ],
        const SizedBox(height: 24),
        _SectionTitle(
          title: 'Your guardians',
          side: '${controller.family.length} connected',
        ),
        const SizedBox(height: 11),
        if (controller.family.isEmpty)
          const _EmptyFamilyCard(
            message: 'Invite someone you trust to view your active rides.',
          )
        else
          ...controller.family.map(
            (member) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  _FamilyCard(member: member),
                  TextButton(
                    onPressed: () async {
                      final remove = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Stop sharing with this guardian?'),
                          content: Text(
                            '${member.name} will lose access to your status and alerts.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (remove == true) {
                        await controller.removeGuardian(member);
                      }
                    },
                    child: const Text('Remove sharing'),
                  ),
                ],
              ),
            ),
          ),
        if (controller.invitations.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle(
            title: 'Invitations',
            side: '${controller.invitations.length} waiting',
          ),
          const SizedBox(height: 11),
          ...controller.invitations.map(
            (invitation) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F4EF),
                    child: Icon(
                      Icons.mark_email_unread_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(invitation.riderEmail),
                  subtitle: const Text('Wants to share live rides with you'),
                  trailing: FilledButton(
                    onPressed: controller.familyLoading
                        ? null
                        : () => controller.acceptInvitation(invitation),
                    child: const Text('Accept'),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (controller.sharedRiders.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionTitle(
            title: 'Riders sharing with you',
            side: '${controller.sharedRiders.length} riders',
          ),
          const SizedBox(height: 11),
          ...controller.sharedRiders.map(
            (member) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FamilyCard(
                member: member,
                onTap: () => controller.watchRider(member),
              ),
            ),
          ),
        ],
        if (controller.familyLoading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 3),
        ],
        if (controller.watchedRider != null) ...[
          const SizedBox(height: 12),
          _SharedRiderCard(status: controller.watchedRider!),
          if (controller.watchedRider!.latitude != null &&
              controller.watchedRider!.longitude != null)
            OutlinedButton.icon(
              onPressed: () => _showHospitalsNear(
                context,
                controller.backend,
                controller.watchedRider!.latitude!,
                controller.watchedRider!.longitude!,
              ),
              icon: const Icon(Icons.local_hospital_outlined),
              label: const Text('Hospitals near this rider'),
            ),
        ],
        if (controller.familyMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            controller.familyMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.primary, fontSize: 12),
          ),
        ],
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: controller.familyLoading
              ? null
              : () => _showInviteGuardian(context, controller),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Invite a guardian'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _ProjectTeamCard(),
        if (onSignOut != null) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out securely'),
          ),
        ],
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE9F4F0),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your live location is private. Sharing activates only during a ride and can be revoked at any time.',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProjectTeamCard extends StatelessWidget {
  const _ProjectTeamCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, Color(0xFF163E35)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A102723),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF244F45),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.school_rounded,
                          color: AppColors.lime,
                          size: 21,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Project team',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            ProjectIdentity.department,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                const Text(
                  ProjectIdentity.college,
                  style: TextStyle(
                    color: Colors.white70,
                    height: 1.4,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                ...ProjectIdentity.students.map(
                  (student) => _StudentIdentityRow(student: student),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            color: const Color(0x1FFFFFFF),
            child: const Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: AppColors.lime,
                  size: 19,
                ),
                SizedBox(width: 10),
                Text(
                  'Project Guide',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                Spacer(),
                Text(
                  ProjectIdentity.guide,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentIdentityRow extends StatelessWidget {
  const _StudentIdentityRow({required this.student});

  final ProjectStudent student;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFF28564B),
            child: Text(
              student.name.substring(0, 1),
              style: const TextStyle(
                color: AppColors.lime,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              student.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF21483F),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              student.usn,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        _Header(title: title, subtitle: subtitle),
        const SizedBox(height: 22),
        ...children,
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 5),
            Text(subtitle),
          ],
        ),
      ),
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outline),
        ),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 17),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 27,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.done,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final bool done;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Icon(
            done ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
            color: done ? AppColors.primary : AppColors.muted,
          ),
        ],
      ),
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: .1),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.side});
  final String title;
  final String side;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          side,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 17,
        ),
      ),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 9,
          letterSpacing: .7,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score, required this.events});
  final int score;
  final int events;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(21),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: score / 100,
                  strokeWidth: 9,
                  backgroundColor: AppColors.outline,
                  color: score >= 80 ? AppColors.primary : AppColors.amber,
                  strokeCap: StrokeCap.round,
                ),
                Text(
                  '$score',
                  style: const TextStyle(
                    fontSize: 25,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 19),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  score >= 90
                      ? 'Excellent riding'
                      : score >= 75
                      ? 'Good riding'
                      : 'Ride with care',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 5),
                Text(
                  '$events risky events in the active ride. The score updates as you ride.',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.status,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String status;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(detail, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              status,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SystemRow extends StatelessWidget {
  const _SystemRow({
    required this.icon,
    required this.name,
    required this.active,
  });
  final IconData icon;
  final String name;
  final bool active;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Icon(
          icon,
          size: 21,
          color: active ? AppColors.primary : AppColors.muted,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _Dot(active: active),
        const SizedBox(width: 7),
        Text(
          active ? 'Active' : 'Standby',
          style: TextStyle(
            color: active ? AppColors.primary : AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.ride});
  final RideSummary ride;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F4EF),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.two_wheeler_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _friendlyDate(ride.startedAt),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ride.distanceKm.toStringAsFixed(1)} km · ${_duration(ride.duration)} · ${ride.maxSpeedKph.toStringAsFixed(0)} km/h max',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color:
                  (ride.safetyScore >= 90 ? AppColors.primary : AppColors.amber)
                      .withValues(alpha: .1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${ride.safetyScore}',
              style: TextStyle(
                color: ride.safetyScore >= 90
                    ? AppColors.primary
                    : AppColors.amber,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.member, this.onTap});
  final FamilyMember member;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFE8F4EF),
                  child: Text(
                    member.initials,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (member.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    member.relationship,
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              onTap == null
                  ? Icons.verified_user_outlined
                  : Icons.chevron_right_rounded,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyFamilyCard extends StatelessWidget {
  const _EmptyFamilyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          const Icon(Icons.group_add_outlined, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ],
      ),
    ),
  );
}

class _SharedRiderCard extends StatelessWidget {
  const _SharedRiderCard({required this.status});
  final SharedRiderStatus status;

  @override
  Widget build(BuildContext context) {
    final active = status.status == 'RIDING';
    final statusLabel = active
        ? 'Riding'
        : status.status == 'SAFE'
        ? 'Safe'
        : 'Offline';
    final updated = status.updatedAt == null
        ? 'No location received yet'
        : 'Updated ${_relativeTime(status.updatedAt!)}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(active: active),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${status.name} · $statusLabel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${status.safetyScore}/100',
                style: const TextStyle(
                  color: AppColors.lime,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${status.speedKph.toStringAsFixed(0)} km/h · $updated',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          if (status.latitude != null && status.longitude != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://www.google.com/maps/search/?api=1&query=${status.latitude},${status.longitude}',
                ),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('Open last location'),
              style: TextButton.styleFrom(foregroundColor: AppColors.lime),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuardianAlertCard extends StatelessWidget {
  const _GuardianAlertCard({required this.alert});
  final SafetyAlert alert;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE8E8),
      border: Border.all(color: AppColors.danger.withValues(alpha: .25)),
      borderRadius: BorderRadius.circular(19),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: AppColors.danger,
          child: Icon(
            Icons.notification_important_rounded,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${alert.riderName} · SOS',
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${alert.reason} · ${_relativeTime(alert.timestamp)}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        if (alert.latitude != null && alert.longitude != null)
          IconButton(
            tooltip: 'Open alert location',
            onPressed: () => launchUrl(
              Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=${alert.latitude},${alert.longitude}',
              ),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(
              Icons.location_on_rounded,
              color: AppColors.danger,
            ),
          ),
      ],
    ),
  );
}

class _MapStatus extends StatelessWidget {
  const _MapStatus({required this.controller});
  final RideController controller;
  @override
  Widget build(BuildContext context) => _MapGlass(
    child: Row(
      children: [
        _Dot(active: controller.isRiding),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.isRiding
                    ? 'Live tracking active'
                    : 'Tracking is paused',
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                controller.isRiding
                    ? 'Updating guardians every 10 seconds'
                    : 'Start a ride to share your position',
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
        Text(
          '${controller.speedKph.toStringAsFixed(0)} km/h',
          style: const TextStyle(
            color: AppColors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _LocationPanel extends StatelessWidget {
  const _LocationPanel({required this.controller});
  final RideController controller;
  @override
  Widget build(BuildContext context) {
    final p = controller.currentPosition;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFF204A41),
            child: Icon(
              Icons.my_location_rounded,
              color: AppColors.lime,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current position',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  p == null
                      ? 'Waiting for GPS signal'
                      : '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showOwnHospitals(context, controller),
            icon: const Icon(
              Icons.local_hospital_outlined,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapGlass extends StatelessWidget {
  const _MapGlass({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(color: AppColors.ink.withValues(alpha: .1), blurRadius: 18),
      ],
    ),
    child: child,
  );
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? AppColors.primary : Colors.white,
    elevation: 5,
    borderRadius: BorderRadius.circular(14),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: active ? Colors.white : AppColors.ink,
    ),
  );
}

class _HospitalCard extends StatelessWidget {
  const _HospitalCard({required this.place, required this.onTap});
  final NearbyPlace place;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 225,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFFFEDED),
                child: Icon(
                  Icons.local_hospital_rounded,
                  color: AppColors.danger,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${place.distanceKm.toStringAsFixed(1)} km away',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RouteResult extends StatelessWidget {
  const _RouteResult({required this.plan});
  final RoutePlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F4F0),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          const Icon(Icons.alt_route_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.distanceKm.toStringAsFixed(1)} km · ${plan.durationMinutes} min by scooter',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  plan.destination.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open navigation',
            onPressed: () => launchUrl(
              Uri.parse(
                'https://www.google.com/maps/dir/?api=1&destination=${plan.destination.latitude},${plan.destination.longitude}',
              ),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(
              Icons.navigation_rounded,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
    decoration: BoxDecoration(
      color: const Color(0xFFFFEDED),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: AppColors.danger),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFF8B3333), fontSize: 12),
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: active ? AppColors.lime : AppColors.amber,
      shape: BoxShape.circle,
    ),
  );
}

class _EmergencyOverlay extends StatelessWidget {
  const _EmergencyOverlay({required this.controller});
  final RideController controller;
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: AppColors.ink.withValues(alpha: .9),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 46,
                backgroundColor: AppColors.danger,
                child: Icon(
                  Icons.car_crash_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'Possible accident detected',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                controller.accidentReason ?? 'Unusual phone motion detected',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 9),
              const Text(
                'Your guardians will be alerted in',
                style: TextStyle(color: Colors.white70),
              ),
              Text(
                '${controller.emergencyCountdown}',
                style: const TextStyle(
                  color: AppColors.lime,
                  fontSize: 72,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: FilledButton(
                  onPressed: controller.cancelEmergency,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.ink,
                  ),
                  child: const Text("I'm safe — cancel alert"),
                ),
              ),
              TextButton(
                onPressed: controller.sendSos,
                child: const Text(
                  'Send SOS now',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE4ECE7),
    );
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 21
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final edge = Paint()
      ..color = const Color(0xFFC9D5CF)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 5; i++) {
      final y = size.height * (.17 + i * .18);
      final path = Path()
        ..moveTo(-30, y)
        ..cubicTo(
          size.width * .25,
          y - 50,
          size.width * .7,
          y + 50,
          size.width + 30,
          y - 10,
        );
      canvas.drawPath(path, road);
      canvas.drawPath(path, edge);
    }
    final route = Path()
      ..moveTo(size.width * .14, size.height * .78)
      ..cubicTo(
        size.width * .28,
        size.height * .6,
        size.width * .45,
        size.height * .72,
        size.width * .55,
        size.height * .47,
      )
      ..cubicTo(
        size.width * .65,
        size.height * .26,
        size.width * .75,
        size.height * .34,
        size.width * .86,
        size.height * .2,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 11
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final pin = Offset(size.width * .86, size.height * .2);
    canvas.drawCircle(pin, 14, Paint()..color = Colors.white);
    canvas.drawCircle(pin, 9, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _duration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return value.inHours > 0
      ? '${value.inHours}:$minutes:$seconds'
      : '$minutes:$seconds';
}

String _friendlyDate(DateTime date) {
  final days = DateTime.now().difference(date).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return '${date.day}/${date.month}/${date.year}';
}

String _relativeTime(DateTime date) {
  final elapsed = DateTime.now().difference(date.toLocal());
  if (elapsed.inSeconds < 60) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours} hr ago';
  return '${elapsed.inDays} days ago';
}

String _displayName(String? username) {
  if (username == null || username.isEmpty) return 'Rider';
  final name = username.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
  return name
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _helmetLabel(RideController controller) =>
    switch (controller.helmetState) {
      HelmetCheckState.notChecked => 'Tap to scan',
      HelmetCheckState.checking => 'Analyzing…',
      HelmetCheckState.detected =>
        'Detected ${controller.helmetConfidence?.toStringAsFixed(0) ?? ''}%',
      HelmetCheckState.notDetected => 'Not detected',
      HelmetCheckState.unavailable =>
        controller.backend.isConfigured ? 'Check failed' : 'Connect backend',
    };

Future<void> _confirmSos(
  BuildContext context,
  RideController controller,
) async {
  final send = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 31,
              backgroundColor: Color(0xFFFFE9E9),
              child: Icon(Icons.sos_rounded, color: AppColors.danger, size: 30),
            ),
            const SizedBox(height: 15),
            Text(
              'Send emergency alert?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 7),
            const Text(
              'Your location and safety status will be shared with every trusted guardian.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                child: const Text('Send SOS now'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
  if (send == true) await controller.sendSos();
}

Future<void> _showInviteGuardian(
  BuildContext context,
  RideController controller,
) async {
  final email = TextEditingController();
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Invite a guardian',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 7),
          const Text(
            'Enter their verified email or phone with country code (+91…). They sign in with that contact and accept in Family.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Guardian email or +91 phone number',
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send secure invitation'),
            ),
          ),
        ],
      ),
    ),
  );
  if (submitted == true && email.text.trim().isNotEmpty) {
    await controller.inviteGuardian(email.text);
  }
  email.dispose();
}

Future<void> _showOwnHospitals(
  BuildContext context,
  RideController controller,
) => showHospitalSearch(
  context,
  title: 'Hospitals near you',
  search: () async {
    await controller.loadHospitals();
    if (controller.hospitalError != null) {
      throw StateError(controller.hospitalError!);
    }
    return controller.nearbyHospitals;
  },
);

Future<void> _showHelmetCheck(
  BuildContext context,
  RideController controller,
) async {
  if (controller.isRiding) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('End your ride before taking a new helmet photo.'),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final checking = controller.helmetState == HelmetCheckState.checking;
          final detected = controller.helmetState == HelmetCheckState.detected;
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sports_motorsports_rounded,
                    size: 48,
                    color: detected ? AppColors.primary : AppColors.amber,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    detected
                        ? 'Helmet detected on your head'
                        : 'Helmet check before riding',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Wear your motorcycle helmet. Keep your whole head and helmet in the frame, with good lighting. Fasten the chin strap.',
                  ),
                  if (checking)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text('Checking your photo…'),
                        ],
                      ),
                    ),
                  if (controller.helmetMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(controller.helmetMessage!),
                    ),
                  if (detected)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: controller.helmetStrapConfirmed,
                      onChanged: (value) =>
                          controller.confirmHelmetStrap(value ?? false),
                      title: const Text(
                        'I have fastened my chin strap and checked the helmet fits securely.',
                      ),
                      subtitle: const Text(
                        'A photo cannot certify fastening or fit.',
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: checking ? null : controller.runHelmetCheck,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      detected ? 'Retake photo' : 'Take helmet photo',
                    ),
                  ),
                  if (detected)
                    TextButton(
                      onPressed: controller.canStartRide
                          ? () => Navigator.pop(context)
                          : null,
                      child: const Text('Ready to ride'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _showHospitalsNear(
  BuildContext context,
  AppBackend backend,
  double latitude,
  double longitude,
) async {
  final search = backend.nearbyHospitals(latitude, longitude);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hospitals near the rider',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Search uses the rider’s shared location. Tap for directions or call to confirm emergency care.',
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<NearbyPlace>>(
                future: search,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text(snapshot.error.toString()));
                  }
                  final hospitals = snapshot.data ?? [];
                  if (hospitals.isEmpty) {
                    return const Center(
                      child: Text('No hospitals found within 10 km.'),
                    );
                  }
                  return ListView(
                    children: hospitals
                        .map(
                          (hospital) => ListTile(
                            leading: const Icon(
                              Icons.local_hospital,
                              color: AppColors.danger,
                            ),
                            title: Text(hospital.name),
                            subtitle: Text(
                              '${hospital.distanceKm.toStringAsFixed(1)} km from rider',
                            ),
                            onTap: () => launchUrl(
                              Uri.parse(
                                'https://www.google.com/maps/dir/?api=1&destination=${hospital.latitude},${hospital.longitude}',
                              ),
                              mode: LaunchMode.externalApplication,
                            ),
                            trailing: hospital.phone == null
                                ? null
                                : IconButton(
                                    tooltip: 'Call hospital',
                                    icon: const Icon(Icons.phone),
                                    onPressed: () => launchUrl(
                                      Uri(scheme: 'tel', path: hospital.phone),
                                    ),
                                  ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
