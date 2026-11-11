import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'config/project_identity.dart';
import 'controllers/auth_controller.dart';
import 'controllers/ride_controller.dart';
import 'screens/app_shell.dart';
import 'screens/auth_screen.dart';
import 'screens/role_screen.dart';
import 'services/guardian_notifications.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const RideGuardianApp());
}

class RideGuardianApp extends StatefulWidget {
  const RideGuardianApp({
    super.key,
    this.authenticationEnabled = true,
    this.mapTilesEnabled = true,
  });

  final bool authenticationEnabled;
  final bool mapTilesEnabled;

  @override
  State<RideGuardianApp> createState() => _RideGuardianAppState();
}

class _RideGuardianAppState extends State<RideGuardianApp> {
  late RideController controller;
  GuardianNotifications? notifications;
  late final AuthController authController;
  bool sessionApplied = false;
  bool sessionReady = false;
  bool? chosenGuardianRole;

  void _chooseRole(bool guardian) {
    setState(() => chosenGuardianRole = guardian);
    controller.selectGuardianView(guardian);
  }

  @override
  void initState() {
    super.initState();
    controller = RideController();
    authController = AuthController()..addListener(_onAuthChanged);
    if (widget.authenticationEnabled) {
      authController.initialize();
    } else {
      controller.initialize();
    }
  }

  Future<void> _onAuthChanged() async {
    if (authController.signedIn && !sessionApplied) {
      sessionApplied = true;
      controller.backend.setTokenProvider(authController.accessToken);
      await controller.restoreRole(FirebaseAuth.instance.currentUser!.uid);
      if (chosenGuardianRole != null) {
        controller.selectGuardianView(chosenGuardianRole!);
      }
      await controller.initialize();
      if (!mounted || !authController.signedIn) return;
      setState(() => sessionReady = true);
      notifications = GuardianNotifications(controller);
      await notifications!.start();
    } else if (!authController.signedIn && sessionApplied) {
      sessionApplied = false;
      sessionReady = false;
      chosenGuardianRole = null;
      controller.backend.setTokenProvider(null);
      notifications?.dispose();
      notifications = null;
      controller.dispose();
      controller = RideController();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    notifications?.dispose();
    authController
      ..removeListener(_onAuthChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RideGuardian AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: widget.authenticationEnabled
          ? ListenableBuilder(
              listenable: authController,
              builder: (context, _) {
                if (chosenGuardianRole == null) {
                  return RoleScreen(onSelect: _chooseRole);
                }
                if (authController.initializing) {
                  return const _SplashScreen();
                }
                if (!authController.signedIn) {
                  return AuthScreen(
                    controller: authController,
                    guardian: chosenGuardianRole!,
                    onChangeRole: () =>
                        setState(() => chosenGuardianRole = null),
                  );
                }
                if (!sessionReady) return const _SplashScreen();
                return AppShell(
                  controller: controller,
                  username: authController.username,
                  mapTilesEnabled: widget.mapTilesEnabled,
                  onSignOut: () async {
                    try {
                      await controller.stopRide();
                      await notifications?.signOut();
                      await authController.signOut();
                    } catch (_) {
                      controller.familyMessage =
                          'Could not safely sign out. Check your connection and retry.';
                      controller.notifyListeners();
                    }
                  },
                );
              },
            )
          : AppShell(
              controller: controller,
              mapTilesEnabled: widget.mapTilesEnabled,
            ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded, color: AppColors.lime, size: 64),
            SizedBox(height: 20),
            Text(
              'RideGuardian AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                ProjectIdentity.department,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            SizedBox(height: 22),
            SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.lime,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
