import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/professional_profile.dart';

void main() {
  ProfessionalProfile profile({
    String specialty = 'Bovine health',
    String license = 'CMVP-123',
    int years = 0,
  }) => ProfessionalProfile(
    specialty: specialty,
    licenseNumber: license,
    yearsOfExperience: years,
  );
  test(
    'profile values follow backend bounds without a license regex or specialty list',
    () {
      expect(profile().isValid, isTrue);
      expect(profile(specialty: ' ').isValid, isFalse);
      expect(profile(specialty: 's' * 120).isValid, isTrue);
      expect(profile(specialty: 's' * 121).isValid, isFalse);
      expect(profile(license: ' ').isValid, isFalse);
      expect(profile(license: 'l' * 80).isValid, isTrue);
      expect(profile(license: 'l' * 81).isValid, isFalse);
      expect(profile(license: 'a / 123').isValid, isTrue);
      expect(profile(years: -1).isValid, isFalse);
      expect(profile(years: 2147483647).isValid, isTrue);
      expect(profile(years: 2147483648).isValid, isFalse);
    },
  );
  test(
    'normalization matches the backend without changing the input object',
    () {
      final original = profile(
        specialty: ' Bovine health ',
        license: ' cmvp-123 ',
        years: 5,
      );
      final normalized = original.normalized();
      expect(normalized.specialty, 'Bovine health');
      expect(normalized.licenseNumber, 'CMVP-123');
      expect(normalized.yearsOfExperience, 5);
      expect(original.licenseNumber, ' cmvp-123 ');
    },
  );

  test('immutable profile snapshots compare by their field values', () {
    final first = profile();
    final second = profile();
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first, isNot(profile(years: 1)));
  });
}
