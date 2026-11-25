import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/waterer_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/waterer.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/presentation/pages/waterers_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import '../../../support/memory_language_preferences.dart';
import '../../../support/waterer_test_support.dart';

void main() {
  testWidgets('loads an online list with loading and successful empty states', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      final response = Completer<List<WatererStatus>>();
      fixture.repository.onList = (_) => response.future;
      await tester.pumpWidget(_app(fixture));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      response.complete([]);
      await tester.pumpAndSettle();
      expect(find.text(_strings(tester).watererEmpty), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  testWidgets('list failure removes prior data and permits a fresh retry', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();
      expect(find.text('North trough'), findsOneWidget);
      fixture.repository.onList = (_) async =>
          throw const MonitoringFailure(MonitoringFailureCode.network);
      await _tap(tester, 'waterer-refresh');
      expect(find.text('North trough'), findsNothing);
      expect(
        find.text(_strings(tester).watererErrorConnection),
        findsOneWidget,
      );
      fixture.repository.onList = null;
      await _tap(tester, 'waterer-refresh');
      expect(find.text('North trough'), findsOneWidget);
    });
  });

  testWidgets(
    'detail preserves absent measurements and does not offer history without a controller',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.repository.onDetail = (_, _) async => watererStatusFixture(
          controllerId: null,
          hasReading: false,
          controllerStatus: WaterControllerStatus.noController,
          measurementStatus: WaterMeasurementStatus.unavailable,
          rangeStatus: WaterRangeStatus.notConfigured,
        );
        await tester.pumpWidget(_app(fixture, detail: true));
        await tester.pumpAndSettle();
        expect(
          find.text(_strings(tester).watererNoMeasurement),
          findsOneWidget,
        );
        expect(
          find.text(_strings(tester).watererHistoryNoController),
          findsOneWidget,
        );
        expect(find.byKey(const Key('waterer-history-load')), findsNothing);
        expect(find.text('0 °C'), findsNothing);
        expect(find.text(_strings(tester).watererNoController), findsWidgets);
      });
    },
  );

  for (final code in [
    MonitoringFailureCode.unauthenticated,
    MonitoringFailureCode.forbidden,
    MonitoringFailureCode.notFound,
  ]) {
    testWidgets('detail handles $code without displaying a stale trough', (
      tester,
    ) async {
      await _withFixture(tester, (fixture) async {
        fixture.repository.onDetail = (_, _) async =>
            throw MonitoringFailure(code);
        await tester.pumpWidget(_app(fixture, detail: true));
        await tester.pumpAndSettle();
        expect(find.text('North trough'), findsNothing);
        expect(find.byKey(const Key('waterer-history-load')), findsNothing);
        fixture.repository.onDetail = null;
        await _tap(tester, 'waterer-refresh');
        expect(find.text('North trough'), findsOneWidget);
      });
    });
  }

  testWidgets(
    'history loads, pages in the same period, returns empty pages and clears on failure',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        await tester.pumpWidget(_app(fixture, detail: true));
        await tester.pumpAndSettle();
        expect(fixture.repository.historyRequests, isEmpty);
        await _tap(tester, 'waterer-history-load');
        expect(fixture.service.history!.page, 1);
        await _tap(tester, 'waterer-history-next');
        expect(fixture.service.history!.page, 2);
        expect(
          fixture.repository.historyRequests.last.query.from,
          fixture.repository.historyRequests.first.query.from,
        );
        expect(
          fixture.repository.historyRequests.last.query.to,
          fixture.repository.historyRequests.first.query.to,
        );
        final next = tester.widget<TextButton>(
          find.byKey(const Key('waterer-history-next')),
        );
        expect(next.onPressed, isNull);
        fixture.repository.onHistory = (_, _, query) async =>
            waterHistoryFixture(query, items: [], total: 0);
        await _tap(tester, 'waterer-history-previous');
        expect(find.text(_strings(tester).watererHistoryEmpty), findsOneWidget);
        fixture.repository.onHistory = (_, _, _) async =>
            throw const MonitoringFailure(MonitoringFailureCode.network);
        await _tap(tester, 'waterer-history-load');
        expect(find.text('North trough'), findsNothing);
        expect(fixture.service.history, isNull);
        expect(
          find.text(_strings(tester).watererErrorConnection),
          findsOneWidget,
        );
      });
    },
  );

  testWidgets(
    'detail shows invalid observations and server communication state independently',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        fixture.repository.onDetail = (_, _) async => watererStatusFixture(
          controllerStatus: WaterControllerStatus.noCommunication,
          measurementStatus: WaterMeasurementStatus.invalid,
          rangeStatus: WaterRangeStatus.unavailable,
          reading: waterReadingFixture(isValid: false),
        );
        await tester.pumpWidget(_app(fixture, detail: true));
        await tester.pumpAndSettle();
        final strings = _strings(tester);
        expect(find.text(strings.watererNoCommunication), findsOneWidget);
        expect(find.text(strings.watererInvalid), findsOneWidget);
        expect(
          find.text(strings.watererInvalidTemperature('16.5 °C')),
          findsOneWidget,
        );
        expect(find.text(strings.watererCapturedAt), findsOneWidget);
        expect(find.text(strings.watererReceivedAt), findsOneWidget);
        expect(find.text(strings.watererLastCommunication), findsOneWidget);
      });
    },
  );

  testWidgets(
    'backgrounding hides data and resuming loads a new online snapshot',
    (tester) async {
      await _withFixture(tester, (fixture) async {
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        fixture.service.setActive(false);
        await tester.pumpAndSettle();
        expect(find.text('North trough'), findsNothing);
        fixture.service.setActive(true);
        await tester.pumpAndSettle();
        expect(fixture.repository.listRequests, hasLength(2));
        expect(find.text('North trough'), findsOneWidget);
      });
    },
  );

  for (final language in AppLanguage.values) {
    for (final size in [const Size(320, 568), const Size(640, 360)]) {
      testWidgets(
        '${language.code} trough list and history fit $size at 200% text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
          try {
            await _withFixture(tester, (fixture) async {
              await tester.pumpWidget(_app(fixture));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(_app(fixture, detail: true));
              await tester.pumpAndSettle();
              await _tap(tester, 'waterer-history-load');
              final next = find.byKey(const Key('waterer-history-next'));
              await tester.ensureVisible(next);
              await tester.pumpAndSettle();
              expect(tester.getSize(next).height, greaterThanOrEqualTo(48));
              expect(tester.takeException(), isNull);
            }, appLanguage: language);
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

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

AppLocalizations _strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(WaterersPage)));

final class _Fixture {
  const _Fixture(this.repository, this.service, this.language);
  final FakeWatererRepository repository;
  final WatererReadService service;
  final LanguageService language;
}

Widget _app(_Fixture fixture, {bool detail = false}) => MaterialApp(
  theme: IchuTheme.light,
  locale: Locale(fixture.language.current.code),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: WaterersPage(
    language: fixture.language,
    service: fixture.service,
    waterTroughId: detail ? watererId : null,
    ranchId: detail ? watererRanchA : null,
    onBack: () {},
    onOpenRanches: () {},
    onOpenDetails: (_) {},
  ),
);

Future<void> _withFixture(
  WidgetTester tester,
  Future<void> Function(_Fixture) body, {
  AppLanguage appLanguage = AppLanguage.english,
}) async {
  final session = WatererTestSession();
  await session.initialize();
  final repository = FakeWatererRepository();
  final service = WatererReadService(
    access: session.access,
    waterers: repository,
  );
  final language = LanguageService(
    MemoryLanguagePreferences(language: appLanguage),
  );
  await language.initialize();
  try {
    await body(_Fixture(repository, service, language));
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    await session.dispose();
    language.dispose();
  }
}
