import '../model/field_record.dart';

/// Looks up an exact cattle ear tag in an authorized account/ranch scope.
abstract interface class FieldCattleDirectory {
  Future<List<FieldCattleOption>> findByExactEarTag({
    required String accountId,
    required String ranchId,
    required String earTag,
  });
}
