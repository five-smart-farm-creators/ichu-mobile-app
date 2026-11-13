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
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/alert_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/alert_search.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/ranch_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/presentation/pages/ranch_alerts_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import 'support/fake_alert_repository.dart';
import 'support/fake_iam_repositories.dart';
import 'support/memory_language_preferences.dart';

const _ranchA = '11111111-1111-4111-8111-111111111111';
const _ranchB = '22222222-2222-4222-8222-222222222222';
const _ranches = <RanchAccess>[
  RanchAccess(
    ranchId: _ranchA,
    scope: AccessScope.read,
    name: 'Selected ranch',
    region: 'Central Region',
    district: 'North District',
  ),
  RanchAccess(
    ranchId: _ranchB,
    scope: AccessScope.read,
    name: 'Second ranch',
    region: 'West Region',
    district: 'South District',
  ),
];

void main() {
  testWidgets('missing ranch offers selection and never reads alerts', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();
      expect(fixture.alerts.requests, isEmpty);
      expect(find.byKey(const Key('alerts-choose-ranch')), findsOneWidget);
      expect(find.byKey(const Key('alerts-reload')), findsNothing);
      await _tap(tester, find.byKey(const Key('alerts-choose-ranch')));
      expect(fixture.openCalls, 1);
    }, ranches: const <RanchAccess>[]);
  });

  testWidgets('unconfigured repository has safe error and disabled retry', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();
      expect(fixture.alerts.requests, isEmpty);
      expect(
        find.text(_strings(tester).alertErrorConfiguration),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('alerts-reload')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('alerts-error')), findsOneWidget);
    }, configured: false);
  });

  testWidgets(
    'initial read is explicit-after-frame; empty is not a health claim',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.alerts.pageResult = _page(_ranchA, page: 1, total: 0);
        expect(fixture.alerts.requests, isEmpty);
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        final strings = _strings(tester);
        expect(fixture.alerts.requests, hasLength(1));
        expect(find.text(strings.alertTotal(0)), findsOneWidget);
        expect(find.text(strings.alertEmpty), findsOneWidget);
        expect(find.text(strings.alertCloudNote), findsOneWidget);
        expect(
          find.textContaining(
            RegExp(r'^(Healthy|Normal)$', caseSensitive: false),
          ),
          findsNothing,
        );
        expect(find.byType(TextFormField), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        expect(find.byType(Switch), findsNothing);
      });
    },
  );

  testWidgets('status draft requires explicit apply and resets to page one', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      fixture.alerts.pageResult = _page(
        _ranchA,
        page: 1,
        total: 41,
        items: [_alert(_ranchA, 'first')],
      );
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();
      fixture.alerts.pageResult = _page(
        _ranchA,
        page: 2,
        total: 41,
        items: [_alert(_ranchA, 'second')],
      );
      await _tap(tester, find.byKey(const Key('alerts-next')));
      expect(fixture.alerts.requests.last.query.page, 2);
      expect(find.byKey(const Key('alert-row-0-2-second')), findsOneWidget);
      expect(find.text(_strings(tester).alertTotal(41)), findsOneWidget);

      await _chooseStatus(tester, AlertStatus.acknowledged);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('alerts-next')))
            .onPressed,
        isNull,
      );
      expect(fixture.alerts.requests, hasLength(2));
      fixture.alerts.pageResult = _page(
        _ranchA,
        page: 1,
        total: 3,
        items: [
          _alert(_ranchA, 'acknowledged', status: AlertStatus.acknowledged),
        ],
      );
      await _tap(tester, find.byKey(const Key('alerts-apply')));
      final request = fixture.alerts.requests.last;
      expect(request.query.status, AlertStatus.acknowledged);
      expect(request.query.page, 1);
      expect(
        find.textContaining(_strings(tester).alertAcknowledged),
        findsWidgets,
      );

      await _chooseStatus(tester, null);
      fixture.alerts.pageResult = _page(
        _ranchA,
        page: 1,
        total: 1,
        items: [_alert(_ranchA, 'all-statuses')],
      );
      await _tap(tester, find.byKey(const Key('alerts-apply')));
      expect(fixture.alerts.requests.last.query.status, isNull);
      expect(fixture.alerts.requests.last.query.page, 1);
      expect(
        find.byKey(const Key('alert-row-0-1-all-statuses')),
        findsOneWidget,
      );
    });
  });

  testWidgets('server total controls short-page navigation and rows replace', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      fixture.alerts.pageResult = _page(
        _ranchA,
        page: 1,
        total: 41,
        items: [_alert(_ranchA, 'one')],
      );
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();
      expect(find.text(_strings(tester).alertTotal(41)), findsOneWidget);
      fixture.alerts.pageResult = _page(
        _ranchA,
        page: 2,
        total: 41,
        items: [_alert(_ranchA, 'two')],
      );
      await _tap(tester, find.byKey(const Key('alerts-next')));
      expect(fixture.alerts.requests.last.query.page, 2);
      expect(fixture.alerts.requests.last.query.pageSize, 20);
      expect(find.byKey(const Key('alert-row-0-2-two')), findsOneWidget);
      expect(find.byKey(const Key('alert-row-0-1-one')), findsNothing);
      fixture.alerts.pageResult = _page(_ranchA, page: 2, total: 1);
      await _tap(tester, find.byKey(const Key('alerts-reload')));
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('alerts-next')))
            .onPressed,
        isNull,
      );
      expect(find.text(_strings(tester).alertEmpty), findsOneWidget);
    });
  });

  testWidgets(
    'reload preserves committed status and page; failure clears snapshot',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 1,
          total: 25,
          items: [_alert(_ranchA, 'pending')],
        );
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        await _chooseStatus(tester, AlertStatus.pending);
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 1,
          total: 25,
          items: [_alert(_ranchA, 'pending-filtered')],
        );
        await _tap(tester, find.byKey(const Key('alerts-apply')));
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 2,
          total: 25,
          items: [_alert(_ranchA, 'pending-page-two')],
        );
        await _tap(tester, find.byKey(const Key('alerts-next')));
        final query = fixture.alerts.requests.last.query;
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: query.page,
          total: 25,
          items: [_alert(_ranchA, 'reloaded')],
          status: query.status,
        );
        await _tap(tester, find.byKey(const Key('alerts-reload')));
        expect(fixture.alerts.requests.last.query, query);
        expect(find.byKey(const Key('alert-row-0-2-reloaded')), findsOneWidget);

        fixture.alerts.failure = const MonitoringFailure(
          MonitoringFailureCode.forbidden,
        );
        await _tap(tester, find.byKey(const Key('alerts-reload')));
        expect(find.byKey(const Key('alerts-error')), findsOneWidget);
        expect(find.text(_strings(tester).alertErrorForbidden), findsOneWidget);
        expect(find.byKey(const Key('alert-row-0-2-reloaded')), findsNothing);
        expect(find.text(_strings(tester).alertTotal(25)), findsNothing);
        expect(
          find.textContaining(
            RegExp('exception|stack|firebase|token', caseSensitive: false),
          ),
          findsNothing,
        );
      });
    },
  );

  testWidgets(
    'network and authorization failures are safe and explicitly retryable',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 1,
          total: 1,
          items: [_alert(_ranchA, 'before-error')],
        );
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        final strings = _strings(tester);
        for (final failure in <(MonitoringFailureCode, String)>[
          (
            MonitoringFailureCode.unauthenticated,
            strings.monitoringErrorUnauthenticated,
          ),
          (MonitoringFailureCode.forbidden, strings.alertErrorForbidden),
          (MonitoringFailureCode.network, strings.alertErrorNetwork),
          (
            MonitoringFailureCode.serviceUnavailable,
            strings.alertErrorUnavailable,
          ),
        ]) {
          fixture.alerts.failure = MonitoringFailure(failure.$1);
          await _tap(tester, find.byKey(const Key('alerts-reload')));
          expect(find.text(failure.$2), findsOneWidget);
          expect(
            find.byKey(const Key('alert-row-0-1-before-error')),
            findsNothing,
          );
          expect(fixture.alerts.requests.last.query, const AlertSearch());
        }
        expect(
          find.textContaining(
            RegExp('exception|stack|firebase|token|http', caseSensitive: false),
          ),
          findsNothing,
        );
      });
    },
  );

  testWidgets('all three alert types and persisted details are read-only', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      final raised = DateTime.utc(2026, 2, 3, 4, 5, 6);
      final received = DateTime.utc(2026, 2, 3, 4, 8, 9);
      final readingIds = List<String>.generate(
        12,
        (index) =>
            'a7777777-7777-4777-8777-${(index + 1).toString().padLeft(12, '0')}',
      );
      fixture.alerts.pageResult = _page(
        _ranchA,
        page: 1,
        total: 3,
        items: [
          _alert(
            _ranchA,
            'temp',
            status: AlertStatus.acknowledged,
            raisedAt: raised,
            receivedAt: received,
            detectedValue: 38.6,
            thresholdMin: 39.2,
            thresholdMax: 41,
            configurationRevision: 9223372036854770000,
            version: 7,
            finding: 'Captured plain-text finding',
            action: 'Recorded fixture action',
            readingIds: readingIds,
          ),
          _alert(
            _ranchA,
            'activity',
            type: AlertType.activity,
            detectedValue: 1e-300,
            severity: AlertSeverity.critical,
            status: AlertStatus.acknowledged,
          ),
          _alert(
            _ranchA,
            'geo',
            type: AlertType.geofence,
            severity: AlertSeverity.informative,
            geofenceId: 'b8888888-8888-4888-8888-888888888888',
            latitude: 0,
            longitude: -72.1,
            distance: 0,
            clearedAt: DateTime.utc(2026, 2, 3, 5),
            exitDuration: 0,
          ),
        ],
      );
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();
      final strings = _strings(tester);
      expect(find.text(strings.alertTypeTemperature), findsOneWidget);
      expect(find.text(strings.alertTypeActivity), findsOneWidget);
      expect(find.text(strings.alertTypeGeofence), findsOneWidget);
      expect(find.textContaining(strings.alertSeverityWarning), findsOneWidget);
      expect(
        find.textContaining(strings.alertSeverityCritical),
        findsOneWidget,
      );
      expect(
        find.textContaining(strings.alertSeverityInformative),
        findsOneWidget,
      );
      expect(find.textContaining(strings.alertPending), findsWidgets);
      expect(find.textContaining(strings.alertAcknowledged), findsWidgets);
      expect(find.textContaining('38.6'), findsNothing);
      final initialCalls = fixture.alerts.calls;
      await _tap(tester, find.byKey(const Key('alert-details-temp')));
      expect(fixture.alerts.calls, initialCalls);
      expect(find.text(strings.alertReadOnlyNote), findsOneWidget);
      expect(find.text(strings.alertWorkflowNote), findsOneWidget);
      expect(find.text('Captured plain-text finding'), findsOneWidget);
      expect(find.text('Recorded fixture action'), findsOneWidget);
      expect(
        find.text('c3333333-3333-4333-8333-333333333333'),
        findsNWidgets(3),
      );
      expect(find.text('d4444444-4444-4444-8444-444444444444'), findsOneWidget);
      expect(find.text('e5555555-5555-4555-8555-555555555555'), findsOneWidget);
      expect(find.text(strings.monitoringOriginGateway), findsOneWidget);
      for (final id in readingIds.take(10)) {
        expect(find.textContaining(id), findsOneWidget);
      }
      expect(find.text(readingIds.last), findsNothing);
      expect(
        find.text(strings.alertReadingIdsMore(10, readingIds.length)),
        findsOneWidget,
      );
      expect(find.textContaining('9223372036854770000'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('38.6'), findsOneWidget);
      expect(find.textContaining('39.2'), findsOneWidget);
      expect(find.textContaining('39.200000000000003'), findsNothing);
      expect(find.textContaining('600000000000001'), findsNothing);
      final dateFormat = DateFormat.yMMMd(strings.localeName).add_Hms();
      expect(find.text(dateFormat.format(raised.toLocal())), findsOneWidget);
      expect(find.text(dateFormat.format(received.toLocal())), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(
        find.textContaining(
          RegExp(
            r'^(Acknowledge|Edit|Save|Delete)(?: alert)?$',
            caseSensitive: false,
          ),
        ),
        findsNothing,
      );
      await _tap(tester, find.byKey(const Key('alert-details-activity')));
      expect(find.textContaining('1E-300'), findsOneWidget);
      expect(find.textContaining('0.000000000000000'), findsNothing);
    });
  });

  testWidgets(
    'pending acknowledgement fields and nullable values stay explicit',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 1,
          total: 1,
          items: [
            _alert(
              _ranchA,
              'pending-detail',
              detectedValue: 0,
              thresholdMin: 1,
              thresholdMax: 39.5,
              finding: null,
              action: null,
            ),
          ],
        );
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        await _tap(
          tester,
          find.byKey(const Key('alert-details-pending-detail')),
        );
        final strings = _strings(tester);
        expect(find.text(strings.alertNotProvided), findsAtLeastNWidgets(2));
        expect(find.text('0'), findsOneWidget);
        expect(find.textContaining('38.6'), findsNothing);
        expect(find.text(strings.alertAcknowledgement), findsOneWidget);
        expect(
          find.textContaining(
            RegExp(
              r'^(Acknowledge|Edit|Save)(?: alert)?$',
              caseSensitive: false,
            ),
          ),
          findsNothing,
        );
      });
    },
  );

  testWidgets(
    'geofence retains zero coordinates and cleared time independently',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 1,
          total: 1,
          items: [
            _alert(
              _ranchA,
              'historical-geo',
              type: AlertType.geofence,
              status: AlertStatus.pending,
              latitude: 0,
              longitude: 0,
              distance: 0,
              clearedAt: DateTime.utc(2026, 3, 4, 5),
              exitDuration: 0,
            ),
          ],
        );
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        await _tap(
          tester,
          find.byKey(const Key('alert-details-historical-geo')),
        );
        final strings = _strings(tester);
        expect(find.text(strings.alertGeofenceNote), findsOneWidget);
        expect(find.text(strings.alertClearedAt), findsOneWidget);
        expect(find.textContaining(strings.alertPending), findsWidgets);
        expect(find.text(strings.alertNotProvided), findsWidgets);
        expect(find.text('0'), findsAtLeastNWidgets(4));
        expect(
          find.text(
            DateFormat.yMMMd(
              strings.localeName,
            ).add_Hms().format(DateTime.utc(2026, 3, 4, 5).toLocal()),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            RegExp(
              r'^(Live location|Current location|Tracking)$',
              caseSensitive: false,
            ),
          ),
          findsNothing,
        );
      });
    },
  );

  testWidgets('switching A-B-A clears rows and fences a late response', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      final pending = Completer<AlertPage>();
      fixture.alerts.completer = pending;
      await tester.pumpWidget(_app(fixture));
      await tester.pump();
      await Future<void>.value();
      expect(fixture.alerts.requests, hasLength(1));
      fixture.selection.select(_ranchB);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alert-row-0-1-old-record')), findsNothing);
      expect(find.text(_strings(tester).alertTotal(1)), findsNothing);
      fixture.selection.select(_ranchA);
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsNothing);
      pending.complete(
        _page(
          _ranchA,
          page: 1,
          total: 1,
          items: [_alert(_ranchA, 'old-record')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alert-row-0-1-old-record')), findsNothing);
      expect(fixture.alerts.calls, 1);
    });
  });

  testWidgets(
    'service replacement and language changes do not expose old data',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 1,
          total: 1,
          items: [_alert(_ranchA, 'first-service')],
        );
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        final oldCalls = fixture.alerts.calls;
        final otherRepo = FakeAlertRepository()
          ..pageResult = _page(_ranchA, page: 1, total: 0);
        final replacement = AlertReadService(
          access: fixture.access,
          alerts: otherRepo,
        );
        try {
          await tester.pumpWidget(_app(fixture, service: replacement));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('alert-row-0-1-first-service')),
            findsNothing,
          );
          expect(otherRepo.calls, 1);
          await fixture.language.select(AppLanguage.spanish);
          await tester.pumpAndSettle();
          expect(find.byType(RanchAlertsPage), findsOneWidget);
          expect(otherRepo.calls, 1);
          expect(fixture.alerts.calls, oldCalls);
          expect(_strings(tester).localeName, 'es');
        } finally {
          replacement.dispose();
        }
      });
    },
  );

  testWidgets(
    'language change preserves the committed filter and page without rereading',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 1,
          total: 41,
          items: [_alert(_ranchA, 'initial')],
        );
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        await _chooseStatus(tester, AlertStatus.pending);
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 1,
          total: 41,
          items: [_alert(_ranchA, 'filtered')],
        );
        await _tap(tester, find.byKey(const Key('alerts-apply')));
        fixture.alerts.pageResult = _page(
          _ranchA,
          page: 2,
          total: 41,
          items: [_alert(_ranchA, 'page-two')],
        );
        await _tap(tester, find.byKey(const Key('alerts-next')));
        final calls = fixture.alerts.calls;
        await fixture.language.select(AppLanguage.spanish);
        await tester.pumpAndSettle();
        expect(fixture.alerts.calls, calls);
        expect(
          fixture.service.query,
          const AlertSearch(status: AlertStatus.pending, page: 2),
        );
        expect(find.byKey(const Key('alert-row-0-2-page-two')), findsOneWidget);
        expect(_strings(tester).localeName, 'es');
      });
    },
  );

  testWidgets('back callback is invoked', (tester) async {
    await _withFixture(tester, (fixture) async {
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();
      final back = find.byTooltip(_strings(tester).cattleBackAccount);
      await _tap(tester, back);
      expect(fixture.backCalls, 1);
    });
  });

  testWidgets('keyboard inset keeps reload reachable on a narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    try {
      await _withFixture(tester, (fixture) async {
        fixture.alerts.pageResult = _page(_ranchA, page: 1, total: 0);
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        final reload = find.byKey(const Key('alerts-reload'));
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
          '${language.code}/${platform.name}/${landscape ? 'landscape' : 'narrow'} scales and scrolls',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = landscape
                ? const Size(640, 360)
                : const Size(320, 568);
            tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
            try {
              await _withFixture(tester, (fixture) async {
                fixture.alerts.pageResult = _page(
                  _ranchA,
                  page: 1,
                  total: 1,
                  items: [_alert(_ranchA, 'scaled')],
                );
                await tester.pumpWidget(_app(fixture, platform: platform));
                await tester.pumpAndSettle();
                final reload = find.byKey(const Key('alerts-reload'));
                await tester.ensureVisible(reload);
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                expect(tester.getSize(reload).height, greaterThanOrEqualTo(48));
                expect(
                  find.byKey(const Key('alert-row-0-1-scaled')),
                  findsOneWidget,
                );
              }, language: language);
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

  testWidgets('controls are labeled and accessible on Android and iOS', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _withFixture(tester, (fixture) async {
        fixture.alerts.pageResult = _page(_ranchA, page: 1, total: 0);
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        final reload = find.byKey(const Key('alerts-reload'));
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
  final alerts = FakeAlertRepository()..configured = configured;
  final service = AlertReadService(access: access, alerts: alerts);
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
    alerts: alerts,
    service: service,
    language: languageService,
  );
  try {
    await body(fixture);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  }
}

Widget _app(
  _Fixture fixture, {
  AlertReadService? service,
  TargetPlatform platform = TargetPlatform.android,
}) => ListenableBuilder(
  listenable: fixture.language,
  builder: (context, _) => MaterialApp(
    theme: IchuTheme.light.copyWith(platform: platform),
    locale: Locale(fixture.language.current.code),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RanchAlertsPage(
      language: fixture.language,
      service: service ?? fixture.service,
      onBack: fixture.pageBack,
      onOpenRanches: fixture.openRanches,
    ),
  ),
);

AppLocalizations _strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(RanchAlertsPage)));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _chooseStatus(WidgetTester tester, AlertStatus? status) async {
  await tester.ensureVisible(find.byType(DropdownButtonFormField<AlertStatus>));
  await tester.tap(find.byType(DropdownButtonFormField<AlertStatus>));
  await tester.pumpAndSettle();
  final label = switch (status) {
    AlertStatus.pending => _strings(tester).alertPending,
    AlertStatus.acknowledged => _strings(tester).alertAcknowledged,
    null => _strings(tester).alertAllStatuses,
  };
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

AlertPage _page(
  String ranchId, {
  required int page,
  required int total,
  List<RanchAlert> items = const <RanchAlert>[],
  AlertStatus? status,
}) {
  assert(ranchId.isNotEmpty);
  return AlertPage(
    page: page,
    pageSize: 20,
    totalCount: total,
    items: status == null
        ? items
        : items.where((item) => item.status == status).toList(growable: false),
  );
}

RanchAlert _alert(
  String ranchId,
  String id, {
  AlertStatus status = AlertStatus.pending,
  AlertType type = AlertType.temperature,
  AlertSeverity severity = AlertSeverity.warning,
  DateTime? raisedAt,
  DateTime? receivedAt,
  double? detectedValue = 40.2,
  double? thresholdMin = 37.5,
  double? thresholdMax = 39.5,
  int configurationRevision = 1,
  int version = 1,
  String? finding,
  String? action,
  String? geofenceId,
  double? latitude,
  double? longitude,
  double? distance,
  DateTime? clearedAt,
  double? exitDuration,
  List<String> readingIds = const <String>[
    'a7777777-7777-4777-8777-777777777777',
  ],
}) => RanchAlert(
  alertId: id,
  ranchId: ranchId,
  cattleId: 'c3333333-3333-4333-8333-333333333333',
  deviceId: 'd4444444-4444-4444-8444-444444444444',
  gatewayId: 'e5555555-5555-4555-8555-555555555555',
  type: type,
  severity: severity,
  status: status,
  origin: AlertOrigin.edgeGateway,
  raisedAt: raisedAt ?? DateTime.utc(2026, 1, 1),
  receivedAt: receivedAt ?? DateTime.utc(2026, 1, 1, 0, 0, 1),
  detectedValue: type == AlertType.geofence ? null : detectedValue,
  unit: switch (type) {
    AlertType.geofence => null,
    AlertType.temperature => 'celsius',
    AlertType.activity => 'index',
  },
  thresholdMinValue: type == AlertType.geofence ? null : thresholdMin,
  thresholdMaxValue: type == AlertType.geofence ? null : thresholdMax,
  configurationRevision: configurationRevision,
  geofenceId: type == AlertType.geofence
      ? (geofenceId ?? 'b8888888-8888-4888-8888-888888888888')
      : null,
  latitude: latitude,
  longitude: longitude,
  distanceToBoundaryMeters: distance,
  clearedAt: clearedAt,
  exitDurationSeconds: exitDuration,
  acknowledgedAt: status == AlertStatus.acknowledged
      ? (raisedAt ?? DateTime.utc(2026, 1, 1)).add(const Duration(minutes: 1))
      : null,
  acknowledgedBy: status == AlertStatus.acknowledged
      ? 'f6666666-6666-4666-8666-666666666666'
      : null,
  finding: status == AlertStatus.acknowledged
      ? (finding ?? 'Synthetic observation')
      : null,
  action: status == AlertStatus.acknowledged ? action : null,
  responseTimeSeconds: status == AlertStatus.acknowledged ? 60 : null,
  version: status == AlertStatus.acknowledged && version < 2 ? 2 : version,
  readingIds: readingIds,
);

final class _Fixture {
  _Fixture({
    required this.authenticationRepository,
    required this.lifecycle,
    required this.auth,
    required this.selection,
    required this.access,
    required this.alerts,
    required this.service,
    required this.language,
  });

  final FakeAuthenticationRepository authenticationRepository;
  final AuthenticationLifecycle lifecycle;
  final AuthService auth;
  final RanchSelectionService selection;
  final AuthorizedRanchSession access;
  final FakeAlertRepository alerts;
  final AlertReadService service;
  final LanguageService language;
  int backCalls = 0;
  int openCalls = 0;

  void pageBack() => backCalls++;
  void openRanches() => openCalls++;

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
