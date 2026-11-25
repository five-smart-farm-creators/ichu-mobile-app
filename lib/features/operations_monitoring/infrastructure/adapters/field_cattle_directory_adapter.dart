import '../../../cattle_information/application/facades/cattle_lookup_facade.dart';
import '../../domain/model/field_record.dart';
import '../../domain/repositories/field_cattle_directory.dart';

/// Adapts the authorized cattle lookup to the field-record application port.
final class FieldCattleDirectoryAdapter implements FieldCattleDirectory {
  const FieldCattleDirectoryAdapter({required this.lookup});

  final CattleLookupFacade lookup;

  @override
  Future<List<FieldCattleOption>> findByExactEarTag({
    required String accountId,
    required String ranchId,
    required String earTag,
  }) async {
    final results = await lookup.findByExactEarTag(
      accountId: accountId,
      ranchId: ranchId,
      earTag: earTag,
    );
    return List<FieldCattleOption>.unmodifiable(
      results.map(
        (item) => FieldCattleOption(
          cattleId: item.cattleId,
          ranchId: item.ranchId,
          earTag: item.earTag,
        ),
      ),
    );
  }
}
