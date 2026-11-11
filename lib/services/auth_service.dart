import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _authOverride = auth;

  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static bool hasVerifiedIdentity(User? user) =>
      user != null &&
      (user.emailVerified || (user.phoneNumber?.isNotEmpty ?? false));

  Stream<User?> get userChanges => _auth.userChanges();

  Future<void> configure() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    if (kDebugMode && defaultTargetPlatform == TargetPlatform.android) {
      // Sideloaded debug APKs are not recognized by Google Play Integrity.
      // Firebase's reCAPTCHA fallback provides real phone verification during
      // device development; Play-distributed release builds use Play Integrity.
      await _auth.setSettings(forceRecaptchaFlow: true);
    }
  }

  Future<bool> isSignedIn() async {
    await _auth.currentUser?.reload();
    final user = _auth.currentUser;
    return hasVerifiedIdentity(user);
  }

  Future<String?> accessToken() async {
    final user = _auth.currentUser;
    if (!hasVerifiedIdentity(user)) return null;
    return user!.getIdToken();
  }

  Future<String?> currentUsername() async {
    final user = _auth.currentUser;
    return user?.displayName ?? user?.email ?? user?.phoneNumber;
  }

  Future<bool> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return credential.user?.emailVerified ?? false;
  }

  Future<void> signUp(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    await credential.user?.sendEmailVerification();
  }

  Future<bool> refreshEmailVerification() async {
    await _auth.currentUser?.reload();
    await _auth.currentUser?.getIdToken(true);
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> resendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Create the account again to continue.');
    await user.sendEmailVerification();
  }

  Future<String?> sendPhoneCode(String phoneNumber) async {
    final result = Completer<String?>();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber.replaceAll(RegExp(r'[\s()-]'), ''),
      verificationCompleted: (credential) async {
        try {
          await _auth.signInWithCredential(credential);
          if (!result.isCompleted) result.complete();
        } catch (error, stackTrace) {
          if (!result.isCompleted) result.completeError(error, stackTrace);
        }
      },
      verificationFailed: (error) {
        if (!result.isCompleted) result.completeError(error);
      },
      codeSent: (verificationId, _) {
        if (!result.isCompleted) result.complete(verificationId);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!result.isCompleted) result.complete(verificationId);
      },
    );
    return result.future.timeout(const Duration(seconds: 120));
  }

  Future<void> verifyPhoneCode(String verificationId, String smsCode) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    await _auth.signInWithCredential(credential);
  }

  Future<void> signOut() => _auth.signOut();
}
