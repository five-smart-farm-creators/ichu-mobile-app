import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/herd_advisory.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/herd_advisory_failure.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/infrastructure/repositories/herd_advisory_mapping.dart';

const _ranchId = '223e4567-e89b-12d3-a456-426614174000';
const _otherRanchId = '423e4567-e89b-12d3-a456-426614174000';
const _advisoryId = '323e4567-e89b-12d3-a456-426614174000';
const _veterinarianId = '523e4567-e89b-12d3-a456-426614174000';

void main() {
  group('HerdAdvisoryMapping', () {
    test('maps ranch summaries without retaining access codes', () {
      final ranch = HerdAdvisoryMapping.ranchFromPayload(<String, Object?>{
        'ranchId': _ranchId,
        'name': 'North ranch',
        'region': 'Cusco',
        'district': 'Anta',
        'accessCode': 'synthetic-private-code',
      });

      expect(ranch.ranchId, _ranchId);
      expect(ranch.name, 'North ranch');
      expect(ranch.region, 'Cusco');
      expect(ranch.district, 'Anta');
      expect(ranch.toString(), isNot(contains('synthetic-private-code')));
    });

    test('maps advisory status, scope, profile, and UTC instants', () {
      final advisory = HerdAdvisoryMapping.advisoryFromPayload(
        _advisoryPayload()
          ..['status'] = 'Granted'
          ..['scope'] = 'ClinicalWrite'
          ..['grantedAt'] = '2026-11-13T12:30:00-05:00'
          ..['expiresAt'] = '2027-01-02T23:59:59Z'
          ..['profile'] = <String, Object?>{
            'specialty': 'Bovine health',
            'licenseNumber': 'CMVP-123',
            'yearsOfExperience': 5,
          },
      );

      expect(advisory.id, _advisoryId);
      expect(advisory.ranchId, _ranchId);
      expect(advisory.status, HerdAdvisoryStatus.granted);
      expect(advisory.scope, AccessScope.clinicalWrite);
      expect(advisory.requestedAt, DateTime.utc(2026, 11, 13, 12));
      expect(advisory.grantedAt, DateTime.parse('2026-11-13T12:30:00-05:00'));
      expect(advisory.grantedAt!.isUtc, isTrue);
      expect(advisory.expiresAt, DateTime.utc(2027, 1, 2, 23, 59, 59));
      expect(advisory.veterinarianProfile?.licenseNumber, 'CMVP-123');
    });

    test('returns an immutable empty advisory list', () {
      final advisories = HerdAdvisoryMapping.advisoriesFromPayload(
        const <Object?>[],
      );

      expect(advisories, isEmpty);
      expect(() => advisories.clear(), throwsUnsupportedError);
    });

    test('rejects unknown scopes, duplicate IDs, and mixed ranch history', () {
      expect(
        () => HerdAdvisoryMapping.advisoryFromPayload(
          _advisoryPayload()..['scope'] = 'Manage',
        ),
        throwsA(isA<HerdAdvisoryFailure>()),
      );
      expect(
        () => HerdAdvisoryMapping.advisoriesFromPayload([
          _advisoryPayload(),
          _advisoryPayload()..['id'] = _advisoryId.toUpperCase(),
        ]),
        throwsA(isA<HerdAdvisoryFailure>()),
      );
      expect(
        () => HerdAdvisoryMapping.advisoriesFromPayload([
          _advisoryPayload(),
          _advisoryPayload()..['ranchId'] = _otherRanchId,
        ]),
        throwsA(isA<HerdAdvisoryFailure>()),
      );
    });

    test('rejects malformed calendar dates and ambiguous timestamps', () {
      for (final timestamp in <Object?>[
        '2026-11-31T12:00:00Z',
        '2026-13-01T12:00:00Z',
        '2026-11-13T24:00:00Z',
        '2026-11-13T12:00:00',
        '2026-11-13T12:00:00+14:01',
      ]) {
        expect(
          () => HerdAdvisoryMapping.advisoryFromPayload(
            _advisoryPayload()..['requestedAt'] = timestamp,
          ),
          throwsA(isA<HerdAdvisoryFailure>()),
          reason: '$timestamp must not map to a normalized instant.',
        );
      }
    });
  });
}

Map<String, Object?> _advisoryPayload() => <String, Object?>{
  'id': _advisoryId,
  'veterinarianId': _veterinarianId,
  'ranchId': _ranchId,
  'reason': 'Herd health review',
  'status': 'Pending',
  'scope': 'Read',
  'requestedAt': '2026-11-13T12:00:00Z',
  'grantedAt': null,
  'expiresAt': null,
  'endedAt': null,
};
