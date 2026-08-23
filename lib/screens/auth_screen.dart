import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  bool obscurePassword = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.view == AuthView.confirm && email.text.isEmpty) {
          email.text = controller.pendingEmail;
        }
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.navy,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            color: AppColors.lime,
                            size: 34,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        _title(controller.view),
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 9),
                      Text(
                        _subtitle(controller.view),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 28),
                      if (controller.error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEDED),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            controller.error!,
                            style: const TextStyle(
                              color: Color(0xFF8B3333),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (controller.view != AuthView.confirm) ...[
                        TextField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: _decoration(
                            'Email address',
                            Icons.mail_outline_rounded,
                          ),
                        ),
                        const SizedBox(height: 13),
                        TextField(
                          controller: password,
                          obscureText: obscurePassword,
                          autofillHints: controller.view == AuthView.signIn
                              ? const [AutofillHints.password]
                              : const [AutofillHints.newPassword],
                          decoration:
                              _decoration(
                                'Password',
                                Icons.lock_outline_rounded,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => obscurePassword = !obscurePassword,
                                  ),
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                        ),
                      ] else ...[
                        TextField(
                          controller: code,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            letterSpacing: 7,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: _decoration(
                            'Verification code',
                            Icons.verified_user_outlined,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed: controller.busy
                              ? null
                              : () => _submit(controller),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: controller.busy
                              ? const SizedBox.square(
                                  dimension: 19,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_button(controller.view)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: controller.busy
                            ? null
                            : () => controller.show(
                                controller.view == AuthView.signIn
                                    ? AuthView.signUp
                                    : AuthView.signIn,
                              ),
                        child: Text(
                          controller.view == AuthView.signIn
                              ? 'New rider? Create a secure account'
                              : 'Already registered? Sign in',
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            size: 14,
                            color: AppColors.muted,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Protected by AWS Cognito',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit(AuthController controller) async {
    await switch (controller.view) {
      AuthView.signIn => controller.signIn(email.text, password.text),
      AuthView.signUp => controller.signUp(email.text, password.text),
      AuthView.confirm => controller.confirm(code.text),
    };
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.outline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.outline),
    ),
  );

  String _title(AuthView view) => switch (view) {
    AuthView.signIn => 'Welcome back',
    AuthView.signUp => 'Create your account',
    AuthView.confirm => 'Verify your email',
  };

  String _subtitle(AuthView view) => switch (view) {
    AuthView.signIn =>
      'Sign in to start protected rides and share safely with your guardian circle.',
    AuthView.signUp =>
      'Your rides and location are private and tied to your verified identity.',
    AuthView.confirm =>
      'Enter the verification code AWS sent to ${widget.controller.pendingEmail}.',
  };

  String _button(AuthView view) => switch (view) {
    AuthView.signIn => 'Sign in securely',
    AuthView.signUp => 'Create account',
    AuthView.confirm => 'Verify account',
  };
}
