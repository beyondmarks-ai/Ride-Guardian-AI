import 'package:flutter/material.dart';

import '../config/project_identity.dart';
import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.controller,
    this.guardian = false,
    this.onChangeRole,
  });

  final AuthController controller;
  final bool guardian;
  final VoidCallback? onChangeRole;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final phone = TextEditingController(text: '+91 ');
  final smsCode = TextEditingController();
  bool obscurePassword = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    phone.dispose();
    smsCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.view == AuthView.verifyEmail && email.text.isEmpty) {
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
                      if (widget.onChangeRole != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: controller.busy
                                ? null
                                : widget.onChangeRole,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Change role'),
                          ),
                        ),
                      Text(
                        widget.guardian ? 'GUARDIAN ACCOUNT' : 'RIDER ACCOUNT',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 14),
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
                        widget.guardian && controller.view == AuthView.signIn
                            ? 'Sign in to connect with a rider and open your guardian dashboard.'
                            : _subtitle(controller.view),
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
                      if (controller.message != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9F4F0),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            controller.message!,
                            style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (controller.view == AuthView.signIn ||
                          controller.view == AuthView.signUp) ...[
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
                      ] else if (controller.view == AuthView.phoneSignIn) ...[
                        TextField(
                          controller: phone,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: _decoration(
                            'Mobile number with country code',
                            Icons.phone_android_rounded,
                          ),
                        ),
                      ] else if (controller.view == AuthView.phoneCode) ...[
                        TextField(
                          controller: smsCode,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          decoration: _decoration(
                            '6-digit one-time code',
                            Icons.password_rounded,
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: AppColors.outline),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Color(0xFFE0F3EC),
                                child: Icon(
                                  Icons.mark_email_read_outlined,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Open the Firebase verification link in your email, then return to the app.',
                                  style: TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 13,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
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
                      if (controller.view == AuthView.signIn ||
                          controller.view == AuthView.signUp) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: controller.busy
                              ? null
                              : () => controller.show(AuthView.phoneSignIn),
                          icon: const Icon(Icons.phone_android_rounded),
                          label: const Text('Continue with phone number'),
                        ),
                      ],
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: controller.busy
                            ? null
                            : controller.view == AuthView.verifyEmail
                            ? controller.resendEmailVerification
                            : controller.view == AuthView.phoneCode
                            ? () => controller.sendPhoneCode(phone.text)
                            : controller.view == AuthView.phoneSignIn
                            ? () => controller.show(AuthView.signIn)
                            : () => controller.show(
                                controller.view == AuthView.signIn
                                    ? AuthView.signUp
                                    : AuthView.signIn,
                              ),
                        child: Text(
                          controller.view == AuthView.verifyEmail
                              ? 'Resend verification email'
                              : controller.view == AuthView.phoneCode
                              ? 'Resend one-time code'
                              : controller.view == AuthView.phoneSignIn
                              ? 'Use email and password instead'
                              : controller.view == AuthView.signIn
                              ? widget.guardian
                                    ? 'New guardian? Create a secure account'
                                    : 'New rider? Create a secure account'
                              : 'Already registered? Sign in',
                        ),
                      ),
                      if (controller.view == AuthView.verifyEmail ||
                          controller.view == AuthView.phoneCode)
                        TextButton(
                          onPressed: controller.busy
                              ? null
                              : () => controller.show(AuthView.signIn),
                          child: const Text('Use a different account'),
                        ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9F4F0),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Column(
                          children: [
                            Text(
                              ProjectIdentity.college,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.primaryDark,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '${ProjectIdentity.department} - Guided by ${ProjectIdentity.guide}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 10,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
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
                            'Protected by Firebase Authentication',
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
      AuthView.verifyEmail => controller.checkEmailVerification(),
      AuthView.phoneSignIn => controller.sendPhoneCode(phone.text),
      AuthView.phoneCode => controller.verifyPhoneCode(smsCode.text),
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
    AuthView.verifyEmail => 'Verify your email',
    AuthView.phoneSignIn => 'Continue with your phone',
    AuthView.phoneCode => 'Enter your secure code',
  };

  String _subtitle(AuthView view) => switch (view) {
    AuthView.signIn =>
      'Sign in to start protected rides and share safely with your guardian circle.',
    AuthView.signUp =>
      'Your rides and location are private and tied to your verified identity.',
    AuthView.verifyEmail =>
      'A secure link was sent to ${widget.controller.pendingEmail}.',
    AuthView.phoneSignIn =>
      'Firebase will verify your mobile number with a one-time SMS code.',
    AuthView.phoneCode =>
      'Enter the code sent to ${widget.controller.pendingPhone}.',
  };

  String _button(AuthView view) => switch (view) {
    AuthView.signIn => 'Sign in securely',
    AuthView.signUp => 'Create account',
    AuthView.verifyEmail => 'I have verified my email',
    AuthView.phoneSignIn => 'Send one-time code',
    AuthView.phoneCode => 'Verify and sign in',
  };
}
