import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/domain/services/credential_rules.dart';

void main() {
  test(
    'email accepts normal addresses and trims only surrounding whitespace',
    () {
      expect(CredentialRules.validEmail('user@example.test'), isTrue);
      expect(CredentialRules.validEmail(' user@example.test '), isTrue);
      expect(CredentialRules.validEmail(''), isFalse);
      expect(CredentialRules.validEmail('user example.test'), isFalse);
      expect(CredentialRules.validEmail('user@ example.test'), isFalse);
      expect(CredentialRules.validEmail('user@@example.test'), isFalse);
      expect(CredentialRules.validEmail('${'a' * 110}@example.test'), isFalse);
    },
  );

  test('password bounds count exact input without trimming', () {
    expect(CredentialRules.validPassword('short'), isFalse);
    expect(CredentialRules.validPassword('a' * 8), isTrue);
    expect(CredentialRules.validPassword('a' * 128), isTrue);
    expect(CredentialRules.validPassword('a' * 129), isFalse);
    expect(CredentialRules.validPassword(' value  '), isTrue);
  });
}
