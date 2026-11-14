import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_search.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/edge_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/infrastructure/repositories/rest_edge_alert_repository.dart';

import '../../../support/fake_alert_repository.dart';

const _ranchId = 'a1111111-1111-4111-8111-111111111111';
const _otherRanchId = 'b2222222-2222-4222-8222-222222222222';

void main() {
  group('RestEdgeAlertRepository', () {
    test(
      'uses the authorized ranch alert read contract without acknowledging',
      () async {
        final alerts = FakeAlertRepository()
          ..pageResult = _page(1, 20, 21, [_alert(_ranchId)]);
        final repository = RestEdgeAlertRepository(alerts: alerts);

        final result = await repository.page(_ranchId, 1);

        expect(repository.isConfigured, isTrue);
        expect(alerts.requests.single.ranchId, _ranchId);
        expect(
          alerts.requests.single.query,
          const AlertSearch(page: 1, pageSize: 20),
        );
        expect(alerts.acknowledgements, isEmpty);
        expect(result.totalCount, 21);
        expect(result.items.single.alertId, _alert(_ranchId).alertId);
        expect(
          result.items.single.receivedAt,
          DateTime.utc(2026, 1, 1, 0, 0, 1),
        );
      },
    );

    test(
      'fails closed when the returned tenant does not match the request',
      () async {
        final alerts = FakeAlertRepository()
          ..pageResult = _page(1, 20, 1, [_alert(_otherRanchId)]);
        final repository = RestEdgeAlertRepository(alerts: alerts);

        await expectLater(
          repository.page(_ranchId, 1),
          throwsA(
            isA<MonitoringFailure>().having(
              (failure) => failure.code,
              'code',
              MonitoringFailureCode.invalidResponse,
            ),
          ),
        );
        expect(alerts.acknowledgements, isEmpty);
      },
    );

    test('rejects a mismatched backend paging envelope', () async {
      final alerts = FakeAlertRepository()
        ..pageResult = _page(2, 20, 1, [_alert(_ranchId)]);
      final repository = RestEdgeAlertRepository(alerts: alerts);

      await expectLater(
        repository.page(_ranchId, 1),
        throwsA(
          isA<MonitoringFailure>().having(
            (failure) => failure.code,
            'code',
            MonitoringFailureCode.invalidResponse,
          ),
        ),
      );
    });

    test(
      'rejects an invalid page before calling the backend adapter',
      () async {
        final alerts = FakeAlertRepository();
        final repository = RestEdgeAlertRepository(alerts: alerts);

        await expectLater(
          repository.page(_ranchId, 0),
          throwsA(
            isA<MonitoringFailure>().having(
              (failure) => failure.code,
              'code',
              MonitoringFailureCode.invalidSearch,
            ),
          ),
        );
        expect(alerts.requests, isEmpty);
      },
    );
  });
}

RanchAlert _alert(String ranchId) => syntheticRanchAlert(
  ranchId: ranchId,
  alertId: 'a8888888-8888-4888-8888-888888888888',
);

AlertPage _page(
  int page,
  int pageSize,
  int totalCount,
  List<RanchAlert> items,
) => AlertPage(
  page: page,
  pageSize: pageSize,
  totalCount: totalCount,
  items: items,
);
