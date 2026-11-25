import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/cattle_information/application/services/cattle_read_service.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_date.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_failure.dart';
import 'package:ichu_mobile_app/features/cattle_information/domain/model/cattle_search.dart';
import 'package:ichu_mobile_app/features/cattle_information/presentation/pages/cattle_list_page.dart';
import 'package:ichu_mobile_app/features/cattle_information/presentation/pages/cattle_profile_page.dart';
import 'package:ichu_mobile_app/features/iam/application/facades/authorized_ranch_session.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import 'support/fake_cattle_repository.dart';
import 'support/fake_iam_repositories.dart';
import 'support/memory_language_preferences.dart';

const _ranchId = '11111111-1111-4111-8111-111111111111';
const _otherRanchId = '22222222-2222-4222-8222-222222222222';
const _cattleId = '33333333-3333-4333-8333-333333333333';
const _identity = AuthUser(
  uid: 'cattle-widget-user',
  email: 'rancher@example.test',
  emailVerified: true,
);

void main() {
  testWidgets(
    'missing ranch offers the selection action without a repository read',
    (tester) async {
      final fixture = await _pump(tester, ranches: const <RanchAccess>[]);
      expect(fixture.cattle.listCalls, 0);
      expect(fixture.service.hasContext, isFalse);
      expect(find.byKey(const Key('cattle-choose-ranch')), findsOneWidget);
      expect(find.byKey(const Key('cattle-search')), findsNothing);
      await _tap(tester, find.byKey(const Key('cattle-choose-ranch')));
      expect(fixture.openRanches, 1);
    },
  );

  testWidgets(
    'empty list, exact trimmed case-sensitive query, status filter, and reset',
    (tester) async {
      final fixture = await _pump(tester);
      fixture.cattle.listResult = <Cattle>[];
      await fixture.service.load();
      await tester.pumpAndSettle();
      expect(
        find.text(
          AppLocalizations.of(
            tester.element(find.byType(CattleListPage)),
          ).cattleEmpty,
        ),
        findsOneWidget,
      );

      fixture.cattle.listResult = <Cattle>[
        _animal(
          id: _cattleId,
          earTag: 'Tag-Exact',
          status: CattleStatus.inactive,
        ),
      ];
      final field = find.byKey(const Key('cattle-ear-tag'));
      await tester.enterText(field, '  Tag-Exact  ');
      await _tap(tester, find.byKey(const ValueKey('cattle-status-null-0')));
      final inactive = find
          .text(
            AppLocalizations.of(
              tester.element(find.byType(CattleListPage)),
            ).cattleStatusInactive,
          )
          .last;
      await _tap(tester, inactive);
      await _tap(tester, find.byKey(const Key('cattle-search')));
      expect(fixture.cattle.listRequests.last.query.earTag, 'Tag-Exact');
      expect(
        fixture.cattle.listRequests.last.query.status,
        CattleStatus.inactive,
      );
      expect(find.text('Tag-Exact'), findsOneWidget);
      expect(find.text('Tag-Exact'.toLowerCase()), findsNothing);

      await _tap(tester, find.byKey(const Key('cattle-reset')));
      expect(fixture.cattle.listRequests.last.query, const CattleSearch());
      expect(tester.widget<TextFormField>(field).controller!.text, isEmpty);
    },
  );

  testWidgets(
    'list exposes only returned cattle and opens the selected profile',
    (tester) async {
      final fixture = await _pump(tester);
      fixture.cattle.listResult = <Cattle>[
        _animal(id: _cattleId, earTag: 'Returned-42'),
        _animal(
          id: '44444444-4444-4444-8444-444444444444',
          earTag: 'Returned-43',
          status: CattleStatus.inactive,
        ),
      ];
      await fixture.service.load();
      await tester.pumpAndSettle();
      expect(find.text('Returned-42'), findsOneWidget);
      expect(find.text('Returned-43'), findsOneWidget);
      expect(find.text('Invented location'), findsNothing);
      expect(find.text('Age: 4 years'), findsNothing);
      await _tap(tester, find.byKey(Key('cattle-open-$_cattleId')));
      expect(fixture.openedCattle, _cattleId);
    },
  );

  testWidgets(
    'paging advances only on a full page and previous preserves query',
    (tester) async {
      final fixture = await _pump(tester);
      fixture.cattle.listResult = <Cattle>[
        for (var i = 1; i <= 20; i++)
          _animal(
            id: '55555555-5555-4555-8555-${i.toString().padLeft(12, '0')}',
            earTag: 'Tag-$i',
          ),
      ];
      await tester.enterText(find.byKey(const Key('cattle-ear-tag')), 'Kept');
      await _tap(tester, find.byKey(const ValueKey('cattle-status-null-0')));
      final active = find
          .text(
            AppLocalizations.of(
              tester.element(find.byType(CattleListPage)),
            ).cattleStatusActive,
          )
          .last;
      await _tap(tester, active);
      await _tap(tester, find.byKey(const Key('cattle-search')));
      final next = find.byKey(const Key('cattle-next'));
      expect(tester.widget<TextButton>(next).onPressed, isNotNull);
      await _tap(tester, next);
      expect(fixture.cattle.listRequests.last.query.page, 2);
      expect(fixture.cattle.listRequests.last.query.earTag, 'Kept');
      expect(
        fixture.cattle.listRequests.last.query.status,
        CattleStatus.active,
      );

      fixture.cattle.listResult = <Cattle>[];
      await fixture.service.load();
      await tester.pumpAndSettle();
      expect(fixture.cattle.listRequests.last.query.page, 2);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('cattle-next')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('cattle-previous')))
            .onPressed,
        isNotNull,
      );

      fixture.cattle.listResult = <Cattle>[
        for (var i = 1; i <= 20; i++)
          _animal(
            id: '77777777-7777-4777-8777-${i.toString().padLeft(12, '0')}',
            earTag: 'Back-$i',
          ),
      ];
      await _tap(tester, find.byKey(const Key('cattle-previous')));
      expect(fixture.cattle.listRequests.last.query.page, 1);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('cattle-next')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'reload preserves committed filters; retry hides server details',
    (tester) async {
      final fixture = await _pump(tester);
      fixture.cattle.listFailure = const CattleFailure(
        CattleFailureCode.network,
      );
      await tester.enterText(
        find.byKey(const Key('cattle-ear-tag')),
        'Retry-7',
      );
      await _tap(tester, find.byKey(const ValueKey('cattle-status-null-0')));
      final inactive = find
          .text(
            AppLocalizations.of(
              tester.element(find.byType(CattleListPage)),
            ).cattleStatusInactive,
          )
          .last;
      await _tap(tester, inactive);
      await _tap(tester, find.byKey(const Key('cattle-search')));
      expect(
        find.textContaining(
          RegExp('network|server|exception', caseSensitive: false),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('cattle-search')), findsOneWidget);

      fixture.cattle.listFailure = null;
      fixture.cattle.listResult = <Cattle>[
        _animal(
          id: _cattleId,
          earTag: 'Retry-7',
          status: CattleStatus.inactive,
        ),
      ];
      await _tap(tester, find.byKey(const Key('cattle-search')));
      expect(fixture.cattle.listRequests.last.query.earTag, 'Retry-7');
      expect(
        fixture.cattle.listRequests.last.query.status,
        CattleStatus.inactive,
      );
      expect(
        find
            .text('Retry-7', skipOffstage: true)
            .evaluate()
            .where((element) => element.widget is Text),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'pending list is visibly loading and never offers editable animal fields',
    (tester) async {
      final fixture = await _pump(tester);
      final response = Completer<List<Cattle>>();
      fixture.cattle.listCompleter = response;
      try {
        final loading = fixture.service.load(
          query: const CattleSearch(earTag: 'Pending'),
        );
        await tester.pump();
        expect(fixture.service.status, CattleLoadStatus.loading);
        expect(find.byKey(const Key('cattle-ear-tag')), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('cattle-ear-tag')))
              .enabled,
          isFalse,
        );
        expect(find.byType(TextFormField), findsOneWidget);
        response.complete(<Cattle>[_animal(id: _cattleId, earTag: 'Pending')]);
        await loading;
        await tester.pumpAndSettle();
        expect(find.text('Pending'), findsOneWidget);
      } finally {
        if (!response.isCompleted) response.complete(<Cattle>[]);
      }
    },
  );

  testWidgets('ranch switch and logout clear visible list and search draft', (
    tester,
  ) async {
    final fixture = await _pump(tester, ranches: _ranches);
    fixture.cattle.listResult = <Cattle>[
      _animal(id: _cattleId, earTag: 'Private-Tag'),
    ];
    await fixture.service.load();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cattle-ear-tag')),
      'draft text',
    );
    fixture.selection.select(_otherRanchId);
    await tester.pumpAndSettle();
    expect(find.text('Private-Tag'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('cattle-ear-tag')))
          .controller!
          .text,
      isEmpty,
    );

    fixture.selection.select(_ranchId);
    await fixture.service.load();
    await tester.pumpAndSettle();
    final signingOut = fixture.auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Private-Tag'), findsNothing);
    expect(fixture.service.hasContext, isFalse);
    await signingOut;
  });

  testWidgets(
    'ranch switch and logout hide profile snapshots while reads are pending',
    (tester) async {
      final fixture = await _pump(tester, ranches: _ranches);
      fixture.cattle.profileResult = CattleProfile(
        cattle: _animal(id: _cattleId, earTag: 'Ranch-One-Profile'),
        device: const CattleDevice(isAvailable: true),
      );
      await tester.pumpWidget(_profileApp(fixture, _cattleId));
      await tester.pumpAndSettle();
      expect(find.text('Ranch-One-Profile'), findsOneWidget);

      final switchedRequest = Completer<CattleProfile>();
      fixture.cattle.profileCompleter = switchedRequest;
      try {
        await _tap(tester, find.byKey(const Key('cattle-profile-reload')));
        expect(find.byKey(const Key('cattle-profile-data')), findsNothing);
        fixture.selection.select(_otherRanchId);
        await tester.pumpAndSettle();
        expect(find.text('Ranch-One-Profile'), findsNothing);
        switchedRequest.complete(
          CattleProfile(
            cattle: _animal(id: _cattleId),
            device: const CattleDevice(isAvailable: true),
          ),
        );
        await tester.pumpAndSettle();
      } finally {
        if (!switchedRequest.isCompleted) {
          switchedRequest.complete(
            CattleProfile(
              cattle: _animal(id: _cattleId),
              device: const CattleDevice(isAvailable: true),
            ),
          );
        }
      }

      fixture.cattle.profileCompleter = null;
      fixture.cattle.profileResult = CattleProfile(
        cattle: _animal(
          id: _cattleId,
          ranchId: _otherRanchId,
          earTag: 'Ranch-Two-Profile',
        ),
        device: const CattleDevice(isAvailable: true),
      );
      await fixture.service.loadProfile(_cattleId);
      await tester.pumpAndSettle();
      expect(find.text('Ranch-Two-Profile'), findsOneWidget);

      final logoutRequest = Completer<CattleProfile>();
      fixture.cattle.profileCompleter = logoutRequest;
      try {
        await _tap(tester, find.byKey(const Key('cattle-profile-reload')));
        expect(find.byKey(const Key('cattle-profile-data')), findsNothing);
        final signingOut = fixture.auth.signOut();
        await tester.pumpAndSettle();
        expect(find.text('Ranch-Two-Profile'), findsNothing);
        expect(fixture.service.hasContext, isFalse);
        logoutRequest.complete(
          CattleProfile(
            cattle: _animal(id: _cattleId, ranchId: _otherRanchId),
            device: const CattleDevice(isAvailable: true),
          ),
        );
        await signingOut;
        await tester.pumpAndSettle();
      } finally {
        if (!logoutRequest.isCompleted) {
          logoutRequest.complete(
            CattleProfile(
              cattle: _animal(id: _cattleId, ranchId: _otherRanchId),
              device: const CattleDevice(isAvailable: true),
            ),
          );
        }
      }
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets(
      '${language.code} profile reports device availability truthfully and dates without timezone conversion',
      (tester) async {
        final fixture = await _pump(tester, language: language);
        final received = DateTime.utc(2024, 2, 3, 10, 11);
        final cases = <({String id, CattleDevice device})>[
          (id: _cattleId, device: const CattleDevice(isAvailable: false)),
          (
            id: '44444444-4444-4444-8444-444444444444',
            device: const CattleDevice(isAvailable: true),
          ),
          (
            id: '55555555-5555-4555-8555-555555555555',
            device: const CattleDevice(isAvailable: true, collarId: 'COLLAR-9'),
          ),
          (
            id: '66666666-6666-4666-8666-666666666666',
            device: CattleDevice(
              isAvailable: true,
              collarId: 'COLLAR-10',
              lastReadingReceivedAt: received,
            ),
          ),
        ];
        final strings = AppLocalizations.of(
          tester.element(find.byType(CattleListPage)),
        );
        for (final testCase in cases) {
          fixture.cattle.profileResult = CattleProfile(
            cattle: _animal(
              id: testCase.id,
              earTag: 'Profile-${testCase.id.substring(0, 4)}',
            ),
            device: testCase.device,
          );
          await tester.pumpWidget(_profileApp(fixture, testCase.id));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('cattle-profile-data')), findsOneWidget);
          expect(
            find.text(
              DateFormat.yMMMd(
                strings.localeName,
              ).format(DateTime.utc(2020, 1, 2)),
            ),
            findsOneWidget,
          );
          if (!testCase.device.isAvailable) {
            expect(find.text(strings.cattleDeviceUnavailable), findsOneWidget);
            expect(find.text(strings.cattleNoCollar), findsNothing);
          } else if (testCase.device.collarId == null) {
            expect(find.text(strings.cattleNoCollar), findsOneWidget);
            expect(find.text(strings.cattleDeviceUnavailable), findsNothing);
          } else {
            expect(find.text(testCase.device.collarId!), findsOneWidget);
            expect(
              find.text(
                testCase.device.lastReadingReceivedAt == null
                    ? strings.cattleNoCommunication
                    : strings.cattleLastReceived,
              ),
              findsOneWidget,
            );
            if (testCase.device.lastReadingReceivedAt != null) {
              final receivedLabel = DateFormat.yMMMd(strings.localeName)
                  .add_jm()
                  .format(testCase.device.lastReadingReceivedAt!.toLocal());
              expect(find.text(receivedLabel), findsOneWidget);
            }
          }
        }
      },
    );
  }

  testWidgets(
    'profile shows half-open stage history and inactive exit metadata, and never retains a denied snapshot',
    (tester) async {
      final fixture = await _pump(tester);
      final exited = _animal(
        id: _cattleId,
        earTag: 'Exited-1',
        status: CattleStatus.inactive,
        exitReason: CattleExitReason.sale,
        exitDate: const CattleDate(2023, 8, 9),
        periods: const <CattleStagePeriod>[
          CattleStagePeriod(
            id: 'old-stage',
            stage: CattleStage.calf,
            validFrom: CattleDate(2020, 1, 1),
            validTo: CattleDate(2020, 9, 1),
          ),
          CattleStagePeriod(
            id: 'current-stage',
            stage: CattleStage.heifer,
            validFrom: CattleDate(2020, 9, 1),
          ),
        ],
      );
      fixture.cattle.profileResult = CattleProfile(
        cattle: exited,
        device: const CattleDevice(isAvailable: true),
      );
      await tester.pumpWidget(_profileApp(fixture, _cattleId));
      await tester.pumpAndSettle();
      final strings = AppLocalizations.of(
        tester.element(find.byType(CattleProfilePage)),
      );
      expect(find.text(strings.cattleStatusInactive), findsOneWidget);
      expect(find.text(strings.cattleExitSale), findsOneWidget);
      expect(find.textContaining(strings.cattlePeriodUntil), findsOneWidget);
      expect(find.text(strings.cattlePeriodOpen), findsOneWidget);

      fixture.cattle.profileFailure = const CattleFailure(
        CattleFailureCode.forbidden,
      );
      await _tap(tester, find.byKey(const Key('cattle-profile-reload')));
      expect(find.byKey(const Key('cattle-profile-data')), findsNothing);
      expect(find.text('Exited-1'), findsNothing);
      expect(
        find.textContaining(
          RegExp('forbidden|denied|server', caseSensitive: false),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('not-found profile never reveals an earlier profile snapshot', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    fixture.cattle.profileResult = CattleProfile(
      cattle: _animal(id: _cattleId, earTag: 'Previous-Profile'),
      device: const CattleDevice(isAvailable: true),
    );
    await tester.pumpWidget(_profileApp(fixture, _cattleId));
    await tester.pumpAndSettle();
    expect(find.text('Previous-Profile'), findsOneWidget);
    fixture.cattle.profileFailure = const CattleFailure(
      CattleFailureCode.notFound,
    );
    await _tap(tester, find.byKey(const Key('cattle-profile-reload')));
    expect(find.byKey(const Key('cattle-profile-data')), findsNothing);
    expect(find.text('Previous-Profile'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('language change preserves list route and committed query', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    fixture.cattle.listResult = <Cattle>[
      _animal(id: _cattleId, earTag: 'Locale-Tag'),
    ];
    await fixture.service.load(query: const CattleSearch(earTag: 'Locale-Tag'));
    await tester.pumpAndSettle();
    await _tap(tester, find.byType(PopupMenuButton<AppLanguage>));
    await _tap(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<AppLanguage> &&
            widget.value == AppLanguage.spanish,
      ),
    );
    expect(fixture.language.current, AppLanguage.spanish);
    expect(fixture.service.query.earTag, 'Locale-Tag');
    expect(find.text('Locale-Tag'), findsOneWidget);
    expect(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(CattleListPage)),
        ).cattleTitle,
      ),
      findsOneWidget,
    );
    await _tap(
      tester,
      find.byTooltip(
        AppLocalizations.of(
          tester.element(find.byType(CattleListPage)),
        ).cattleBackAccount,
      ),
    );
    expect(fixture.backCalls, 1);
    expect(fixture.service.query.earTag, 'Locale-Tag');
  });

  testWidgets('keyboard inset preserves scroll and labeled touch controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final semantics = tester.ensureSemantics();
    _Fixture? fixture;
    try {
      fixture = await _pump(tester);
      final search = find.byKey(const Key('cattle-search'));
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSemantics(find.byKey(const Key('cattle-ear-tag'))).label,
        isNotEmpty,
      );
      expect(tester.getSize(search).height, greaterThanOrEqualTo(48));
    } finally {
      semantics.dispose();
      fixture?.dispose();
    }
  });

  for (final language in AppLanguage.values) {
    for (final platform in const <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      for (final profile in <bool>[false, true]) {
        for (final landscape in <bool>[false, true]) {
          testWidgets(
            '${language.code}/${platform.name}/${profile ? 'profile' : 'list'}/${landscape ? 'landscape' : 'narrow'} scales and scrolls',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = landscape
                  ? const Size(640, 360)
                  : const Size(320, 568);
              tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              addTearDown(
                tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
              );
              final fixture = await _pump(
                tester,
                language: language,
                platform: platform,
              );
              if (profile) {
                fixture.cattle.profileResult = CattleProfile(
                  cattle: _animal(id: _cattleId),
                  device: const CattleDevice(
                    isAvailable: true,
                    collarId: 'COLLAR-320',
                  ),
                );
                await tester.pumpWidget(_profileApp(fixture, _cattleId));
              } else {
                fixture.cattle.listResult = <Cattle>[_animal(id: _cattleId)];
                await fixture.service.load();
                await tester.pumpWidget(_listApp(fixture));
              }
              await tester.pumpAndSettle();
              final key = profile
                  ? const Key('cattle-profile-reload')
                  : const Key('cattle-open-$_cattleId');
              await tester.ensureVisible(find.byKey(key));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }

  testWidgets('list and profile controls remain labeled and accessible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    _Fixture? fixture;
    try {
      fixture = await _pump(tester);
      fixture.cattle.listResult = <Cattle>[_animal(id: _cattleId)];
      await fixture.service.load();
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(
        tester.getSemantics(find.byKey(const Key('cattle-ear-tag'))).label,
        isNotEmpty,
      );
      fixture.cattle.profileResult = CattleProfile(
        cattle: _animal(id: _cattleId),
        device: const CattleDevice(isAvailable: true, collarId: 'COLLAR-A11Y'),
      );
      await tester.pumpWidget(_profileApp(fixture, _cattleId));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(find.byType(TextFormField), findsNothing);
    } finally {
      semantics.dispose();
      fixture?.dispose();
    }
  });
}

Widget _listApp(_Fixture fixture) => _app(
  fixture,
  CattleListPage(
    language: fixture.language,
    service: fixture.service,
    onBack: () => fixture.backCalls++,
    onOpenRanches: () => fixture.openRanches++,
    onOpenCattle: (id) => fixture.openedCattle = id,
  ),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Widget _profileApp(_Fixture fixture, String id) => _app(
  fixture,
  CattleProfilePage(
    language: fixture.language,
    service: fixture.service,
    cattleId: id,
    onBack: () => fixture.backCalls++,
    onOpenRanches: () => fixture.openRanches++,
  ),
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

Future<_Fixture> _pump(
  WidgetTester tester, {
  List<RanchAccess> ranches = const <RanchAccess>[_defaultRanch],
  AppLanguage language = AppLanguage.english,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  final authenticationRepository = FakeAuthenticationRepository(
    user: _identity,
  );
  final accounts = FakeAccountRepository(account: _account, ranches: ranches);
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
  final cattle = FakeCattleRepository();
  final service = CattleReadService(access: access, cattle: cattle);
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
    cattle: cattle,
    service: service,
    language: languageService,
    platform: platform,
  );
  addTearDown(fixture.dispose);
  await tester.pumpWidget(_listApp(fixture));
  await tester.pumpAndSettle();
  return fixture;
}

const _account = IamAccount(
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  email: 'rancher@example.test',
  role: AccountRole.ranchManager,
  status: 'active',
);
const _defaultRanch = RanchAccess(
  ranchId: _ranchId,
  scope: AccessScope.read,
  name: 'Selected ranch',
  region: 'Central Region',
  district: 'North District',
);
final _ranches = <RanchAccess>[
  _defaultRanch,
  const RanchAccess(
    ranchId: _otherRanchId,
    scope: AccessScope.read,
    name: 'Second ranch',
    region: 'West Region',
    district: 'South District',
  ),
];

Cattle _animal({
  String id = _cattleId,
  String ranchId = _ranchId,
  String earTag = 'TAG-1',
  CattleStatus status = CattleStatus.active,
  CattleExitReason? exitReason,
  CattleDate? exitDate,
  List<CattleStagePeriod> periods = const <CattleStagePeriod>[
    CattleStagePeriod(
      id: 'period-1',
      stage: CattleStage.heifer,
      validFrom: CattleDate(2021, 1, 1),
    ),
  ],
}) => Cattle(
  id: id,
  ranchId: ranchId,
  earTag: earTag,
  breed: CattleBreed.brownSwiss,
  sex: CattleSex.female,
  birthDate: const CattleDate(2020, 1, 2),
  currentStage: CattleStage.heifer,
  status: status,
  version: 'fixture-v1',
  stagePeriods: periods,
  exitReason:
      exitReason ??
      (status == CattleStatus.inactive ? CattleExitReason.sale : null),
  exitDate:
      exitDate ??
      (status == CattleStatus.inactive ? const CattleDate(2023, 8, 9) : null),
);

final class _Fixture {
  _Fixture({
    required this.authenticationRepository,
    required this.lifecycle,
    required this.auth,
    required this.selection,
    required this.access,
    required this.cattle,
    required this.service,
    required this.language,
    required this.platform,
  });

  final FakeAuthenticationRepository authenticationRepository;
  final AuthenticationLifecycle lifecycle;
  final AuthService auth;
  final RanchSelectionService selection;
  final AuthorizedRanchSession access;
  final FakeCattleRepository cattle;
  final CattleReadService service;
  final LanguageService language;
  final TargetPlatform platform;
  int openRanches = 0;
  int backCalls = 0;
  String? openedCattle;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    service.dispose();
    access.dispose();
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    language.dispose();
    unawaited(authenticationRepository.close());
  }
}
