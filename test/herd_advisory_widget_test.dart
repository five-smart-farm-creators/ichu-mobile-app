import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ichu_mobile_app/core/theme/ichu_theme.dart';
import 'package:ichu_mobile_app/features/iam/application/services/auth_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/authentication_lifecycle.dart';
import 'package:ichu_mobile_app/features/iam/application/services/herd_advisory_service.dart';
import 'package:ichu_mobile_app/features/iam/application/services/ranch_selection_service.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/auth_user.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/iam_account.dart';
import 'package:ichu_mobile_app/features/iam/domain/model/ranch_summary.dart';
import 'package:ichu_mobile_app/features/iam/presentation/pages/herd_advisory_page.dart';
import 'package:ichu_mobile_app/shared/application/services/language_service.dart';
import 'package:ichu_mobile_app/shared/infrastructure/i18n/generated/app_localizations.dart';

import 'support/fake_herd_advisory_repository.dart';
import 'support/fake_iam_repositories.dart';
import 'support/memory_language_preferences.dart';

const _ranchId = '11111111-1111-4111-8111-111111111111';
const _privateCode = 'Synthetic-Private-Code';

void main() {
  testWidgets('hides the shared code and shows only the lookup result', (
    tester,
  ) async {
    final repository = FakeHerdAdvisoryRepository(
      ranchResult: const RanchSummary(
        ranchId: _ranchId,
        name: 'North ranch',
        region: 'Cusco',
        district: 'Anta',
      ),
    );
    final identity = FakeAuthenticationRepository(
      user: const AuthUser(
        uid: 'advisory-widget-user',
        email: 'vet@example.test',
        emailVerified: true,
      ),
    );
    final lifecycle = AuthenticationLifecycle(identity);
    final auth = AuthService(
      authentication: lifecycle,
      accounts: FakeAccountRepository(
        account: const IamAccount(
          id: '22222222-2222-4222-8222-222222222222',
          email: 'vet@example.test',
          role: AccountRole.veterinarian,
          status: 'Active',
        ),
      ),
    );
    await auth.initialize();
    final selection = RanchSelectionService(session: auth);
    final preferences = MemoryLanguagePreferences();
    final language = LanguageService(preferences);
    await language.initialize();
    final service = HerdAdvisoryService(
      advisories: repository,
      selection: selection,
    );
    addTearDown(() async {
      selection.dispose();
      auth.dispose();
      lifecycle.dispose();
      language.dispose();
      await identity.close();
    });

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: language,
        builder: (context, _) => MaterialApp(
          theme: IchuTheme.light,
          locale: Locale(language.current.code),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HerdAdvisoryPage(
            language: language,
            service: service,
            selection: selection,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final codeField = find.byKey(const Key('advisory-access-code'));
    expect(tester.widget<TextField>(codeField).obscureText, isTrue);
    await tester.enterText(codeField, _privateCode);
    await tester.tap(find.byKey(const Key('advisory-lookup')));
    await tester.pumpAndSettle();

    expect(repository.lastAccessCode, _privateCode);
    expect(find.text('North ranch'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == _privateCode,
      ),
      findsNothing,
    );

    await tester.enterText(codeField, 'a different code');
    await tester.pump();
    expect(find.text('North ranch'), findsNothing);
    expect(find.byKey(const Key('advisory-submit-request')), findsNothing);
  });
}
