enum RideEventType {
  harshBrake,
  harshAcceleration,
  sharpTurn,
  overspeed,
  impact,
}

class RideEvent {
  const RideEvent({
    required this.type,
    required this.timestamp,
    required this.value,
  });

  final RideEventType type;
  final DateTime timestamp;
  final double value;

  Map<String, Object> toJson() => {
    'type': type.name,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'value': value,
  };
}

class RidePoint {
  const RidePoint({
    required this.latitude,
    required this.longitude,
    required this.speedKph,
    required this.recordedAt,
  });

  final double latitude;
  final double longitude;
  final double speedKph;
  final DateTime recordedAt;

  Map<String, Object> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'speedKph': speedKph,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}

class RideSummary {
  const RideSummary({
    required this.id,
    required this.startedAt,
    required this.duration,
    required this.distanceKm,
    required this.maxSpeedKph,
    required this.safetyScore,
    required this.eventCount,
  });

  final String id;
  final DateTime startedAt;
  final Duration duration;
  final double distanceKm;
  final double maxSpeedKph;
  final int safetyScore;
  final int eventCount;

  factory RideSummary.fromJson(Map<String, dynamic> json) => RideSummary(
    id: json['rideId'] as String? ?? json['id'] as String? ?? 'ride',
    startedAt:
        DateTime.tryParse(json['startedAt'] as String? ?? '') ?? DateTime.now(),
    duration: Duration(
      seconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    ),
    distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
    maxSpeedKph: (json['maxSpeedKph'] as num?)?.toDouble() ?? 0,
    safetyScore: (json['safetyScore'] as num?)?.toInt() ?? 100,
    eventCount: (json['events'] as List<dynamic>?)?.length ?? 0,
  );
}

class FamilyMember {
  const FamilyMember({
    required this.name,
    required this.relationship,
    required this.initials,
    this.userId,
    this.email,
    this.canViewLiveLocation = true,
    this.isOnline = false,
  });

  final String name;
  final String relationship;
  final String initials;
  final String? userId;
  final String? email;
  final bool canViewLiveLocation;
  final bool isOnline;

  factory FamilyMember.fromJson(
    Map<String, dynamic> json, {
    required String relationship,
  }) {
    final email = json['email'] as String? ?? 'Guardian';
    final display = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
    final name = display
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
    final initials = name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join();
    return FamilyMember(
      name: name.isEmpty ? 'Guardian' : name,
      relationship: relationship,
      initials: initials.isEmpty ? 'G' : initials,
      userId: json['userId'] as String?,
      email: email,
    );
  }
}

class GuardianInvitation {
  const GuardianInvitation({required this.riderId, required this.riderEmail});

  final String riderId;
  final String riderEmail;

  factory GuardianInvitation.fromJson(Map<String, dynamic> json) =>
      GuardianInvitation(
        riderId: json['riderId'] as String? ?? '',
        riderEmail: json['riderEmail'] as String? ?? 'Rider',
      );
}

class SharedRiderStatus {
  const SharedRiderStatus({
    required this.riderId,
    required this.name,
    required this.status,
    required this.updatedAt,
    this.latitude,
    this.longitude,
    this.speedKph = 0,
    this.safetyScore = 100,
  });

  final String riderId;
  final String name;
  final String status;
  final DateTime? updatedAt;
  final double? latitude;
  final double? longitude;
  final double speedKph;
  final int safetyScore;
}

class SafetyAlert {
  const SafetyAlert({
    required this.riderId,
    required this.reason,
    required this.timestamp,
    this.latitude,
    this.longitude,
  });

  final String riderId;
  final String reason;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;

  factory SafetyAlert.fromJson(Map<String, dynamic> json) => SafetyAlert(
    riderId: json['riderId'] as String? ?? '',
    reason: json['reason'] as String? ?? 'Emergency alert',
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
  );
}

class NearbyPlace {
  const NearbyPlace({
    required this.name,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
    this.phone,
  });

  final String name;
  final double distanceKm;
  final double latitude;
  final double longitude;
  final String? phone;

  factory NearbyPlace.fromJson(Map<String, dynamic> json) => NearbyPlace(
    name: json['name'] as String? ?? 'Hospital',
    distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    phone: json['phone'] as String?,
  );
}

class RoutePlan {
  const RoutePlan({
    required this.destination,
    required this.distanceKm,
    required this.durationMinutes,
  });

  final NearbyPlace destination;
  final double distanceKm;
  final int durationMinutes;
}
