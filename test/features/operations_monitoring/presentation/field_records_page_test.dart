import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/application/services/field_record_service.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/model/field_record_sync.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/domain/repositories/field_cattle_directory.dart';
import 'package:ichu_mobile_app/features/operations_monitoring/presentation/pages/field_records_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import '../../../support/fake_iam_repositories.dart';
import '../../../support/fake_field_record_sync_repository.dart';
import '../../../support/memory_field_record_repository.dart';
import '../../../support/memory_language_preferences.dart';

const _accountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _ranchId = '11111111-1111-4111-8111-111111111111';
const _cattleId = '33333333-3333-4333-8333-333333333333';

void main() {
  for (final language in AppLanguage.values) {
    testWidgets('${language.code} saves a field record locally', (
      tester,
    ) async {
      await _withFixture(tester, (fixture) async {
        await tester.pumpWidget(_app(fixture));
        await tester.pumpAndSettle();
        final strings = _strings(tester);

        await tester.enterText(
          find.byKey(const Key('field-record-cattle-tag')),
          'TAG-7',
        );
        await tester.tap(find.byTooltip(strings.fieldRecordFindCattle));
        await tester.pumpAndSettle();
        expect(
          find.text(strings.fieldRecordSelectedCattle('TAG-7')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('field-record-observation')),
          'Mild lameness',
        );
        await _tap(tester, find.text(strings.fieldRecordSave));

        expect(fixture.records.records, hasLength(1));
        expect(fixture.records.records.single.ranchId, _ranchId);
        expect(fixture.records.records.single.cattleId, _cattleId);
        expect(fixture.records.records.single.observation, 'Mild lameness');
        expect(fixture.cattleDirectory.requestedEarTags, <String>['TAG-7']);
        expect(find.textContaining('Mild lameness'), findsOneWidget);
        expect(fixture.remote.requests, isEmpty);
        await _tap(tester, find.byKey(const Key('field-sync-send')));
        expect(fixture.records.records, isEmpty);
        expect(find.text(strings.fieldSyncConfirmed(1)), findsOneWidget);
        expect(find.text(strings.fieldRecordEmpty), findsOneWidget);
      }, language: language);
    });

    testWidgets(
      '${language.code} keeps uncertain deliveries and retries without new identifiers',
      (tester) async {
        await _withFixture(tester, (fixture) async {
          await _capture(fixture);
          await tester.pumpWidget(_app(fixture));
          await tester.pumpAndSettle();
          final strings = _strings(tester);
          final record = fixture.records.records.single;
          fixture.remote.failure = const FieldRecordSyncFailure(
            FieldRecordSyncFailureCode.network,
          );
          await _tap(tester, find.byKey(const Key('field-sync-send')));
          expect(find.text(strings.fieldSyncConnectionError), findsOneWidget);
          expect(fixture.records.records.single, record);
          expect(fixture.records.canCreate, isTrue);
          fixture.remote.failure = null;
          await _tap(tester, find.byKey(const Key('field-sync-send')));
          expect(fixture.remote.requests.last.records, [record]);
          expect(fixture.records.records, isEmpty);
          expect(find.text(strings.fieldSyncConnectionError), findsNothing);
        }, language: language);
      },
    );

    testWidgets(
      '${language.code} shows a retained conflict without raw server diagnostics',
      (tester) async {
        await _withFixture(tester, (fixture) async {
          await _capture(fixture);
          fixture.remote.respond = (records) => [
            FieldRecordSyncResult(
              operationId: records.single.operationId,
              status: FieldRecordSyncStatus.conflict,
              reason: 'Untrusted synthetic diagnostic',
            ),
          ];
          await tester.pumpWidget(_app(fixture));
          await tester.pumpAndSettle();
          final strings = _strings(tester);
          await _tap(tester, find.byKey(const Key('field-sync-send')));
          expect(
            find.textContaining(strings.fieldSyncConflict),
            findsOneWidget,
          );
          expect(find.text('Untrusted synthetic diagnostic'), findsNothing);
          expect(fixture.records.records, hasLength(1));
        }, language: language);
      },
    );

    for (final (layout, size) in <(String, Size)>[
      ('narrow', const Size(320, 568)),
      ('landscape', const Size(640, 360)),
    ]) {
      testWidgets(
        '${language.code} field records support $layout at large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
          try {
            await _withFixture(tester, (fixture) async {
              await _capture(fixture);
              fixture.remote.respond = (records) => [
                FieldRecordSyncResult(
                  operationId: records.single.operationId,
                  status: FieldRecordSyncStatus.rejected,
                ),
              ];
              await fixture.records.synchronize();
              await tester.pumpWidget(_app(fixture));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await tester.ensureVisible(
                find.byKey(const Key('field-sync-send')),
              );
              await tester.pumpAndSettle();
              expect(
                tester.getSize(find.byKey(const Key('field-sync-send'))).height,
                greaterThanOrEqualTo(48),
              );
              expect(tester.takeException(), isNull);

              final save = find.byKey(const Key('field-record-save'));
              await tester.ensureVisible(save);
              await tester.pumpAndSettle();
              expect(tester.getSize(save).height, greaterThanOrEqualTo(48));
              expect(tester.takeException(), isNull);
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

Future<void> _withFixture(
  WidgetTester tester,
  Future<void> Function(_Fixture fixture) body, {
  required AppLanguage language,
}) async {
  final identity = FakeAuthenticationRepository();
  final accounts = FakeAccountRepository(
    account: const IamAccount(
      id: _accountId,
      email: 'user@example.test',
      role: AccountRole.ranchManager,
      status: 'active',
    ),
    ranches: const <RanchAccess>[
      RanchAccess(
        ranchId: _ranchId,
        scope: AccessScope.manage,
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
    authentication: lifecycle,
  );
  await auth.initialize();
  expect(selection.select(_ranchId), isTrue);

  final cattleDirectory = _FieldCattleDirectory(<FieldCattleOption>[
    FieldCattleOption(cattleId: _cattleId, ranchId: _ranchId, earTag: 'TAG-7'),
  ]);
  final recordRepository = MemoryFieldRecordRepository();
  final remote = FakeFieldRecordSyncRepository();
  final records = FieldRecordService(
    access: access,
    repository: recordRepository,
    syncRepository: remote,
  );
  final languageService = LanguageService(
    MemoryLanguagePreferences(language: language),
  );
  await languageService.initialize();
  final fixture = _Fixture(
    access: access,
    selection: selection,
    auth: auth,
    lifecycle: lifecycle,
    identity: identity,
    cattleDirectory: cattleDirectory,
    records: records,
    language: languageService,
    remote: remote,
  );
  try {
    await body(fixture);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  }
}

Widget _app(_Fixture fixture) => ListenableBuilder(
  listenable: fixture.language,
  builder: (context, _) => MaterialApp(
    theme: IchuTheme.light,
    locale: Locale(fixture.language.current.code),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: FieldRecordsPage(
      language: fixture.language,
      records: fixture.records,
      cattleDirectory: fixture.cattleDirectory,
      onBack: () {},
    ),
  ),
);

AppLocalizations _strings(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(FieldRecordsPage)));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _capture(_Fixture fixture) async {
  await fixture.records.load();
  await fixture.records.cacheCattleOptions([
    FieldCattleOption(cattleId: _cattleId, ranchId: _ranchId, earTag: 'TAG-7'),
  ]);
  await fixture.records.save(
    cattleId: _cattleId,
    cattleEarTag: 'TAG-7',
    type: FieldRecordType.healthEvent,
    occurredAt: DateTime.utc(2020),
    observation: 'Synthetic offline record',
  );
}

final class _Fixture {
  const _Fixture({
    required this.access,
    required this.selection,
    required this.auth,
    required this.lifecycle,
    required this.identity,
    required this.cattleDirectory,
    required this.records,
    required this.language,
    required this.remote,
  });

  final AuthorizedRanchSession access;
  final RanchSelectionService selection;
  final AuthService auth;
  final AuthenticationLifecycle lifecycle;
  final FakeAuthenticationRepository identity;
  final _FieldCattleDirectory cattleDirectory;
  final FieldRecordService records;
  final LanguageService language;
  final FakeFieldRecordSyncRepository remote;

  void dispose() {
    records.dispose();
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    language.dispose();
    unawaited(identity.close());
  }
}

final class _FieldCattleDirectory implements FieldCattleDirectory {
  _FieldCattleDirectory(this.options);

  final List<FieldCattleOption> options;
  final List<String> requestedEarTags = <String>[];

  @override
  Future<List<FieldCattleOption>> findByExactEarTag({
    required String accountId,
    required String ranchId,
    required String earTag,
  }) async {
    requestedEarTags.add(earTag);
    if (accountId != _accountId || ranchId != _ranchId) return const [];
    return options.where((option) => option.earTag == earTag).toList();
  }
}
