import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';

import '../controllers/ride_controller.dart';

class GuardianNotifications {
  GuardianNotifications(this.controller);
  final RideController controller;
  final _messaging = FirebaseMessaging.instance;
  static const _channel = MethodChannel('rideguardian/notifications');
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  String? _token;
  bool _disposed = false;

  Future<void> start() async {
    controller.enableNotifications = start;
    try {
      final permissions = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permissions.authorizationStatus == AuthorizationStatus.denied) {
        controller.notificationStatus =
            'Notifications blocked. Enable them in phone settings for SOS alerts.';
        return;
      }
      await _register(await _messaging.getToken());
      _tokens ??= _messaging.onTokenRefresh.listen((token) async {
        try {
          await _register(token);
        } catch (_) {
          controller.notificationStatus =
              'Notification registration failed. Tap to retry.';
          controller.notifyListeners();
        }
      });
      _foreground ??= FirebaseMessaging.onMessage.listen((message) async {
        if (_disposed) return;
        unawaited(controller.refreshCloudData());
        try {
          await _channel.invokeMethod('show', {
            'id': message.messageId,
            'title': message.notification?.title,
            'body': message.notification?.body,
            'kind': message.data['kind'],
          });
        } catch (_) {
          /* Alerts remain available in Family. */
        }
      });
      _opened ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (message) =>
            controller.openNotification(kind: message.data['kind'] as String?),
      );
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'opened' && !_disposed) {
          controller.openNotification(kind: call.arguments as String?);
        }
      });
      final initial = await _messaging.getInitialMessage();
      final nativeKind = await _channel.invokeMethod<String>('consumeOpened');
      if (initial != null || nativeKind != null) {
        controller.openNotification(
          kind: initial?.data['kind'] as String? ?? nativeKind,
        );
      }
    } catch (_) {
      controller.notificationStatus =
          'Notifications unavailable. Tap to retry; check Family for alerts.';
    } finally {
      controller.notifyListeners();
    }
  }

  Future<void> _register(String? token) async {
    if (_disposed || token == null) return;
    await controller.backend.request(
      '/devices',
      method: 'POST',
      body: {'token': token},
    );
    _token = token;
    controller.notificationStatus = 'SOS notifications enabled on this device';
    controller.notifyListeners();
  }

  Future<void> signOut() async {
    // Remove the account binding before another person signs in on this phone.
    if (_token != null) {
      await controller.backend.request(
        '/devices',
        method: 'DELETE',
        body: {'token': _token},
      );
    }
    await _messaging.deleteToken();
    dispose();
  }

  void dispose() {
    _disposed = true;
    _tokens?.cancel();
    _foreground?.cancel();
    _opened?.cancel();
    _channel.setMethodCallHandler(null);
  }
}
