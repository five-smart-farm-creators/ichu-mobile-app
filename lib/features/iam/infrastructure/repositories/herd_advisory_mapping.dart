import '../../domain/model/herd_advisory.dart';
import '../../domain/model/herd_advisory_failure.dart';
import '../../domain/model/ranch_access.dart';
import '../../domain/model/ranch_summary.dart';
import 'iam_account_mapping.dart';

/// Validates the ranch and herd-advisory resources returned by IAM.
abstract final class HerdAdvisoryMapping {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static RanchSummary ranchFromPayload(Object? payload) {
    final dto = IamAccountMapping.objectFromPayload(payload);
    final ranchId = _requiredString(dto, 'ranchId');
    if (!_isNonzeroUuid(ranchId)) _invalidResponse();
    return RanchSummary(
      ranchId: ranchId,
      name: _boundedString(dto, 'name', 160),
      region: _boundedString(dto, 'region', 120),
      district: _boundedString(dto, 'district', 120),
    );
  }

  static HerdAdvisory advisoryFromPayload(Object? payload) {
    final dto = IamAccountMapping.objectFromPayload(payload);
    final id = _requiredString(dto, 'id');
    final veterinarianId = _requiredString(dto, 'veterinarianId');
    final ranchId = _requiredString(dto, 'ranchId');
    if (!_isNonzeroUuid(id) ||
        !_isNonzeroUuid(veterinarianId) ||
        !_isNonzeroUuid(ranchId)) {
      _invalidResponse();
    }
    final status = switch (_requiredString(dto, 'status')) {
      'Pending' => HerdAdvisoryStatus.pending,
      'Granted' => HerdAdvisoryStatus.granted,
      'Rejected' => HerdAdvisoryStatus.rejected,
      'Revoked' => HerdAdvisoryStatus.revoked,
      'Expired' => HerdAdvisoryStatus.expired,
      _ => _invalidResponse(),
    };
    final scope = switch (_requiredString(dto, 'scope')) {
      'Read' => AccessScope.read,
      'ClinicalWrite' => AccessScope.clinicalWrite,
      _ => _invalidResponse(),
    };
    return HerdAdvisory(
      id: id,
      veterinarianId: veterinarianId,
      ranchId: ranchId,
      reason: _boundedString(dto, 'reason', 1000),
      status: status,
      scope: scope,
      requestedAt: _dateTime(dto, 'requestedAt')!,
      grantedAt: _dateTime(dto, 'grantedAt'),
      expiresAt: _dateTime(dto, 'expiresAt'),
      endedAt: _dateTime(dto, 'endedAt'),
      veterinarianProfile: IamAccountMapping.optionalProfileFromPayload(dto),
    );
  }

  static List<HerdAdvisory> advisoriesFromPayload(Object? payload) {
    if (payload is! List<Object?>) _invalidResponse();
    final entries = payload.map(advisoryFromPayload).toList(growable: false);
    final ids = <String>{};
    for (final advisory in entries) {
      if (!ids.add(advisory.id.toLowerCase()) ||
          advisory.ranchId.toLowerCase() !=
              entries.first.ranchId.toLowerCase()) {
        _invalidResponse();
      }
    }
    return List<HerdAdvisory>.unmodifiable(entries);
  }

  static String _boundedString(
    Map<String, dynamic> dto,
    String key,
    int maximumLength,
  ) {
    final value = _requiredString(dto, key).trim();
    if (value.isEmpty || value.length > maximumLength) _invalidResponse();
    return value;
  }

  static String _requiredString(Map<String, dynamic> dto, String key) {
    final value = dto[key];
    if (value is! String || value.trim().isEmpty) _invalidResponse();
    return value;
  }

  static DateTime? _dateTime(Map<String, dynamic> dto, String key) {
    final value = dto[key];
    if (value == null) return null;
    if (value is! String) _invalidResponse();
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,7})?(?:Z|[+-](\d{2}):(\d{2}))$',
    ).firstMatch(value);
    if (match == null) _invalidResponse();
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final offsetHour = int.parse(match.group(7) ?? '0');
    final offsetMinute = int.parse(match.group(8) ?? '0');
    if (year == 0 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        hour > 23 ||
        minute > 59 ||
        second > 59 ||
        offsetHour > 14 ||
        offsetMinute > 59 ||
        (offsetHour == 14 && offsetMinute != 0)) {
      _invalidResponse();
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) _invalidResponse();
    return parsed;
  }

  static bool _isNonzeroUuid(String value) =>
      _uuidPattern.hasMatch(value) &&
      value.replaceAll('-', '').replaceAll('0', '').isNotEmpty;

  static Never _invalidResponse() =>
      throw const HerdAdvisoryFailure(HerdAdvisoryFailureCode.invalidResponse);
}
