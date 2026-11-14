import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/edge_alert_read_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/edge_alert.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/monitoring_failure.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/presentation/pages/edge_alerts_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import '../../../support/fake_edge_alert_repository.dart';
import '../../../support/fake_iam_repositories.dart';
import '../../../support/memory_language_preferences.dart';

const _ranchId = 'a1111111-1111-4111-8111-111111111111';

void main() {
  testWidgets('shows an explicit empty state for a successful empty page', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      fixture.repository.pageResult = _page(const []);
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();

      expect(find.text(_strings(tester).edgeAlertEmpty), findsOneWidget);
      expect(fixture.repository.requests.single.ranchId, _ranchId);
    });
  });

  testWidgets('shows stale data after a refresh failure and retries it', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      fixture.repository.pageResult = _page([_alert()]);
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();
      expect(
        find.text(
          _strings(
            tester,
          ).edgeAlertCattle('c3333333-3333-4333-8333-333333333333'),
        ),
        findsOneWidget,
      );

      fixture.repository.failure = const MonitoringFailure(
        MonitoringFailureCode.network,
      );
      await tester.tap(find.byKey(const Key('edge-alerts-refresh')));
      await tester.pumpAndSettle();
      expect(find.text(_strings(tester).edgeAlertStale), findsOneWidget);
      expect(find.byKey(const Key('edge-alerts-stale')), findsOneWidget);
      expect(fixture.service.alerts, hasLength(1));

      fixture.repository.failure = null;
      fixture.repository.pageResult = _page([_alert(suffix: '2')]);
      await tester.tap(find.byKey(const Key('edge-alerts-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edge-alerts-stale')), findsNothing);
      expect(
        fixture.service.alerts.single.alertId,
        _alert(suffix: '2').alertId,
      );
    });
  });

  testWidgets('shows an unavailable permission error and allows retry', (
    tester,
  ) async {
    await _withFixture(tester, (fixture) async {
      fixture.repository.failure = const MonitoringFailure(
        MonitoringFailureCode.forbidden,
      );
      await tester.pumpWidget(_app(fixture));
      await tester.pumpAndSettle();

      expect(
        find.text(_strings(tester).edgeAlertErrorForbidden),
        findsOneWidget,
      );
      expect(find.byKey(const Key('edge-alerts-unavailable')), findsOneWidget);

      fixture.repository.failure = null;
      fixture.repository.pageResult = _page(const []);
      await tester.tap(find.byKey(const Key('edge-alerts-refresh')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edge-alerts-unavailable')), findsNothing);
      expect(find.text(_strings(tester).edgeAlertEmpty), findsOneWidget);
    });
  });

  for (final language in AppLanguage.values) {
    for (final (layout, size) in <(String, Size)>[
      ('narrow', const Size(320, 568)),
      ('landscape', const Size(640, 360)),
    ]) {
      testWidgets(
        '${language.code} Edge alerts support $layout at large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
          try {
            await _withFixture(tester, (fixture) async {
              fixture.repository.pageResult = _page(const []);
              await tester.pumpWidget(_app(fixture));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);

              final refresh = find.byKey(const Key('edge-alerts-refresh'));
              await tester.ensureVisible(refresh);
              await tester.pumpAndSettle();
              expect(tester.getSize(refresh).height, greaterThanOrEqualTo(48));
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

Future<void> _withFixture(
  WidgetTester tester,
  Future<void> Function(_Fixture fixture) body, {
  AppLanguage appLanguage = AppLanguage.english,
}) async {
  final identity = FakeAuthenticationRepository();
  final accounts = FakeAccountRepository(
    account: const IamAccount(
      id: 'e5555555-5555-4555-8555-555555555555',
      email: 'user@example.test',
      role: AccountRole.ranchManager,
      status: 'Active',
    ),
    ranches: const <RanchAccess>[
      RanchAccess(
        ranchId: _ranchId,
        scope: AccessScope.read,
        name: 'Selected ranch',
        region: 'Synthetic region',
        district: 'Synthetic district',
      ),
    ],
  );
  final lifecycle = AuthenticationLifecycle(identity);
  final auth = AuthService(authentication: lifecycle, accounts: accounts);
  final selection = RanchSelectionService(session: auth);
  final access = AuthorizedRanchSession(
    session: auth,
    selection: selection,
    authentication: identity,
  );
  await auth.initialize();
  expect(selection.select(_ranchId), isTrue);
  final repository = FakeEdgeAlertRepository();
  final service = EdgeAlertReadService(access: access, edgeAlerts: repository);
  final language = LanguageService(
    MemoryLanguagePreferences(language: appLanguage),
  );
  await language.initialize();

  try {
    await body(
      _Fixture(repository: repository, service: service, language: language),
    );
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    await identity.close();
    language.dispose();
  }
}

Widget _app(_Fixture fixture) => ListenableBuilder(
  listenable: fixture.language,
  builder: (context, _) => MaterialApp(
    theme: IchuTheme.light,
    locale: Locale(fixture.language.current.code),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: EdgeAlertsPage(
      language: fixture.language,
      service: fixture.service,
      onBack: () {},
      onOpenRanches: () {},
    ),
  ),
);

AppLocalizations _strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(EdgeAlertsPage)));

EdgeAlert _alert({String suffix = '1'}) => EdgeAlert(
  alertId: 'a8888888-8888-4888-8888-00000000000$suffix',
  ranchId: _ranchId,
  cattleId: 'c3333333-3333-4333-8333-333333333333',
  deviceId: 'd4444444-4444-4444-8444-444444444444',
  gatewayId: 'e5555555-5555-4555-8555-555555555555',
  type: EdgeAlertType.temperature,
  severity: EdgeAlertSeverity.warning,
  raisedAt: DateTime.utc(2026, 1, 1),
  receivedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
  detectedValue: 40.2,
  unit: 'celsius',
  thresholdMinValue: 37.5,
  thresholdMaxValue: 39.5,
  configurationRevision: 1,
  readingIds: const <String>['b7777777-7777-4777-8777-777777777777'],
);

EdgeAlertPage _page(List<EdgeAlert> items) => EdgeAlertPage(
  page: 1,
  pageSize: 20,
  totalCount: items.length,
  items: items,
);

final class _Fixture {
  const _Fixture({
    required this.repository,
    required this.service,
    required this.language,
  });

  final FakeEdgeAlertRepository repository;
  final EdgeAlertReadService service;
  final LanguageService language;
}
