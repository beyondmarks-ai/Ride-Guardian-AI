import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/cloud_config.dart';
import '../models/ride_models.dart';

class BackendException implements Exception {
  const BackendException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AppBackend {
  AppBackend({http.Client? client}) : _client = client ?? http.Client();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: CloudConfig.azureApiBaseUrl,
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

  void setSessionToken(String? firebaseIdToken) {
    _sessionToken = firebaseIdToken;
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
    String? requestId,
  }) async {
    await sendEmergency(point: point, reason: reason, requestId: requestId);
  }

  Future<Map<String, dynamic>> sendEmergency({
    required RidePoint? point,
    required String reason,
    String? requestId,
  }) => request(
    '/emergency',
    method: 'POST',
    body: {
      'reason': reason,
      'requestId': requestId ?? 'sos-${DateTime.now().microsecondsSinceEpoch}',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (point != null) ...point.toJson(),
    },
  );

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
    final body = await requestUri(uri);
    final items = body['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(NearbyPlace.fromJson)
        .toList();
  }

  Future<HelmetResult> checkHelmet(XFile image) async {
    if (!isConfigured) {
      throw const BackendException('Helmet service is not configured.');
    }
    final response = await _client
        .post(
          Uri.parse('$baseUrl/helmet-check'),
          headers: await _headers(contentType: 'image/jpeg'),
          body: await image.readAsBytes(),
        )
        .timeout(const Duration(seconds: 75));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException(
        'Helmet check could not complete (HTTP ${response.statusCode}). Check your connection and retry.',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final confidence = (decoded['confidence'] as num?)?.toDouble();
    if (decoded['detected'] is! bool ||
        confidence == null ||
        !confidence.isFinite ||
        confidence < 0 ||
        confidence > 100) {
      throw const BackendException(
        'Helmet service returned an invalid result. Retake the photo.',
      );
    }
    return HelmetResult(
      detected: decoded['detected'] == true && confidence >= 80,
      confidence: confidence,
      reason:
          decoded['reason'] as String? ??
          'Retake the photo with your whole helmet visible.',
      strapStatus: decoded['strapStatus'] as String? ?? 'not_visible',
    );
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
    final body = await requestUri(uri);
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

  Future<List<SharingRequest>> fetchGuardianRequests() async =>
      (await _getItems(
        '/guardian-requests',
      )).map(SharingRequest.fromJson).toList();
  Future<List<SharingRequest>> fetchPendingRequests() async => (await _getItems(
    '/riders/requests',
  )).map(SharingRequest.fromJson).toList();
  Future<List<RideSummary>> fetchRiderHistory(String riderId) async {
    final uri = Uri.parse(
      '$baseUrl/rider-rides',
    ).replace(queryParameters: {'riderId': riderId});
    final result = await requestUri(uri);
    return (result['items'] as List<dynamic>? ?? [])
        .map((r) => RideSummary.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<List<SafetyAlert>> fetchAlerts() async {
    final items = await _getItems('/alerts');
    return items.map(SafetyAlert.fromJson).toList();
  }

  Future<bool> inviteGuardian(String email) => _postSuccess(
    '/guardians/invite',
    {'contact': email.trim().toLowerCase()},
  );

  Future<void> removeGuardian(String guardianId) =>
      _post('/guardians/remove', {'guardianId': guardianId});

  Future<bool> acceptInvitation(String riderId) =>
      _postSuccess('/guardians/accept', {'riderId': riderId});

  Future<SharedRiderStatus?> fetchRiderStatus(FamilyMember rider) async {
    if (!isConfigured || rider.userId == null) return null;
    final uri = Uri.parse(
      '$baseUrl/rider-status',
    ).replace(queryParameters: {'riderId': rider.userId});
    final body = await requestUri(uri);
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
  }

  Future<List<Map<String, dynamic>>> _getItems(String path) async {
    if (!isConfigured) return const [];
    final body = await request(path);
    return (body['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    await _postSuccess(path, body);
  }

  Future<bool> _postSuccess(String path, Map<String, Object?> body) async {
    await request(path, method: 'POST', body: body);
    return true;
  }

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
  }) => requestUri(Uri.parse('$baseUrl$path'), method: method, body: body);

  Future<Map<String, dynamic>> requestUri(
    Uri uri, {
    String method = 'GET',
    Map<String, Object?>? body,
  }) async {
    try {
      final outgoing = http.Request(method, uri)
        ..headers.addAll(await _headers());
      if (body != null) outgoing.body = jsonEncode(body);
      final response = await http.Response.fromStream(
        await _client.send(outgoing).timeout(const Duration(seconds: 35)),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) {
          throw const BackendException('Your session expired. Sign in again.');
        }
        Map<String, dynamic>? error;
        try {
          error = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}
        throw BackendException(
          error?['message'] as String? ??
              'The service could not complete this request (${response.statusCode}).',
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on BackendException {
      rethrow;
    } catch (_) {
      throw const BackendException(
        'Unable to reach the server. Check your connection and retry.',
      );
    }
  }

  void dispose() => _client.close();
}
