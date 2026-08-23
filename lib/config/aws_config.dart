abstract final class AwsConfig {
  static const region = 'ap-south-1';
  static const userPoolId = 'ap-south-1_5ftpBlHrJ';
  static const userPoolClientId = '7c21nurv5puncgd6n8prjnngvc';
  static const apiBaseUrl =
      'https://ck2jaupdj5.execute-api.ap-south-1.amazonaws.com/v1';

  static const amplifyConfiguration =
      '''
{
  "UserAgent": "aws-amplify-cli/2.0",
  "Version": "1.0",
  "auth": {
    "plugins": {
      "awsCognitoAuthPlugin": {
        "UserAgent": "aws-amplify-cli/0.1.0",
        "Version": "0.1.0",
        "IdentityManager": {"Default": {}},
        "CognitoUserPool": {
          "Default": {
            "PoolId": "$userPoolId",
            "AppClientId": "$userPoolClientId",
            "Region": "$region"
          }
        },
        "Auth": {
          "Default": {
            "authenticationFlowType": "USER_SRP_AUTH",
            "socialProviders": [],
            "usernameAttributes": ["EMAIL"],
            "signupAttributes": ["EMAIL"],
            "passwordProtectionSettings": {
              "passwordPolicyMinLength": 10,
              "passwordPolicyCharacters": [
                "REQUIRES_LOWERCASE",
                "REQUIRES_UPPERCASE",
                "REQUIRES_NUMBERS"
              ]
            },
            "mfaConfiguration": "OFF",
            "mfaTypes": [],
            "verificationMechanisms": ["EMAIL"]
          }
        }
      }
    }
  }
}
''';
}
