import 'package:flutter/material.dart';

import 'controllers/auth_controller.dart';
import 'controllers/ride_controller.dart';
import 'screens/app_shell.dart';
import 'screens/auth_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RideGuardianApp());
}

class RideGuardianApp extends StatefulWidget {
  const RideGuardianApp({super.key, this.authenticationEnabled = true});

  final bool authenticationEnabled;

  @override
  State<RideGuardianApp> createState() => _RideGuardianAppState();
}

class _RideGuardianAppState extends State<RideGuardianApp> {
  late final RideController controller;
  late final AuthController authController;
  bool sessionApplied = false;

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
      await controller.initialize();
    } else if (!authController.signedIn && sessionApplied) {
      sessionApplied = false;
      controller.backend.setTokenProvider(null);
    }
  }

  @override
  void dispose() {
    controller.dispose();
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
                if (authController.initializing) {
                  return const _SplashScreen();
                }
                if (!authController.signedIn) {
                  return AuthScreen(controller: authController);
                }
                return AppShell(
                  controller: controller,
                  username: authController.username,
                  onSignOut: () async {
                    await controller.stopRide();
                    await authController.signOut();
                  },
                );
              },
            )
          : AppShell(controller: controller),
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
