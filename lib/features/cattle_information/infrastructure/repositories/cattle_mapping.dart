import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_date.dart';
import '../../domain/model/cattle_failure.dart';

/// Strictly maps the implemented Cattle Information read resources.
abstract final class CattleMapping {
  static List<Cattle> cattleListFromPayload(
    Object? payload, {
    required String ranchId,
    required int maximumCount,
  }) {
    if (payload is! List<Object?> || payload.length > maximumCount) {
      _invalidResponse();
    }

    final seenIds = <String>{};
    final cattle = payload
        .map((item) {
          final animal = _cattleFromPayload(item, expectedRanchId: ranchId);
          if (!seenIds.add(animal.id.toLowerCase())) _invalidResponse();
          return animal;
        })
        .toList(growable: false);
    return List<Cattle>.unmodifiable(cattle);
  }

  /// Write responses return one animal; the repository checks it against the request.
  static Cattle cattleFromPayload(
    Object? payload, {
    required String ranchId,
    String? cattleId,
  }) => _cattleFromPayload(
    payload,
    expectedRanchId: ranchId,
    expectedCattleId: cattleId,
  );

  static CattleProfile profileFromPayload(
    Object? payload, {
    required String ranchId,
    required String cattleId,
  }) {
    final dto = _object(payload);
    final cattle = _cattleFromPayload(
      dto['cattle'],
      expectedRanchId: ranchId,
      expectedCattleId: cattleId,
    );
    final deviceDto = _object(dto['device']);
    final isAvailable = deviceDto['isAvailable'];
    if (isAvailable is! bool) _invalidResponse();

    final collarId = _nullableUuid(deviceDto['collarId']);
    final lastReadingReceivedAt = _nullableTimestamp(
      deviceDto['lastReadingReceivedAt'],
    );
    if ((!isAvailable && (collarId != null || lastReadingReceivedAt != null)) ||
        (collarId == null && lastReadingReceivedAt != null)) {
      _invalidResponse();
    }

    return CattleProfile(
      cattle: cattle,
      device: CattleDevice(
        isAvailable: isAvailable,
        collarId: collarId,
        lastReadingReceivedAt: lastReadingReceivedAt,
      ),
    );
  }

  static Cattle _cattleFromPayload(
    Object? payload, {
    required String expectedRanchId,
    String? expectedCattleId,
  }) {
    final dto = _object(payload);
    final id = _requiredUuid(dto, 'id');
    final ranchId = _requiredUuid(dto, 'ranchId');
    final version = _requiredUuid(dto, 'version');
    if (!_sameUuid(ranchId, expectedRanchId) ||
        (expectedCattleId != null && !_sameUuid(id, expectedCattleId))) {
      _invalidResponse();
    }

    final earTag = _requiredString(dto, 'earTag');
    if (earTag != earTag.trim() || earTag.isEmpty || earTag.length > 30) {
      _invalidResponse();
    }

    final status = _enumValue(
      _requiredString(dto, 'status'),
      const <String, CattleStatus>{
        'Active': CattleStatus.active,
        'Inactive': CattleStatus.inactive,
      },
    );
    final exitReason =
        _nullableEnumValue(dto['exitReason'], const <String, CattleExitReason>{
          'Death': CattleExitReason.death,
          'Sale': CattleExitReason.sale,
          'Theft': CattleExitReason.theft,
          'Culling': CattleExitReason.culling,
        });
    final exitDate = _nullableDate(dto['exitDate']);
    final birthDate = _requiredDate(dto, 'birthDate');
    if ((status == CattleStatus.active &&
            (exitReason != null || exitDate != null)) ||
        (status == CattleStatus.inactive &&
            (exitReason == null ||
                exitDate == null ||
                exitDate.compareTo(birthDate) < 0))) {
      _invalidResponse();
    }

    final periodsPayload = dto['stagePeriods'];
    if (periodsPayload is! List<Object?> || periodsPayload.isEmpty) {
      _invalidResponse();
    }
    final periodIds = <String>{};
    final periods = periodsPayload
        .map((value) {
          final period = _object(value);
          final periodId = _requiredUuid(period, 'id');
          if (!periodIds.add(periodId.toLowerCase())) _invalidResponse();
          final validFrom = _requiredDate(period, 'validFrom');
          final validTo = _nullableDate(period['validTo']);
          if (validFrom.compareTo(birthDate) < 0 ||
              (validTo != null && validTo.compareTo(validFrom) < 0)) {
            _invalidResponse();
          }
          return CattleStagePeriod(
            id: periodId,
            stage: _enumValue(
              _requiredString(period, 'lifeStage'),
              const <String, CattleStage>{
                'Calf': CattleStage.calf,
                'Heifer': CattleStage.heifer,
                'MilkingCow': CattleStage.milkingCow,
                'FatteningBull': CattleStage.fatteningBull,
              },
            ),
            validFrom: validFrom,
            validTo: validTo,
          );
        })
        .toList(growable: false);

    final openPeriods = periods.where((period) => period.validTo == null);
    if (status == CattleStatus.active) {
      if (openPeriods.length != 1 ||
          openPeriods.single.stage !=
              _enumValue(
                _requiredString(dto, 'currentStage'),
                const <String, CattleStage>{
                  'Calf': CattleStage.calf,
                  'Heifer': CattleStage.heifer,
                  'MilkingCow': CattleStage.milkingCow,
                  'FatteningBull': CattleStage.fatteningBull,
                },
              )) {
        _invalidResponse();
      }
    } else {
      final currentStage = _enumValue(
        _requiredString(dto, 'currentStage'),
        const <String, CattleStage>{
          'Calf': CattleStage.calf,
          'Heifer': CattleStage.heifer,
          'MilkingCow': CattleStage.milkingCow,
          'FatteningBull': CattleStage.fatteningBull,
        },
      );
      if (openPeriods.isNotEmpty ||
          !periods.any(
            (period) =>
                period.stage == currentStage && period.validTo == exitDate,
          )) {
        _invalidResponse();
      }
    }

    return Cattle(
      id: id,
      ranchId: ranchId,
      earTag: earTag,
      breed:
          _enumValue(_requiredString(dto, 'breed'), const <String, CattleBreed>{
            'BrownSwiss': CattleBreed.brownSwiss,
            'Fleckvieh': CattleBreed.fleckvieh,
            'Criollo': CattleBreed.criollo,
            'Crossbred': CattleBreed.crossbred,
          }),
      sex: _enumValue(_requiredString(dto, 'sex'), const <String, CattleSex>{
        'Female': CattleSex.female,
        'Male': CattleSex.male,
      }),
      birthDate: birthDate,
      currentStage: _enumValue(
        _requiredString(dto, 'currentStage'),
        const <String, CattleStage>{
          'Calf': CattleStage.calf,
          'Heifer': CattleStage.heifer,
          'MilkingCow': CattleStage.milkingCow,
          'FatteningBull': CattleStage.fatteningBull,
        },
      ),
      status: status,
      version: version,
      stagePeriods: periods,
      exitReason: exitReason,
      exitDate: exitDate,
    );
  }

  static String _requiredUuid(Map<String, dynamic> dto, String key) {
    final value = _requiredString(dto, key);
    if (!_isUuid(value) || _isZeroUuid(value)) _invalidResponse();
    return value;
  }

  static String? _nullableUuid(Object? value) {
    if (value == null) return null;
    if (value is! String || !_isUuid(value) || _isZeroUuid(value)) {
      _invalidResponse();
    }
    return value;
  }

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  static bool _isZeroUuid(String value) =>
      value.replaceAll('-', '').replaceAll('0', '').isEmpty;

  static bool _sameUuid(String left, String right) =>
      _isUuid(right) && left.toLowerCase() == right.toLowerCase();

  static CattleDate _requiredDate(Map<String, dynamic> dto, String key) =>
      _date(dto[key]);

  static CattleDate? _nullableDate(Object? value) =>
      value == null ? null : _date(value);

  static CattleDate _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      _invalidResponse();
    }
    final date = CattleDate(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
      int.parse(value.substring(8, 10)),
    );
    if (!date.isValid) _invalidResponse();
    return date;
  }

  static DateTime? _nullableTimestamp(Object? value) {
    if (value == null) return null;
    if (value is! String) _invalidResponse();
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,7}))?(?:Z|[+-](\d{2}):(\d{2}))$',
    ).firstMatch(value);
    if (match == null) _invalidResponse();
    final date = CattleDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final offsetHour = int.parse(match.group(8) ?? '0');
    final offsetMinute = int.parse(match.group(9) ?? '0');
    if (!date.isValid ||
        hour > 23 ||
        minute > 59 ||
        second > 59 ||
        offsetHour > 14 ||
        offsetMinute > 59 ||
        (offsetHour == 14 && offsetMinute != 0)) {
      _invalidResponse();
    }
    final timestamp = DateTime.tryParse(value);
    if (timestamp == null) _invalidResponse();
    return timestamp.toUtc();
  }

  static String _requiredString(Map<String, dynamic> dto, String key) {
    final value = dto[key];
    if (value is! String || value.trim().isEmpty) _invalidResponse();
    return value;
  }

  static T _enumValue<T>(String value, Map<String, T> values) {
    final mapped = values[value];
    if (mapped == null) _invalidResponse();
    return mapped;
  }

  static T? _nullableEnumValue<T>(Object? value, Map<String, T> values) {
    if (value == null) return null;
    if (value is! String) _invalidResponse();
    return _enumValue(value, values);
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) _invalidResponse();
    return value;
  }

  static Never _invalidResponse() =>
      throw const CattleFailure(CattleFailureCode.invalidResponse);
}
