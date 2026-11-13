import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/monitoring_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/latest_telemetry.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/telemetry_history.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/presentation/pages/animal_monitoring_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import 'support/fake_iam_repositories.dart';
import 'support/fake_monitoring_repository.dart';
import 'support/memory_language_preferences.dart';

const _ranchId = '11111111-1111-4111-8111-111111111111';
const _otherRanchId = '22222222-2222-4222-8222-222222222222';
const _cattleId = '33333333-3333-4333-8333-333333333333';
const _otherCattleId = '44444444-4444-4444-8444-444444444444';
const _ranches = <RanchAccess>[
  RanchAccess(
    ranchId: _ranchId,
    scope: AccessScope.read,
    name: 'Selected ranch',
    region: 'Central Region',
    district: 'North District',
  ),
  RanchAccess(
    ranchId: _otherRanchId,
    scope: AccessScope.read,
    name: 'Second ranch',
    region: 'West Region',
    district: 'South District',
  ),
];

void main() {
  for (final language in AppLanguage.values) {
    testWidgets(
      '${language.code} decimal display avoids binary artifacts and preserves extreme magnitudes',
      (tester) async {
        await _withFixture(tester, (fixture) async {
          final time = DateTime.utc(2026, 11, 12);
          fixture.monitoring.latestResult = syntheticLatestTelemetry(
            cattleId: _cattleId,
            bodyTemperature: LatestIndicator.available(
              value: 38.6,
              unit: TelemetryUnit.celsius,
              recordedAt: time,
              isStale: false,
            ),
            activityIndex: LatestIndicator.available(
              value: 1e-300,
              unit: TelemetryUnit.activityIndex,
              recordedAt: time,
              isStale: false,
            ),
            ruminationMinutes: LatestIndicator.available(
              value: 1e300,
              unit: TelemetryUnit.minutes,
              recordedAt: time,
              isStale: false,
            ),
            lastKnownPosition: LastKnownPosition.available(
              latitude: -13.5,
              longitude: -72.1,
              accuracyMeters: 8,
              recordedAt: time,
              isStale: false,
            ),
          );
          await tester.pumpWidget(_app(fixture, _page(fixture)));
          await tester.pumpAndSettle();
          final separator = language == AppLanguage.spanish ? ',' : '.';
          expect(find.text('38${separator}6 °C'), findsOneWidget);
          expect(find.text('-72${separator}1'), findsOneWidget);
          expect(find.textContaining('1E-300'), findsOneWidget);
          expect(find.textContaining('1E300'), findsOneWidget);
          expect(find.textContaining('600000000000001'), findsNothing);
          expect(find.textContaining('099999999999994'), findsNothing);
        }, language: language);
      },
    );
  }
  testWidgets('no selected ranch offers selection without a monitoring read', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      await tester.pumpWidget(_app(fixture, _page(fixture)));
      await tester.pumpAndSettle();
      expect(fixture.monitoring.requests, isEmpty);
      expect(find.byKey(const Key('monitoring-choose-ranch')), findsOneWidget);
      expect(find.byKey(const Key('monitoring-reload')), findsNothing);
      await _tap(tester, find.byKey(const Key('monitoring-choose-ranch')));
      expect(fixture.openRanches, 1);
    }, ranches: const <RanchAccess>[]);
  });

  testWidgets('initial load is visible and resolves a single latest summary', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      final response = Completer<LatestTelemetry>();
      fixture.monitoring.completer = response;
      await tester.pumpWidget(_app(fixture, _page(fixture)));
      await tester.pump();
      expect(fixture.monitoring.requests, hasLength(1));
      expect(fixture.monitoring.requests.single.cattleId, _cattleId);
      expect(find.text(_strings(tester).monitoringLoading), findsOneWidget);
      response.complete(syntheticLatestTelemetry(cattleId: _cattleId));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('monitoring-snapshot')), findsOneWidget);
      expect(fixture.service.status, MonitoringLoadStatus.ready);
    });
  });

  testWidgets('unconfigured integration gives a disabled explicit retry', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      await tester.pumpWidget(_app(fixture, _page(fixture)));
      await tester.pumpAndSettle();
      final strings = _strings(tester);
      expect(fixture.monitoring.requests, isEmpty);
      expect(find.text(strings.monitoringErrorConfiguration), findsOneWidget);
      final reload = find.byKey(const Key('monitoring-reload'));
      expect(tester.widget<OutlinedButton>(reload).onPressed, isNull);
    }, configured: false);
  });

  testWidgets('valid empty summary distinguishes unavailable from zero', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      fixture.monitoring.latestResult = syntheticLatestTelemetry(
        cattleId: _cattleId,
      );
      await tester.pumpWidget(_app(fixture, _page(fixture)));
      await tester.pumpAndSettle();
      final strings = _strings(tester);
      expect(find.byKey(const Key('monitoring-snapshot')), findsOneWidget);
      expect(
        find.text(strings.monitoringIndicatorUnavailable),
        findsNWidgets(3),
      );
      expect(find.text(strings.monitoringPositionUnavailable), findsOneWidget);
      expect(find.textContaining('0 °C'), findsNothing);
      expect(find.text(strings.monitoringErrorNotFound), findsNothing);
      expect(find.text(strings.monitoringNoCapture), findsOneWidget);
    });
  });

  testWidgets(
    'mixed fields preserve units, origin, timestamps and server freshness',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        final evaluated = DateTime.utc(2026, 6, 7, 12, 13, 14);
        fixture.monitoring.latestResult = syntheticLatestTelemetry(
          cattleId: _cattleId,
          evaluatedAt: evaluated,
          bodyTemperature: LatestIndicator.available(
            value: -2.5,
            unit: TelemetryUnit.celsius,
            recordedAt: DateTime.utc(2026, 6, 7, 8, 9, 10),
            isStale: false,
          ),
          activityIndex: LatestIndicator.available(
            value: 4.25,
            unit: TelemetryUnit.activityIndex,
            recordedAt: DateTime.utc(2026, 6, 6, 7, 8, 9),
            isStale: true,
          ),
          lastKnownPosition: LastKnownPosition.available(
            latitude: 12.5,
            longitude: -43.25,
            accuracyMeters: 3.5,
            recordedAt: DateTime.utc(2026, 6, 5, 6, 7, 8),
            isStale: false,
          ),
        );
        await tester.pumpWidget(_app(fixture, _page(fixture)));
        await tester.pumpAndSettle();
        final strings = _strings(tester);
        expect(find.textContaining('-2.5'), findsOneWidget);
        expect(
          find.textContaining(strings.monitoringUnitCelsius),
          findsOneWidget,
        );
        expect(find.textContaining('4.25'), findsOneWidget);
        expect(
          find.text('4.25 ${strings.monitoringUnitIndex}'),
          findsOneWidget,
        );
        expect(
          find.text(strings.monitoringIndicatorUnavailable),
          findsOneWidget,
        );
        expect(find.text(strings.monitoringOriginGateway), findsOneWidget);
        expect(find.textContaining('12.5'), findsOneWidget);
        expect(find.textContaining('-43.25'), findsOneWidget);
        expect(find.textContaining('3.5'), findsOneWidget);
        expect(find.text(strings.monitoringStale), findsOneWidget);
        expect(find.text(strings.monitoringNotStale), findsNWidgets(2));
        expect(
          find.text(
            DateFormat.yMMMd(
              strings.localeName,
            ).add_Hms().format(evaluated.toLocal()),
          ),
          findsOneWidget,
        );
        for (final capture in <DateTime>[
          DateTime.utc(2026, 6, 7, 8, 9, 10),
          DateTime.utc(2026, 6, 6, 7, 8, 9),
          DateTime.utc(2026, 6, 5, 6, 7, 8),
        ]) {
          expect(
            find.text(
              DateFormat.yMMMd(
                strings.localeName,
              ).add_Hms().format(capture.toLocal()),
            ),
            findsOneWidget,
          );
        }
        expect(find.byType(TextFormField), findsNothing);
        expect(
          find.textContaining(
            RegExp(r'^(Healthy|Normal|Alert|Threshold)$', caseSensitive: false),
          ),
          findsNothing,
        );
        expect(
          find.text(strings.monitoringIndicatorUnavailable),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('monitoring-snapshot')),
            matching: find.textContaining(
              RegExp('received|communication', caseSensitive: false),
            ),
          ),
          findsNothing,
        );
      });
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets('${language.code} loads and pages historical telemetry', (
      tester,
    ) async {
      await _withFixture(tester, (fixture) async {
        fixture.monitoring.latestResult = syntheticLatestTelemetry(
          cattleId: _cattleId,
        );
        fixture.monitoring.historyBuilder = (ranchId, cattleId, query) {
          final recordedAt = query.from.add(const Duration(minutes: 10));
          final reading = syntheticTelemetryReading(
            readingId: query.page == 1
                ? '55555555-5555-4555-8555-555555555555'
                : '66666666-6666-4666-8666-666666666666',
            cattleId: cattleId,
            recordedAt: recordedAt,
            bodyTemperature: const HistoricalMeasurement(
              value: 38.6,
              unit: 'celsius',
              status: HistoricalMeasurementStatus.valid,
              invalidReason: null,
            ),
          );
          return syntheticTelemetryHistory(
            cattleId: cattleId,
            from: query.from,
            to: query.to,
            page: query.page,
            pageSize: query.pageSize,
            totalCount: 21,
            oldestRetainedRecordedAt: query.from.subtract(
              const Duration(days: 2),
            ),
            items: [reading],
          );
        };

        await tester.pumpWidget(_app(fixture, _page(fixture)));
        await tester.pumpAndSettle();
        expect(fixture.monitoring.historyRequests, isEmpty);

        await _tap(
          tester,
          find.byKey(const Key('monitoring-history-24-hours')),
        );
        expect(fixture.monitoring.historyRequests, hasLength(1));
        expect(
          fixture.monitoring.historyRequests.single.query.to.difference(
            fixture.monitoring.historyRequests.single.query.from,
          ),
          const Duration(hours: 24),
        );
        expect(
          find.byKey(
            const Key(
              'monitoring-history-reading-55555555-5555-4555-8555-555555555555',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text('38${language == AppLanguage.spanish ? ',' : '.'}6 °C'),
          findsOneWidget,
        );
        expect(
          find.text(_strings(tester).monitoringHistoryCount(21)),
          findsOneWidget,
        );

        await _tap(tester, find.byKey(const Key('monitoring-history-next')));
        expect(fixture.monitoring.historyRequests, hasLength(2));
        expect(fixture.monitoring.historyRequests.last.query.page, 2);
        expect(
          find.byKey(
            const Key(
              'monitoring-history-reading-66666666-6666-4666-8666-666666666666',
            ),
          ),
          findsOneWidget,
        );
        expect(fixture.service.canGoNextHistoryPage, isFalse);
      }, language: language);
    });
  }

  testWidgets('an empty history page is distinct from a failed query', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      fixture.monitoring.latestResult = syntheticLatestTelemetry(
        cattleId: _cattleId,
      );
      fixture.monitoring.historyBuilder = (ranchId, cattleId, query) =>
          syntheticTelemetryHistory(
            cattleId: cattleId,
            from: query.from,
            to: query.to,
            page: query.page,
            pageSize: query.pageSize,
          );
      await tester.pumpWidget(_app(fixture, _page(fixture)));
      await tester.pumpAndSettle();

      await _tap(tester, find.byKey(const Key('monitoring-history-load')));

      expect(
        find.text(_strings(tester).monitoringHistoryEmpty),
        findsOneWidget,
      );
      expect(find.byKey(const Key('monitoring-history-error')), findsNothing);
    });
  });

  testWidgets('history custom date picker opens within supported bounds', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      fixture.monitoring.latestResult = syntheticLatestTelemetry(
        cattleId: _cattleId,
      );
      await tester.pumpWidget(_app(fixture, _page(fixture)));
      await tester.pumpAndSettle();

      await _tap(
        tester,
        find.byKey(const Key('monitoring-history-choose-dates')),
      );

      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'history cards and pagination remain usable on narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      try {
        await _withFixture(tester, (fixture) async {
          fixture.monitoring.latestResult = syntheticLatestTelemetry(
            cattleId: _cattleId,
          );
          fixture.monitoring.historyBuilder = (ranchId, cattleId, query) =>
              syntheticTelemetryHistory(
                cattleId: cattleId,
                from: query.from,
                to: query.to,
                page: query.page,
                pageSize: query.pageSize,
                totalCount: 21,
                items: [
                  syntheticTelemetryReading(
                    readingId: '55555555-5555-4555-8555-555555555555',
                    cattleId: cattleId,
                    recordedAt: query.from.add(const Duration(minutes: 1)),
                  ),
                ],
              );
          await tester.pumpWidget(_app(fixture, _page(fixture)));
          await tester.pumpAndSettle();
          await _tap(
            tester,
            find.byKey(const Key('monitoring-history-24-hours')),
          );
          final next = find.byKey(const Key('monitoring-history-next'));
          await tester.ensureVisible(next);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(next).height, greaterThanOrEqualTo(48));
        });
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      }
    },
  );

  testWidgets(
    'real zeros, boundary coordinates, extreme magnitudes and future capture remain values',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        final recorded = DateTime.utc(2027, 1, 2, 3, 4, 5);
        fixture.monitoring.latestResult = syntheticLatestTelemetry(
          cattleId: _cattleId,
          bodyTemperature: LatestIndicator.available(
            value: 0,
            unit: TelemetryUnit.celsius,
            recordedAt: recorded,
            isStale: false,
          ),
          activityIndex: LatestIndicator.available(
            value: 1e-12,
            unit: TelemetryUnit.activityIndex,
            recordedAt: recorded,
            isStale: false,
          ),
          ruminationMinutes: LatestIndicator.available(
            value: 1e20,
            unit: TelemetryUnit.minutes,
            recordedAt: recorded,
            isStale: false,
          ),
          lastKnownPosition: LastKnownPosition.available(
            latitude: 0,
            longitude: 180,
            accuracyMeters: 0,
            recordedAt: recorded,
            isStale: false,
          ),
        );
        await tester.pumpWidget(_app(fixture, _page(fixture)));
        await tester.pumpAndSettle();
        final strings = _strings(tester);
        expect(find.textContaining(RegExp(r'(^|\s)0(\s|$)')), findsWidgets);
        expect(find.textContaining('1E-12'), findsOneWidget);
        expect(find.textContaining('1E20'), findsOneWidget);
        expect(find.textContaining('180'), findsOneWidget);
        expect(find.text(strings.monitoringIndicatorUnavailable), findsNothing);
        expect(find.text(strings.monitoringPositionUnavailable), findsNothing);
        final formatted = DateFormat.yMMMd(
          strings.localeName,
        ).add_Hms().format(recorded.toLocal());
        expect(find.text(formatted), findsNWidgets(4));
        expect(find.text(strings.monitoringNotStale), findsNWidgets(4));
      });
    },
  );

  testWidgets(
    'not found is distinct and retry clears previous data and errors safely',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.monitoring.latestResult = syntheticLatestTelemetry(
          cattleId: _cattleId,
          bodyTemperature: LatestIndicator.available(
            value: 38.1,
            unit: TelemetryUnit.celsius,
            recordedAt: DateTime.utc(2026),
            isStale: false,
          ),
        );
        await tester.pumpWidget(_app(fixture, _page(fixture)));
        await tester.pumpAndSettle();
        fixture.monitoring.failure = const MonitoringFailure(
          MonitoringFailureCode.forbidden,
        );
        await _tap(tester, find.byKey(const Key('monitoring-reload')));
        expect(find.byKey(const Key('monitoring-snapshot')), findsNothing);
        expect(find.textContaining('38.1'), findsNothing);
        expect(
          find.text(_strings(tester).monitoringErrorForbidden),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            RegExp('forbidden|server|exception', caseSensitive: false),
          ),
          findsNothing,
        );
        fixture.monitoring.failure = const MonitoringFailure(
          MonitoringFailureCode.network,
        );
        await _tap(tester, find.byKey(const Key('monitoring-reload')));
        expect(
          find.text(_strings(tester).monitoringErrorNetwork),
          findsOneWidget,
        );
        fixture.monitoring.failure = const MonitoringFailure(
          MonitoringFailureCode.unauthenticated,
        );
        await _tap(tester, find.byKey(const Key('monitoring-reload')));
        expect(
          find.text(_strings(tester).monitoringErrorUnauthenticated),
          findsOneWidget,
        );
        fixture.monitoring.failure = const MonitoringFailure(
          MonitoringFailureCode.notFound,
        );
        await _tap(tester, find.byKey(const Key('monitoring-reload')));
        expect(
          find.text(_strings(tester).monitoringErrorNotFound),
          findsOneWidget,
        );
        expect(find.byKey(const Key('monitoring-snapshot')), findsNothing);
      });
    },
  );

  testWidgets(
    'ranch switches and logout hide pending snapshots; stale responses do not return',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        final pending = Completer<LatestTelemetry>();
        fixture.monitoring.completer = pending;
        await tester.pumpWidget(_app(fixture, _page(fixture)));
        await tester.pump();
        expect(fixture.monitoring.requests, hasLength(1));
        fixture.selection.select(_otherRanchId);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('monitoring-snapshot')), findsNothing);
        fixture.selection.select(_ranchId);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('monitoring-snapshot')), findsNothing);
        pending.complete(syntheticLatestTelemetry(cattleId: _cattleId));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('monitoring-snapshot')), findsNothing);

        fixture.monitoring.completer = null;
        fixture.monitoring.latestResult = syntheticLatestTelemetry(
          cattleId: _cattleId,
        );
        await _tap(tester, find.byKey(const Key('monitoring-reload')));
        expect(find.byKey(const Key('monitoring-snapshot')), findsOneWidget);
        final logoutPending = Completer<LatestTelemetry>();
        fixture.monitoring.completer = logoutPending;
        await _tap(tester, find.byKey(const Key('monitoring-reload')));
        expect(find.byKey(const Key('monitoring-snapshot')), findsNothing);
        final signingOut = fixture.auth.signOut();
        await tester.pumpAndSettle();
        expect(fixture.service.hasContext, isFalse);
        expect(find.byKey(const Key('monitoring-snapshot')), findsNothing);
        logoutPending.complete(syntheticLatestTelemetry(cattleId: _cattleId));
        await signingOut;
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('monitoring-snapshot')), findsNothing);
      });
    },
  );

  testWidgets('updated cattle ID loads that ID and back invokes its callback', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      fixture.monitoring.latestResult = syntheticLatestTelemetry(
        cattleId: _cattleId,
      );
      await tester.pumpWidget(_app(fixture, _page(fixture)));
      await tester.pumpAndSettle();
      final replacement = Completer<LatestTelemetry>();
      fixture.monitoring.completer = replacement;
      await tester.pumpWidget(
        _app(fixture, _page(fixture, cattleId: _otherCattleId)),
      );
      await tester.pump();
      expect(fixture.monitoring.requests.last.cattleId, _otherCattleId);
      expect(find.byKey(const Key('monitoring-snapshot')), findsNothing);
      replacement.complete(syntheticLatestTelemetry(cattleId: _otherCattleId));
      await tester.pumpAndSettle();
      expect(find.text(_otherCattleId), findsOneWidget);
      fixture.monitoring.completer = null;
      fixture.monitoring.latestResult = syntheticLatestTelemetry(
        cattleId: _otherCattleId,
        bodyTemperature: LatestIndicator.available(
          value: 39,
          unit: TelemetryUnit.celsius,
          recordedAt: DateTime.utc(2026, 2, 3),
          isStale: false,
        ),
      );
      await _tap(tester, find.byKey(const Key('monitoring-reload')));
      expect(find.text('39 °C'), findsOneWidget);
      final replacementService = MonitoringReadService(
        access: fixture.access,
        monitoring: fixture.monitoring,
      );
      try {
        fixture.monitoring.latestResult = syntheticLatestTelemetry(
          cattleId: _otherCattleId,
        );
        await tester.pumpWidget(
          _app(
            fixture,
            AnimalMonitoringPage(
              language: fixture.language,
              service: replacementService,
              cattleId: _otherCattleId,
              onBack: () => fixture.backCalls++,
              onOpenRanches: () => fixture.openRanches++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(fixture.monitoring.requests.last.cattleId, _otherCattleId);
        expect(find.textContaining('39'), findsNothing);
        expect(find.text(_otherCattleId), findsOneWidget);
      } finally {
        replacementService.dispose();
      }
      await _tap(tester, find.byTooltip(_strings(tester).monitoringBackAnimal));
      expect(fixture.backCalls, 1);
    });
  });

  testWidgets(
    'changing language preserves the route and snapshot without another request',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.monitoring.latestResult = syntheticLatestTelemetry(
          cattleId: _cattleId,
        );
        await tester.pumpWidget(_app(fixture, _page(fixture)));
        await tester.pumpAndSettle();
        final calls = fixture.monitoring.calls;
        await fixture.language.select(AppLanguage.spanish);
        await tester.pumpAndSettle();
        expect(fixture.language.current, AppLanguage.spanish);
        expect(fixture.monitoring.calls, calls);
        expect(find.byType(AnimalMonitoringPage), findsOneWidget);
        expect(find.byKey(const Key('monitoring-snapshot')), findsOneWidget);
        expect(_strings(tester).localeName, 'es');
      });
    },
  );

  testWidgets('keyboard insets keep reload reachable on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    try {
      await _withFixture(tester, (fixture) async {
        fixture.monitoring.latestResult = syntheticLatestTelemetry(
          cattleId: _cattleId,
        );
        await tester.pumpWidget(_app(fixture, _page(fixture)));
        await tester.pumpAndSettle();
        final reload = find.byKey(const Key('monitoring-reload'));
        await tester.ensureVisible(reload);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(reload).height, greaterThanOrEqualTo(48));
      });
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    }
  });

  for (final language in AppLanguage.values) {
    for (final platform in const <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      for (final landscape in <bool>[false, true]) {
        testWidgets(
          '${language.code}/${platform.name}/${landscape ? 'landscape' : 'narrow'} summary scales and scrolls',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = landscape
                ? const Size(640, 360)
                : const Size(320, 568);
            tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
            try {
              await _withFixture(
                tester,
                (fixture) async {
                  fixture.monitoring.latestResult = syntheticLatestTelemetry(
                    cattleId: _cattleId,
                    bodyTemperature: LatestIndicator.available(
                      value: 38.25,
                      unit: TelemetryUnit.celsius,
                      recordedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
                      isStale: false,
                    ),
                  );
                  await tester.pumpWidget(_app(fixture, _page(fixture)));
                  await tester.pumpAndSettle();
                  final reload = find.byKey(const Key('monitoring-reload'));
                  await tester.ensureVisible(reload);
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull);
                  expect(
                    tester.getSize(reload).height,
                    greaterThanOrEqualTo(48),
                  );
                  expect(
                    find.textContaining(
                      NumberFormat(
                        '0.###############',
                        language.code,
                      ).format(38.25),
                    ),
                    findsOneWidget,
                  );
                },
                language: language,
                platform: platform,
              );
            } finally {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
              tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
            }
          },
        );
      }
    }
  }

  testWidgets('reload and selection controls are labeled and accessible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _withFixture(tester, (fixture) async {
        fixture.monitoring.latestResult = syntheticLatestTelemetry(
          cattleId: _cattleId,
        );
        await tester.pumpWidget(_app(fixture, _page(fixture)));
        await tester.pumpAndSettle();
        final reload = find.byKey(const Key('monitoring-reload'));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        expect(tester.getSemantics(reload).label, isNotEmpty);
      });
    } finally {
      semantics.dispose();
    }
  });
}

Future<void> _withFixture(
  WidgetTester tester,
  Future<void> Function(_Fixture fixture) body, {
  List<RanchAccess> ranches = _ranches,
  AppLanguage language = AppLanguage.english,
  TargetPlatform platform = TargetPlatform.android,
  bool configured = true,
}) async {
  final authenticationRepository = FakeAuthenticationRepository();
  final accounts = FakeAccountRepository(ranches: ranches);
  final lifecycle = AuthenticationLifecycle(authenticationRepository);
  final auth = AuthService(authentication: lifecycle, accounts: accounts);
  await auth.initialize();
  final selection = RanchSelectionService(
    session: auth,
    now: () => DateTime.utc(2026, 1, 1),
  );
  if (ranches.isNotEmpty) selection.select(ranches.first.ranchId);
  final access = AuthorizedRanchSession(
    session: auth,
    selection: selection,
    authentication: authenticationRepository,
  );
  final monitoring = FakeMonitoringRepository()..configured = configured;
  final service = MonitoringReadService(access: access, monitoring: monitoring);
  final languageService = LanguageService(
    MemoryLanguagePreferences(language: language),
  );
  await languageService.initialize();
  final fixture = _Fixture(
    authenticationRepository: authenticationRepository,
    lifecycle: lifecycle,
    auth: auth,
    selection: selection,
    access: access,
    monitoring: monitoring,
    service: service,
    language: languageService,
    platform: platform,
  );
  try {
    await body(fixture);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  }
}

Widget _page(_Fixture fixture, {String cattleId = _cattleId}) =>
    AnimalMonitoringPage(
      language: fixture.language,
      service: fixture.service,
      cattleId: cattleId,
      onBack: () => fixture.backCalls++,
      onOpenRanches: () => fixture.openRanches++,
    );

Widget _app(_Fixture fixture, Widget page) => ListenableBuilder(
  listenable: fixture.language,
  builder: (context, _) => MaterialApp(
    theme: IchuTheme.light.copyWith(platform: fixture.platform),
    locale: Locale(fixture.language.current.code),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: page,
  ),
);

AppLocalizations _strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AnimalMonitoringPage)));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

final class _Fixture {
  _Fixture({
    required this.authenticationRepository,
    required this.lifecycle,
    required this.auth,
    required this.selection,
    required this.access,
    required this.monitoring,
    required this.service,
    required this.language,
    required this.platform,
  });

  final FakeAuthenticationRepository authenticationRepository;
  final AuthenticationLifecycle lifecycle;
  final AuthService auth;
  final RanchSelectionService selection;
  final AuthorizedRanchSession access;
  final FakeMonitoringRepository monitoring;
  final MonitoringReadService service;
  final LanguageService language;
  final TargetPlatform platform;
  int openRanches = 0;
  int backCalls = 0;

  void dispose() {
    service.dispose();
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    language.dispose();
    unawaited(authenticationRepository.close());
  }
}
