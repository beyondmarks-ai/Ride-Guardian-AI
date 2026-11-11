import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../controllers/ride_controller.dart';
import '../models/ride_models.dart';
import '../theme/app_theme.dart';
import 'hospital_sheet.dart';
import 'sharing_requests.dart';

class GuardianDashboard extends StatelessWidget {
  const GuardianDashboard({
    super.key,
    required this.controller,
    this.mapTilesEnabled = true,
    this.onSignOut,
  });
  final RideController controller;
  final bool mapTilesEnabled;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    final rider = controller.watchedRider;
    final fresh =
        controller.backendOnline &&
        rider?.updatedAt != null &&
        DateTime.now().difference(rider!.updatedAt!) <
            const Duration(seconds: 60);
    final riding = fresh && rider.status == 'RIDING';
    final status = rider == null
        ? 'Select a rider'
        : !fresh || rider.status == 'OFFLINE'
        ? 'Updates unavailable'
        : riding
        ? 'Ride in progress'
        : 'Ride ended';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardian dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh riders',
            onPressed: controller.refreshCloudData,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'rider') controller.selectGuardianView(false);
              if (action == 'signout') onSignOut?.call();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'rider',
                child: Text('Switch to rider'),
              ),
              if (onSignOut != null)
                const PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refreshCloudData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            const Text(
              'Your riders, at a glance',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text('Shared updates refresh about every 10 seconds.'),
            const SizedBox(height: 12),
            ConnectRiderCard(controller: controller),
            if (controller.connectionMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(controller.connectionMessage!),
              ),
            ...controller.pendingRequests.map(
              (request) => Card(
                child: ListTile(
                  leading: const Icon(Icons.hourglass_top),
                  title: Text(request.contact),
                  subtitle: const Text(
                    'Waiting for rider approval • expires after 7 days',
                  ),
                  trailing: TextButton(
                    onPressed: controller.connectionBusy
                        ? null
                        : () => controller.cancelRiderRequest(request),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 4,
                child: controller.familyLoading
                    ? const LinearProgressIndicator()
                    : null,
              ),
            ),
            if (!controller.backendOnline && controller.familyMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  controller.familyMessage!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(
                controller.notificationStatus,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.settings_outlined),
              onTap: controller.enableNotifications,
            ),
            if (controller.invitations.isNotEmpty) ...[
              const Text(
                'Sharing invitations',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              ...controller.invitations.map(
                (invite) => Card(
                  child: ListTile(
                    title: Text(invite.riderEmail),
                    subtitle: const Text('Wants to share rides with you'),
                    trailing: FilledButton(
                      onPressed: controller.familyLoading
                          ? null
                          : () => controller.acceptInvitation(invite),
                      child: const Text('Accept'),
                    ),
                  ),
                ),
              ),
            ],
            if (controller.sharedRiders.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.family_restroom,
                        size: 48,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Connect your first rider',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Enter the rider’s phone number above. They will see your request on Home and in Family. Their data appears after they allow sharing.',
                      ),
                      TextButton(
                        onPressed: controller.refreshCloudData,
                        child: const Text('Check for invitations'),
                      ),
                    ],
                  ),
                ),
              ),
            if (controller.sharedRiders.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: ValueKey(rider?.riderId),
                initialValue: rider?.riderId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Watching rider',
                  prefixIcon: Icon(Icons.two_wheeler),
                ),
                items: controller.sharedRiders
                    .map(
                      (r) => DropdownMenuItem(
                        value: r.userId,
                        child: Text(r.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: controller.familyLoading
                    ? null
                    : (id) => controller.watchRider(
                        controller.sharedRiders.firstWhere(
                          (r) => r.userId == id,
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xff102e29), Color(0xff1d5147)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 10,
                          color: riding ? AppColors.lime : Colors.amber,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            status,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.two_wheeler,
                          color: AppColors.lime,
                          size: 30,
                        ),
                      ],
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: riding ? rider.speedKph : 0),
                      duration: const Duration(milliseconds: 650),
                      builder: (context, speed, _) => SizedBox(
                        height: 230,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _SpeedDial(speed),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 34),
                                Text(
                                  riding ? speed.toStringAsFixed(0) : '—',
                                  style: const TextStyle(
                                    fontSize: 64,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const Text(
                                  'km/h',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      rider?.updatedAt == null
                          ? 'Waiting for the rider’s first location'
                          : 'Last update: ${rider!.updatedAt!.toLocal().toString().substring(0, 19)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fresh
                          ? 'Safety score ${rider.safetyScore}/100'
                          : 'Speed hidden until fresh updates arrive',
                      style: const TextStyle(color: AppColors.lime),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Rider location',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (rider?.latitude != null && rider?.longitude != null) ...[
                Text(
                  fresh && riding
                      ? 'Latest shared position'
                      : 'Last known position • may no longer be current',
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  key: const ValueKey('guardian-location-map'),
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    height: 230,
                    child: mapTilesEnabled
                        ? _RiderMap(rider: rider!)
                        : const ColoredBox(
                            color: Color(0xffdcebe5),
                            child: Center(
                              child: Icon(Icons.location_on, size: 42),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${rider!.latitude!.toStringAsFixed(5)}, ${rider.longitude!.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 12),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => openExternal(
                        context,
                        Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=${rider.latitude},${rider.longitude}',
                        ),
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Open location'),
                    ),
                    FilledButton.icon(
                      onPressed: () => showHospitalSearch(
                        context,
                        title: 'Hospitals near this rider',
                        search: () => controller.backend.nearbyHospitals(
                          rider.latitude!,
                          rider.longitude!,
                        ),
                      ),
                      icon: const Icon(Icons.local_hospital_outlined),
                      label: const Text('Nearby hospitals'),
                    ),
                  ],
                ),
              ] else
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Location appears when this rider starts sharing a ride.',
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            if (rider != null)
              Card(
                key: ValueKey('history-${rider.riderId}'),
                child: ExpansionTile(
                  leading: const Icon(Icons.route_outlined),
                  title: const Text('Ride history'),
                  subtitle: Text(
                    '${controller.watchedHistory.length} saved rides • ${controller.watchedHistory.fold<double>(0, (total, r) => total + r.distanceKm).toStringAsFixed(1)} km',
                  ),
                  children: [
                    if (controller.watchedHistoryError != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(controller.watchedHistoryError!),
                      )
                    else if (controller.watchedHistory.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No completed rides shared yet.'),
                      )
                    else
                      ...controller.watchedHistory.map(
                        (ride) => ListTile(
                          leading: const Icon(Icons.two_wheeler),
                          title: Text(
                            ride.startedAt.toLocal().toString().substring(
                              0,
                              16,
                            ),
                          ),
                          subtitle: Text(
                            '${ride.distanceKm.toStringAsFixed(1)} km • ${ride.duration.inMinutes} min\nMax ${ride.maxSpeedKph.toStringAsFixed(0)} km/h • Safety ${ride.safetyScore}/100 • ${ride.eventCount} events',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Accident checks & SOS',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'During a ride, strong impacts or repeated strong vibrations start a 20-second check on the rider’s phone. If they do not cancel, an SOS is sent to connected guardians.',
            ),
            const SizedBox(height: 12),
            if (controller.alerts.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('No SOS alerts received'),
                ),
              ),
            ...controller.alerts.map(
              (alert) => Card(
                color: const Color(0xffffeded),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.sos, color: AppColors.danger),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${alert.riderName} · SOS',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(alert.reason),
                      Text(
                        alert.timestamp.toLocal().toString().substring(0, 19),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (alert.latitude != null && alert.longitude != null)
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => openExternal(
                                context,
                                Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=${alert.latitude},${alert.longitude}',
                                ),
                              ),
                              child: const Text('SOS location'),
                            ),
                            TextButton(
                              onPressed: () => showHospitalSearch(
                                context,
                                title: 'Hospitals near this SOS',
                                search: () =>
                                    controller.backend.nearbyHospitals(
                                      alert.latitude!,
                                      alert.longitude!,
                                    ),
                              ),
                              child: const Text('Hospitals'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiderMap extends StatefulWidget {
  const _RiderMap({required this.rider});
  final SharedRiderStatus rider;
  @override
  State<_RiderMap> createState() => _RiderMapState();
}

class _RiderMapState extends State<_RiderMap> {
  GoogleMapController? map;
  LatLng get point => LatLng(widget.rider.latitude!, widget.rider.longitude!);
  @override
  void didUpdateWidget(covariant _RiderMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rider.latitude != widget.rider.latitude ||
        oldWidget.rider.longitude != widget.rider.longitude) {
      map?.animateCamera(CameraUpdate.newLatLng(point));
    }
  }

  @override
  void dispose() {
    map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GoogleMap(
    initialCameraPosition: CameraPosition(target: point, zoom: 15),
    onMapCreated: (controller) => map = controller,
    myLocationButtonEnabled: false,
    markers: {
      Marker(
        markerId: const MarkerId('rider'),
        position: point,
        infoWindow: InfoWindow(title: widget.rider.name),
      ),
    },
  );
}

class _SpeedDial extends CustomPainter {
  _SpeedDial(this.speed);
  final double speed;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .56);
    final radius = math.min(size.width * .43, size.height * .47);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi * .78, sweep = math.pi * 1.44;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      start,
      sweep * (speed / 120).clamp(0, 1),
      false,
      Paint()
        ..color = AppColors.lime
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );
    for (int i = 0; i <= 24; i++) {
      final a = start + sweep * i / 24;
      final u = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + u * (radius - 16),
        center + u * (radius - (i % 4 == 0 ? 27 : 22)),
        Paint()
          ..color = Colors.white54
          ..strokeWidth = 2,
      );
    }
    final angle = start + sweep * (speed / 120).clamp(0, 1);
    canvas.drawCircle(
      center + Offset(math.cos(angle), math.sin(angle)) * radius,
      7,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedDial oldDelegate) =>
      oldDelegate.speed != speed;
}
