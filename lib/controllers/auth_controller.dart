import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

enum AuthView { signIn, signUp, verifyEmail, phoneSignIn, phoneCode }

class AuthController extends ChangeNotifier {
  AuthController({AuthService? service}) : _service = service ?? AuthService();

  final AuthService _service;
  StreamSubscription<User?>? _authSubscription;
  bool initializing = true;
  bool busy = false;
  bool signedIn = false;
  String? username;
  String? error;
  String? message;
  AuthView view = AuthView.signIn;
  String pendingEmail = '';
  String pendingPhone = '';
  String? _phoneVerificationId;

  Future<void> initialize() async {
    try {
      await _service.configure();
      _authSubscription ??= _service.userChanges.listen((user) async {
        if (AuthService.hasVerifiedIdentity(user)) {
          signedIn = true;
          username = user?.displayName ?? user?.email ?? user?.phoneNumber;
          notifyListeners();
        }
      });
      signedIn = await _service.isSignedIn();
      username = await _service.currentUsername();
      if (!signedIn && username != null) {
        pendingEmail = username!;
        view = AuthView.verifyEmail;
      }
    } on FirebaseException catch (exception) {
      error = exception.message;
    } catch (exception, stackTrace) {
      _logUnexpected(exception, stackTrace);
      error =
          'Secure authentication could not start. Restart the app and try again.';
    } finally {
      initializing = false;
      notifyListeners();
    }
  }

  Future<String?> accessToken() => _service.accessToken();

  Future<void> signIn(String email, String password) async {
    await _run(() async {
      pendingEmail = email.trim().toLowerCase();
      signedIn = await _service.signIn(email, password);
      username = pendingEmail;
      if (!signedIn) {
        view = AuthView.verifyEmail;
        message = 'Verify your email, then return here to continue.';
      }
    });
  }

  Future<void> signUp(String email, String password) async {
    await _run(() async {
      pendingEmail = email.trim().toLowerCase();
      await _service.signUp(pendingEmail, password);
      username = pendingEmail;
      view = AuthView.verifyEmail;
      message = 'Firebase sent a verification link to $pendingEmail.';
    });
  }

  Future<void> checkEmailVerification() async {
    await _run(() async {
      signedIn = await _service.refreshEmailVerification();
      if (signedIn) {
        username = await _service.currentUsername();
        message = null;
      } else {
        message = 'The email is not verified yet. Open the link and try again.';
      }
    });
  }

  Future<void> resendEmailVerification() async {
    await _run(() async {
      await _service.resendEmailVerification();
      message = 'A new verification link was sent to $pendingEmail.';
    });
  }

  Future<void> sendPhoneCode(String phoneNumber) async {
    await _run(() async {
      pendingPhone = phoneNumber.trim();
      if (!pendingPhone.startsWith('+')) {
        throw const FormatException(
          'Enter the country code, for example +91 98765 43210.',
        );
      }
      _phoneVerificationId = await _service.sendPhoneCode(pendingPhone);
      if (_phoneVerificationId == null) {
        signedIn = true;
        username = pendingPhone;
      } else {
        view = AuthView.phoneCode;
        message = 'Firebase sent a one-time code to $pendingPhone.';
      }
    });
  }

  Future<void> verifyPhoneCode(String code) async {
    await _run(() async {
      final verificationId = _phoneVerificationId;
      if (verificationId == null) {
        throw StateError('Request a new phone code and try again.');
      }
      await _service.verifyPhoneCode(verificationId, code);
      signedIn = true;
      username = pendingPhone;
    });
  }

  Future<void> signOut() async {
    busy = true;
    notifyListeners();
    await _service.signOut();
    signedIn = false;
    username = null;
    pendingEmail = '';
    pendingPhone = '';
    _phoneVerificationId = null;
    busy = false;
    view = AuthView.signIn;
    notifyListeners();
  }

  void show(AuthView nextView) {
    error = null;
    message = null;
    view = nextView;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() operation) async {
    busy = true;
    error = null;
    message = null;
    notifyListeners();
    try {
      await operation();
    } on FirebaseAuthException catch (exception) {
      error = _firebaseMessage(exception);
    } on FormatException catch (exception) {
      error = exception.message;
    } catch (exception, stackTrace) {
      _logUnexpected(exception, stackTrace);
      error =
          'Authentication is unavailable on this device. Try again shortly.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _firebaseMessage(FirebaseAuthException exception) =>
      switch (exception.code) {
        'invalid-credential' => 'The email or password is incorrect.',
        'email-already-in-use' => 'An account already exists for this email.',
        'weak-password' =>
          'Use a stronger password with at least 6 characters.',
        'invalid-email' => 'Enter a valid email address.',
        'invalid-phone-number' =>
          'Enter a valid phone number including the country code.',
        'invalid-verification-code' => 'The one-time code is incorrect.',
        'session-expired' => 'The one-time code expired. Request a new code.',
        'too-many-requests' =>
          'Too many attempts. Please wait before trying again.',
        _ =>
          exception.message ??
              'Firebase Authentication could not complete the request.',
      };

  void _logUnexpected(Object exception, StackTrace stackTrace) {
    debugPrint(
      'Unexpected authentication error (${exception.runtimeType}): $exception',
    );
    debugPrintStack(stackTrace: stackTrace);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
