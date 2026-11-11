import 'package:flutter/material.dart';
import '../config/project_identity.dart';
import '../theme/app_theme.dart';

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key, required this.onSelect});
  final ValueChanged<bool> onSelect;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.shield_rounded,
                  size: 64,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome to RideGuardian',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'How will you use the app?',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _role(
                  context,
                  false,
                  Icons.two_wheeler,
                  'I am a rider',
                  'Check your helmet, start protected rides and share with your guardian.',
                ),
                const SizedBox(height: 16),
                _role(
                  context,
                  true,
                  Icons.family_restroom,
                  'I am a guardian',
                  'Connect using the rider’s phone number. Follow speed, location, ride history and SOS alerts.',
                ),
                const SizedBox(height: 32),
                const Text(
                  ProjectIdentity.college,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget _role(
    BuildContext context,
    bool guardian,
    IconData icon,
    String title,
    String description,
  ) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => onSelect(guardian),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(icon, size: 38, color: AppColors.primary),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(description, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}
