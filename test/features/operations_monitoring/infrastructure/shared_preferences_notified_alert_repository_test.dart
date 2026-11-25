import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/preferences/shared_preferences_notified_alert_repository.dart';

const _ranchA = 'A1111111-1111-4111-8111-111111111111';
const _ranchB = 'b2222222-2222-4222-8222-222222222222';

void main() {
  group('SharedPreferencesNotifiedAlertRepository', () {
    test('stores announced IDs per ranch in recorded order', () async {
      final values = <String, String>{};
      final repository = _repository(values);

      await repository.write(_ranchA, ['first', 'second']);
      await repository.write(_ranchB, ['other']);

      expect(await repository.read(_ranchA), ['first', 'second']);
      expect(await repository.read(_ranchB), ['other']);
      expect(values.keys, hasLength(2));
    });

    test('reads nothing for a ranch that has no stored IDs', () async {
      expect(await _repository({}).read(_ranchA), isEmpty);
    });

    test('uses one key for a ranch regardless of ID casing', () async {
      final values = <String, String>{};
      final repository = _repository(values);

      await repository.write(_ranchA, ['first']);

      expect(await repository.read(_ranchA.toLowerCase()), ['first']);
      expect(values.keys.single, endsWith(_ranchA.toLowerCase()));
    });
  });
}

SharedPreferencesNotifiedAlertRepository _repository(
  Map<String, String> values,
) => SharedPreferencesNotifiedAlertRepository.withAccess(
  readString: (key) async => values[key],
  writeString: (key, value) async {
    values[key] = value;
  },
);
