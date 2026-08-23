import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import '../config/aws_config.dart';

class AuthService {
  Future<void> configure() async {
    if (Amplify.isConfigured) return;
    await Amplify.addPlugin(AmplifyAuthCognito());
    await Amplify.configure(AwsConfig.amplifyConfiguration);
  }

  Future<bool> isSignedIn() async {
    final session = await Amplify.Auth.fetchAuthSession();
    return session.isSignedIn;
  }

  Future<String?> accessToken() async {
    final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
    if (!session.isSignedIn) return null;
    return session.userPoolTokensResult.value.idToken.raw;
  }

  Future<String?> currentUsername() async {
    if (!await isSignedIn()) return null;
    final attributes = await Amplify.Auth.fetchUserAttributes();
    for (final attribute in attributes) {
      if (attribute.userAttributeKey == AuthUserAttributeKey.email) {
        return attribute.value;
      }
    }
    return (await Amplify.Auth.getCurrentUser()).username;
  }

  Future<bool> signIn(String email, String password) async {
    final result = await Amplify.Auth.signIn(
      username: email.trim().toLowerCase(),
      password: password,
    );
    return result.isSignedIn;
  }

  Future<bool> signUp(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    final result = await Amplify.Auth.signUp(
      username: normalizedEmail,
      password: password,
      options: SignUpOptions(
        userAttributes: {AuthUserAttributeKey.email: normalizedEmail},
      ),
    );
    return result.isSignUpComplete;
  }

  Future<bool> confirmSignUp(String email, String code) async {
    final result = await Amplify.Auth.confirmSignUp(
      username: email.trim().toLowerCase(),
      confirmationCode: code.trim(),
    );
    return result.isSignUpComplete;
  }

  Future<void> signOut() async {
    await Amplify.Auth.signOut();
  }
}
