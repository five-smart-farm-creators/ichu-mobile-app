import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/core/theme/ichu_colors.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_access.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/ranch_selection_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/domain/model/app_language.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import 'support/fake_iam_repositories.dart';
import 'support/memory_language_preferences.dart';

const _identity = AuthUser(
  uid: 'ranch-selection-widget-user',
  email: 'rancher@example.test',
  emailVerified: true,
);
const _accountId = '11111111-1111-4111-8111-111111111111';
const _accountEmail = 'rancher@example.test';

void main() {
  testWidgets('zero ranches shows the validated-account empty state', (
    tester,
  ) async {
    final fixture = await _pumpPage(tester);

    expect(fixture.selection.canSelect, isTrue);
    expect(
      find.text(
        'Your account does not currently have authorized ranch access.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Sign in with a validated ICHU account to view authorized ranches.',
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('ranch-selected')), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('ranches-refresh')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('one ranch remains unselected until the user chooses it', (
    tester,
  ) async {
    final ranch = _ranch(1, scope: AccessScope.read);
    final fixture = await _pumpPage(tester, ranches: <RanchAccess>[ranch]);

    expect(fixture.selection.selectedRanch, isNull);
    expect(find.byKey(Key('ranch-select-${ranch.ranchId}')), findsOneWidget);
    expect(find.byKey(const Key('ranch-selected')), findsNothing);
  });

  testWidgets('many ranches can be selected, switched, and cleared', (
    tester,
  ) async {
    final fixture = await _pumpPage(tester, ranches: _ranches);
    final first = _ranches[0];
    final second = _ranches[1];
    final firstButton = find.byKey(Key('ranch-select-${first.ranchId}'));
    final secondButton = find.byKey(Key('ranch-select-${second.ranchId}'));

    expect(fixture.selection.selectedRanch, isNull);
    await tester.ensureVisible(firstButton);
    await tester.pumpAndSettle();
    await tester.tap(firstButton);
    await tester.pump();
    expect(fixture.selection.selectedRanch, same(first));
    expect(find.byKey(const Key('ranch-selected')), findsOneWidget);
    expect(tester.widget<FilledButton>(firstButton).onPressed, isNull);

    await tester.ensureVisible(secondButton);
    await tester.pumpAndSettle();
    await tester.tap(secondButton);
    await tester.pump();
    expect(fixture.selection.selectedRanch, same(second));
    expect(find.text('Clinical Ranch'), findsNWidgets(2));

    await tester.ensureVisible(find.byKey(const Key('ranch-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ranch-clear')));
    await tester.pump();
    expect(fixture.selection.selectedRanch, isNull);
    expect(find.byKey(const Key('ranch-selected')), findsNothing);
  });

  testWidgets('refresh hides the old selection while revalidation is pending', (
    tester,
  ) async {
    final fixture = await _pumpPage(tester, ranches: _ranches);
    final ranch = _ranches.first;
    fixture.selection.select(ranch.ranchId);
    await tester.pumpAndSettle();
    final accountSnapshot = Completer<IamAccount>();
    final ranchSnapshot = Completer<List<RanchAccess>>();
    fixture.accounts.currentAccountCompleter = accountSnapshot;
    fixture.accounts.ranchAccessCompleter = ranchSnapshot;

    final refresh = find.byKey(const Key('ranches-refresh'));
    await tester.ensureVisible(refresh);
    await tester.pumpAndSettle();
    await tester.tap(refresh);
    await tester.pump();
    expect(find.text('North Meadow'), findsNothing);
    expect(fixture.selection.selectedRanch, isNull);
    expect(tester.widget<OutlinedButton>(refresh).onPressed, isNull);

    accountSnapshot.complete(_account(AccountRole.ranchManager));
    ranchSnapshot.complete(<RanchAccess>[_ranch(4, scope: AccessScope.read)]);
    await tester.pumpAndSettle();
    expect(find.text('Ranch 4'), findsOneWidget);
    expect(find.text('North Meadow'), findsNothing);
  });

  testWidgets('logout immediately removes ranch data and selection', (
    tester,
  ) async {
    final fixture = await _pumpPage(tester, ranches: _ranches);
    fixture.selection.select(_ranches.first.ranchId);

    final signingOut = fixture.auth.signOut();
    await tester.pump();
    expect(find.text('North Meadow'), findsNothing);
    expect(
      find.text(
        'Sign in with a validated ICHU account to view authorized ranches.',
      ),
      findsOneWidget,
    );
    expect(fixture.selection.selectedRanch, isNull);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('ranches-refresh')))
          .onPressed,
      isNull,
    );
    await signingOut;
    await tester.pumpAndSettle();
    expect(find.text('North Meadow'), findsNothing);
  });

  testWidgets('a rejected refresh cannot reveal the previous snapshot', (
    tester,
  ) async {
    final fixture = await _pumpPage(tester, ranches: _ranches);
    fixture.selection.select(_ranches.first.ranchId);
    fixture.accounts.currentAccountFailure = StateError('synthetic rejection');

    final refresh = fixture.selection.refresh();
    await tester.pump();
    expect(find.text('North Meadow'), findsNothing);
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('North Meadow'), findsNothing);
    expect(fixture.selection.selectedRanch, isNull);
  });

  testWidgets('expired and ambiguous ranch IDs are never presented', (
    tester,
  ) async {
    final duplicate = _ranch(5, scope: AccessScope.read);
    final fixture = await _pumpPage(
      tester,
      ranches: <RanchAccess>[
        ..._ranches,
        _ranch(
          6,
          scope: AccessScope.manage,
          expiresAt: DateTime.utc(2025, 12, 31),
        ),
        duplicate,
        duplicate,
      ],
    );

    expect(find.text('Ranch 6'), findsNothing);
    expect(find.text('Ranch 5'), findsNothing);
    expect(find.text('North Meadow'), findsOneWidget);
    expect(fixture.selection.select(duplicate.ranchId), isFalse);
  });

  for (final language in AppLanguage.values) {
    testWidgets('${language.code} shows location and only real expiry dates', (
      tester,
    ) async {
      final fixture = await _pumpPage(
        tester,
        language: language,
        ranches: <RanchAccess>[
          _ranch(
            10,
            scope: AccessScope.read,
            name: 'Distant Ranch',
            region: 'Southern Region',
            district: 'River District',
            expiresAt: DateTime.utc(2027, 1, 2, 15),
          ),
          _ranch(11, scope: AccessScope.read, name: 'No Expiry Ranch'),
        ],
      );

      try {
        expect(fixture.selection.canSelect, isTrue);
        expect(find.text('Southern Region · River District'), findsOneWidget);
        expect(find.text('No Expiry Ranch'), findsOneWidget);
        expect(
          find.textContaining(RegExp('expires|vence', caseSensitive: false)),
          findsOneWidget,
        );
        expect(
          find.textContaining(RegExp('permanent access', caseSensitive: false)),
          findsNothing,
        );
      } finally {
        // The test owns the service; cancel its timer before binding invariants.
        fixture.selection.dispose();
      }
    });
  }

  for (final role in AccountRole.values) {
    for (final scope in AccessScope.values) {
      testWidgets(
        '${role.name} sees server scope ${scope.name} without tools',
        (tester) async {
          final fixture = await _pumpPage(
            tester,
            role: role,
            ranches: <RanchAccess>[_ranch(7, scope: scope)],
          );

          expect(find.textContaining(_scopeLabel(scope)), findsOneWidget);
          expect(find.byType(FilledButton), findsOneWidget);
          expect(
            find.textContaining(RegExp('invite', caseSensitive: false)),
            findsNothing,
          );
          expect(
            find.textContaining(RegExp('access code', caseSensitive: false)),
            findsNothing,
          );
          expect(
            find.textContaining(RegExp('manage ranch', caseSensitive: false)),
            findsNothing,
          );
          expect(fixture.selection.selectedRanch, isNull);
        },
      );
    }
  }

  for (final language in AppLanguage.values) {
    for (final platform in const <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      for (final landscape in <bool>[false, true]) {
        for (final largeText in <bool>[false, true]) {
          testWidgets(
            '${language.code}/${platform.name}/${landscape ? 'landscape' : 'narrow'}/${largeText ? '200%' : 'normal'} layout',
            (tester) async {
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = landscape
                  ? const Size(640, 360)
                  : const Size(320, 568);
              tester.binding.platformDispatcher.textScaleFactorTestValue =
                  largeText ? 2 : 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              addTearDown(
                tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
              );

              final fixture = await _pumpPage(
                tester,
                ranches: _longRanches,
                language: language,
                platform: platform,
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(fixture.selection.selectedRanch, isNull);

              final choose = find.byKey(
                Key('ranch-select-${_longRanches.first.ranchId}'),
              );
              await tester.ensureVisible(choose);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }

  testWidgets('keyboard insets preserve scrolling and labeled 48px controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPage(tester, ranches: _ranches);

      final refresh = find.byKey(const Key('ranches-refresh'));
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSemantics(refresh).label, contains('Refresh access'));
      for (final button in find.byType(FilledButton).evaluate()) {
        final size = tester.getSize(find.byWidget(button.widget));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(
        _contrastRatio(IchuColors.ink, IchuColors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(IchuColors.forestDeep, IchuColors.background),
        greaterThanOrEqualTo(4.5),
      );
    } finally {
      semantics.dispose();
    }
  });

  for (final language in AppLanguage.values) {
    testWidgets('${language.code} controls meet accessibility guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpPage(tester, ranches: _ranches, language: language);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('locale menu changes language without clearing the choice', (
    tester,
  ) async {
    final fixture = await _pumpPage(tester, ranches: _ranches);
    final ranch = _ranches.first;
    fixture.selection.select(ranch.ranchId);
    await tester.pump();

    await tester.tap(find.byType(PopupMenuButton<AppLanguage>));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<AppLanguage> &&
            widget.value == AppLanguage.spanish,
      ),
    );
    await tester.pumpAndSettle();

    expect(fixture.language.current, AppLanguage.spanish);
    expect(fixture.selection.selectedRanch, same(ranch));
    expect(find.text('Unidades productivas autorizadas'), findsOneWidget);
  });
}

final List<RanchAccess> _ranches = <RanchAccess>[
  _ranch(1, scope: AccessScope.read, name: 'North Meadow'),
  _ranch(2, scope: AccessScope.clinicalWrite, name: 'Clinical Ranch'),
  _ranch(3, scope: AccessScope.manage, name: 'Management Ranch'),
];

final _longRanches = <RanchAccess>[
  for (var index = 8; index <= 9; index++)
    _ranch(
      index,
      scope: AccessScope.read,
      name: List<String>.filled(6, 'Long Server Ranch Name ').join(),
      region: List<String>.filled(7, 'Central Region ').join(),
      district: List<String>.filled(6, 'Northern District ').join(),
    ),
];

RanchAccess _ranch(
  int index, {
  required AccessScope scope,
  String? name,
  String region = 'Central Region',
  String district = 'North District',
  DateTime? expiresAt,
}) => RanchAccess(
  ranchId: '11111111-1111-4111-8111-${index.toString().padLeft(12, '0')}',
  name: name ?? 'Ranch $index',
  region: region,
  district: district,
  scope: scope,
  expiresAt: expiresAt,
);

String _scopeLabel(AccessScope scope) => switch (scope) {
  AccessScope.read => 'Read-only',
  AccessScope.clinicalWrite => 'Clinical records',
  AccessScope.manage => 'Management',
};

Future<_Fixture> _pumpPage(
  WidgetTester tester, {
  List<RanchAccess> ranches = const <RanchAccess>[],
  AccountRole role = AccountRole.ranchManager,
  AppLanguage language = AppLanguage.english,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  final authRepository = FakeAuthenticationRepository(user: _identity);
  final accounts = FakeAccountRepository(
    account: _account(role),
    ranches: ranches,
  );
  final lifecycle = AuthenticationLifecycle(authRepository);
  final auth = AuthService(authentication: lifecycle, accounts: accounts);
  await auth.initialize();
  final selection = RanchSelectionService(
    session: auth,
    now: () => DateTime.utc(2026, 1, 1),
  );
  final preferences = MemoryLanguagePreferences(language: language);
  final languageService = LanguageService(preferences);
  await languageService.initialize();
  addTearDown(() async {
    selection.dispose();
    auth.dispose();
    lifecycle.dispose();
    languageService.dispose();
    await authRepository.close();
  });

  await tester.pumpWidget(
    ListenableBuilder(
      listenable: languageService,
      builder: (context, _) => MaterialApp(
        theme: IchuTheme.light.copyWith(platform: platform),
        locale: Locale(languageService.current.code),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RanchSelectionPage(
          language: languageService,
          selection: selection,
          onBack: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fixture(
    selection: selection,
    auth: auth,
    accounts: accounts,
    language: languageService,
  );
}

IamAccount _account(AccountRole role) => IamAccount(
  id: _accountId,
  email: _accountEmail,
  role: role,
  status: 'Active',
);

double _contrastRatio(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

final class _Fixture {
  const _Fixture({
    required this.selection,
    required this.auth,
    required this.accounts,
    required this.language,
  });

  final RanchSelectionService selection;
  final AuthService auth;
  final FakeAccountRepository accounts;
  final LanguageService language;
}
