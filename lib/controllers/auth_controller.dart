import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

enum AuthView { signIn, signUp, confirm }

class AuthController extends ChangeNotifier {
  AuthController({AuthService? service}) : _service = service ?? AuthService();

  final AuthService _service;
  bool initializing = true;
  bool busy = false;
  bool signedIn = false;
  String? username;
  String? error;
  AuthView view = AuthView.signIn;
  String pendingEmail = '';

  Future<void> initialize() async {
    try {
      await _service.configure();
      signedIn = await _service.isSignedIn();
      username = await _service.currentUsername();
    } on AmplifyException catch (exception) {
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
      signedIn = await _service.signIn(email, password);
      if (!signedIn) {
        error = 'Additional sign-in verification is required.';
        return;
      }
      username = email.trim().toLowerCase();
    });
  }

  Future<void> signUp(String email, String password) async {
    await _run(() async {
      pendingEmail = email.trim().toLowerCase();
      final complete = await _service.signUp(pendingEmail, password);
      view = complete ? AuthView.signIn : AuthView.confirm;
    });
  }

  Future<void> confirm(String code) async {
    await _run(() async {
      final complete = await _service.confirmSignUp(pendingEmail, code);
      if (complete) view = AuthView.signIn;
    });
  }

  Future<void> signOut() async {
    busy = true;
    notifyListeners();
    await _service.signOut();
    signedIn = false;
    username = null;
    busy = false;
    view = AuthView.signIn;
    notifyListeners();
  }

  void show(AuthView nextView) {
    error = null;
    view = nextView;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() operation) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } on AuthException catch (exception) {
      error = exception.message;
    } catch (exception, stackTrace) {
      _logUnexpected(exception, stackTrace);
      error =
          'Authentication is unavailable on this device. Restart the app and try again.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _logUnexpected(Object exception, StackTrace stackTrace) {
    debugPrint(
      'Unexpected authentication error (${exception.runtimeType}): '
      '$exception',
    );
    debugPrintStack(stackTrace: stackTrace);
  }
}
