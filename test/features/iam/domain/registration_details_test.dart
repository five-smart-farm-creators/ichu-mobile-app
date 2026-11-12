import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/registration_details.dart';

void main() {
  test('only backend-supported self-registration roles are accepted', () {
    expect(
      const RegistrationDetails(role: AccountRole.veterinarian).isValid,
      isTrue,
    );
    expect(
      const RegistrationDetails(role: AccountRole.fieldOperator).isValid,
      isFalse,
    );
    expect(
      const RegistrationDetails(role: AccountRole.ranchManager).isValid,
      isFalse,
    );
    expect(
      const RegistrationDetails(
        role: AccountRole.ranchManager,
        ranch: RanchRegistration(
          name: 'Test ranch',
          region: 'Test region',
          district: 'Test district',
          estimatedHeadCount: 0,
        ),
      ).isValid,
      isTrue,
    );
  });

  test(
    'ranch fields use backend bounds and the request Int32 representation',
    () {
      RanchRegistration details({
        String? name,
        String? region,
        String? district,
        int count = 0,
      }) => RanchRegistration(
        name: name ?? 'Test ranch',
        region: region ?? 'Test region',
        district: district ?? 'Test district',
        estimatedHeadCount: count,
      );
      expect(details(name: ' ' * 3).isValid, isFalse);
      expect(details(name: 'n' * 160).isValid, isTrue);
      expect(details(name: 'n' * 161).isValid, isFalse);
      expect(details(region: '').isValid, isFalse);
      expect(details(region: 'r' * 120).isValid, isTrue);
      expect(details(region: 'r' * 121).isValid, isFalse);
      expect(details(district: 'd' * 121).isValid, isFalse);
      expect(details(count: -1).isValid, isFalse);
      expect(details(count: 2147483647).isValid, isTrue);
      expect(details(count: 2147483648).isValid, isFalse);
    },
  );
}
