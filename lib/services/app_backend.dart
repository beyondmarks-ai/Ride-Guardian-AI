import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/aws_config.dart';
import '../models/ride_models.dart';

class AppBackend {
  AppBackend({http.Client? client}) : _client = client ?? http.Client();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: AwsConfig.apiBaseUrl,
  );
  final http.Client _client;
  String? _sessionToken;
  Future<String?> Function()? _tokenProvider;

  bool get isConfigured => baseUrl.trim().isNotEmpty;
  bool get hasAuthentication => _sessionToken != null || _tokenProvider != null;

  Future<Map<String, String>> _headers({
    String contentType = 'application/json',
  }) async {
    final token = _tokenProvider == null
        ? _sessionToken
        : await _tokenProvider!.call();
    return {
      'content-type': contentType,
      if (token != null) 'authorization': 'Bearer $token',
    };
  }

  void setSessionToken(String? cognitoJwt) {
    _sessionToken = cognitoJwt;
  }

  void setTokenProvider(Future<String?> Function()? provider) {
    _tokenProvider = provider;
  }

  Future<bool> healthCheck() async {
    if (!isConfigured) return false;
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'), headers: await _headers())
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<void> publishLocation(
    RidePoint point,
    int safetyScore, {
    String status = 'RIDING',
  }) async {
    if (!isConfigured) return;
    await _post('/location', {
      ...point.toJson(),
      'safetyScore': safetyScore,
      'status': status,
    });
  }

  Future<void> publishEmergency({
    required RidePoint? point,
    required String reason,
  }) async {
    if (!isConfigured) return;
    await _post('/emergency', {
      'reason': reason,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (point != null) ...point.toJson(),
    });
  }

  Future<void> saveRide({
    required RideSummary summary,
    required List<RidePoint> points,
    required List<RideEvent> events,
  }) async {
    if (!isConfigured) return;
    await _post('/rides', {
      'id': summary.id,
      'startedAt': summary.startedAt.toUtc().toIso8601String(),
      'durationSeconds': summary.duration.inSeconds,
      'distanceKm': summary.distanceKm,
      'maxSpeedKph': summary.maxSpeedKph,
      'safetyScore': summary.safetyScore,
      'points': points.map((point) => point.toJson()).toList(),
      'events': events.map((event) => event.toJson()).toList(),
    });
  }

  Future<List<NearbyPlace>> nearbyHospitals(
    double latitude,
    double longitude,
  ) async {
    if (!isConfigured) return const [];
    final uri = Uri.parse('$baseUrl/nearby-hospitals').replace(
      queryParameters: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
      },
    );
    try {
      final response = await _client
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = body['items'] as List<dynamic>? ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map(NearbyPlace.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<double?> checkHelmet(XFile image) async {
    if (!isConfigured) return null;
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/helmet-check'),
            headers: await _headers(contentType: 'image/jpeg'),
            body: await image.readAsBytes(),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return (decoded['confidence'] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  Future<RoutePlan?> routeTo({
    required RidePoint origin,
    required NearbyPlace destination,
  }) async {
    if (!isConfigured) return null;
    final uri = Uri.parse('$baseUrl/route').replace(
      queryParameters: {
        'originLat': origin.latitude.toString(),
        'originLng': origin.longitude.toString(),
        'destinationLat': destination.latitude.toString(),
        'destinationLng': destination.longitude.toString(),
      },
    );
    try {
      final response = await _client
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = body['Routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) return null;
      final summary =
          (routes.first as Map<String, dynamic>)['Summary']
              as Map<String, dynamic>;
      return RoutePlan(
        destination: destination,
        distanceKm: ((summary['Distance'] as num?) ?? 0) / 1000,
        durationMinutes: (((summary['Duration'] as num?) ?? 0) / 60).ceil(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<RideSummary>> fetchRides() async {
    final items = await _getItems('/rides');
    return items.map(RideSummary.fromJson).toList();
  }

  Future<List<FamilyMember>> fetchGuardians() async {
    final items = await _getItems('/guardians');
    return items
        .map(
          (item) => FamilyMember.fromJson(
            item,
            relationship: 'Can view your live rides',
          ),
        )
        .toList();
  }

  Future<List<FamilyMember>> fetchSharedRiders() async {
    final items = await _getItems('/shared-riders');
    return items
        .map(
          (item) => FamilyMember.fromJson(
            item,
            relationship: 'Shares live rides with you',
          ),
        )
        .toList();
  }

  Future<List<GuardianInvitation>> fetchInvitations() async {
    final items = await _getItems('/guardians/invitations');
    return items.map(GuardianInvitation.fromJson).toList();
  }

  Future<List<SafetyAlert>> fetchAlerts() async {
    final items = await _getItems('/alerts');
    return items.map(SafetyAlert.fromJson).toList();
  }

  Future<bool> inviteGuardian(String email) =>
      _postSuccess('/guardians/invite', {'email': email.trim().toLowerCase()});

  Future<bool> acceptInvitation(String riderId) =>
      _postSuccess('/guardians/accept', {'riderId': riderId});

  Future<SharedRiderStatus?> fetchRiderStatus(FamilyMember rider) async {
    if (!isConfigured || rider.userId == null) return null;
    final uri = Uri.parse(
      '$baseUrl/rider-status',
    ).replace(queryParameters: {'riderId': rider.userId});
    try {
      final response = await _client
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final status = body['status'] as Map<String, dynamic>?;
      return SharedRiderStatus(
        riderId: rider.userId!,
        name: rider.name,
        status: status?['status'] as String? ?? 'OFFLINE',
        updatedAt: DateTime.tryParse(status?['updatedAt'] as String? ?? ''),
        latitude: (status?['latitude'] as num?)?.toDouble(),
        longitude: (status?['longitude'] as num?)?.toDouble(),
        speedKph: (status?['speedKph'] as num?)?.toDouble() ?? 0,
        safetyScore: (status?['safetyScore'] as num?)?.toInt() ?? 100,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _getItems(String path) async {
    if (!isConfigured) return const [];
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl$path'), headers: await _headers())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    await _postSuccess(path, body);
  }

  Future<bool> _postSuccess(String path, Map<String, Object?> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl$path'),
            headers: await _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      // Ride monitoring must never fail because the cloud is unreachable.
      return false;
    }
  }

  void dispose() => _client.close();
}
