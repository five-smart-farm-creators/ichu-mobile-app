import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/layout/public_shell.dart';
import 'core/layout/terms_page.dart';
import 'core/theme/ichu_theme.dart';
import 'features/cattle_information/application/services/cattle_management_service.dart';
import 'features/cattle_information/application/services/cattle_read_service.dart';
import 'features/cattle_information/presentation/pages/cattle_list_page.dart';
import 'features/cattle_information/presentation/pages/cattle_profile_page.dart';
import 'features/iam/application/services/auth_service.dart';
import 'features/iam/application/services/registration_service.dart';
import 'features/iam/application/services/professional_profile_service.dart';
import 'features/iam/application/services/ranch_selection_service.dart';
import 'features/iam/application/services/herd_advisory_service.dart';
import 'features/iam/domain/model/iam_account.dart';
import 'features/iam/presentation/pages/login_page.dart';
import 'features/iam/presentation/pages/recovery_page.dart';
import 'features/iam/presentation/pages/registration_page.dart';
import 'features/iam/presentation/pages/professional_profile_page.dart';
import 'features/iam/presentation/pages/ranch_selection_page.dart';
import 'features/iam/presentation/pages/session_account_page.dart';
import 'features/iam/presentation/pages/herd_advisory_page.dart';
import 'features/operations_monitoring/application/services/monitoring_read_service.dart';
import 'features/operations_monitoring/application/services/alert_read_service.dart';
import 'features/operations_monitoring/presentation/pages/animal_monitoring_page.dart';
import 'features/operations_monitoring/presentation/pages/ranch_alerts_page.dart';
import 'shared/application/services/language_service.dart';
import 'shared/infrastructure/i18n/generated/app_localizations.dart';

/// Keeps one router for the app lifetime; locale changes never reset navigation.
final class IchuApp extends StatefulWidget {
  const IchuApp({
    super.key,
    required this.language,
    required this.authentication,
    required this.registration,
    required this.profileService,
    required this.ranchSelection,
    required this.cattleService,
    required this.herdAdvisoryService,
    required this.cattleManagementService,
    required this.monitoringService,
    required this.alertService,
    this.initialRoute = '/',
    this.onDispose,
  });

  final LanguageService language;
  final AuthService authentication;
  final RegistrationService registration;
  final ProfessionalProfileService profileService;
  final RanchSelectionService ranchSelection;
  final CattleReadService cattleService;
  final HerdAdvisoryService herdAdvisoryService;
  final CattleManagementService cattleManagementService;
  final MonitoringReadService monitoringService;
  final AlertReadService alertService;
  final String initialRoute;
  final VoidCallback? onDispose;

  @override
  State<IchuApp> createState() => _IchuAppState();
}

final class _IchuAppState extends State<IchuApp> with WidgetsBindingObserver {
  late GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = _createRouter();
    unawaited(widget.authentication.initialize());
  }

  @override
  void didUpdateWidget(covariant IchuApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authentication != widget.authentication ||
        oldWidget.ranchSelection != widget.ranchSelection ||
        oldWidget.cattleService != widget.cattleService ||
        oldWidget.herdAdvisoryService != widget.herdAdvisoryService ||
        oldWidget.cattleManagementService != widget.cattleManagementService ||
        oldWidget.monitoringService != widget.monitoringService ||
        oldWidget.alertService != widget.alertService) {
      _router.dispose();
      _router = _createRouter();
      unawaited(widget.authentication.initialize());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.authentication.status == SessionStatus.authenticated) {
      unawaited(widget.authentication.refresh());
    }
  }

  void _backFromTerms() {
    if (_router.canPop()) {
      _router.pop();
    } else {
      _router.go(
        widget.authentication.status == SessionStatus.authenticated
            ? '/account'
            : '/login',
      );
    }
  }

  GoRouter _createRouter() => GoRouter(
    initialLocation: widget.initialRoute,
    refreshListenable: Listenable.merge([
      widget.authentication,
      widget.ranchSelection,
    ]),
    redirect: (context, state) {
      final signedIn =
          widget.authentication.status == SessionStatus.authenticated;
      final path = state.uri.path;
      if (path == '/') return signedIn ? '/account' : '/login';
      if ((path == '/account' || path.startsWith('/account/')) && !signedIn) {
        return '/login';
      }
      if (signedIn &&
          (path == '/login' || path == '/recover' || path == '/register')) {
        return '/account';
      }
      if (signedIn &&
          path == '/account/advisories' &&
          widget.authentication.account?.role == AccountRole.fieldOperator) {
        return '/account';
      }
      if (signedIn &&
          (path == '/account/animals' ||
              path.startsWith('/account/animals/'))) {
        final selected = widget.ranchSelection.selectedRanch;
        if (selected == null || !widget.cattleService.hasContext) {
          return '/account/ranches';
        }
        if (path.endsWith('/monitoring') &&
            !widget.monitoringService.hasContext) {
          return '/account/ranches';
        }
        final routeRanch = state.pathParameters['ranchId'];
        if (routeRanch != null &&
            routeRanch.toLowerCase() != selected.ranchId.toLowerCase()) {
          return '/account/animals';
        }
      }
      if (signedIn &&
          path == '/account/alerts' &&
          (widget.ranchSelection.selectedRanch == null ||
              !widget.alertService.hasContext)) {
        return '/account/ranches';
      }
      // External return URLs and unrecognized destinations are never followed.
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/login'),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(
          language: widget.language,
          authentication: widget.authentication,
          onRecover: () {
            widget.authentication.clearError();
            _router.push('/recover');
          },
          onRegister: () => _router.push('/register'),
          onOpenTerms: () => _router.push('/terms'),
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => RegistrationPage(
          language: widget.language,
          registration: widget.registration,
          onBack: () => _router.go('/login'),
          onOpenTerms: () => _router.push('/terms'),
        ),
      ),
      GoRoute(
        path: '/recover',
        builder: (context, state) => RecoveryPage(
          language: widget.language,
          authentication: widget.authentication,
          onBack: () {
            widget.authentication.clearError();
            _router.go('/login');
          },
        ),
      ),
      GoRoute(
        path: '/account',
        builder: (context, state) => SessionAccountPage(
          language: widget.language,
          authentication: widget.authentication,
          ranchSelection: widget.ranchSelection,
          onOpenTerms: () => _router.push('/terms'),
          onOpenProfile: () => _router.push('/account/profile'),
          onOpenRanches: () => _router.push('/account/ranches'),
          onOpenAnimals: () => _router.push('/account/animals'),
          onOpenAlerts: () => _router.push('/account/alerts'),
          onOpenAdvisories: () => _router.push('/account/advisories'),
        ),
        routes: [
          GoRoute(
            path: 'advisories',
            builder: (context, state) => HerdAdvisoryPage(
              language: widget.language,
              service: widget.herdAdvisoryService,
              selection: widget.ranchSelection,
              onBack: () => _router.go('/account'),
            ),
          ),
          GoRoute(
            path: 'alerts',
            builder: (context, state) => RanchAlertsPage(
              language: widget.language,
              service: widget.alertService,
              onBack: () => _router.go('/account'),
              onOpenRanches: () => _router.go('/account/ranches'),
            ),
          ),
          GoRoute(
            path: 'animals/:ranchId/:cattleId/monitoring',
            builder: (context, state) => AnimalMonitoringPage(
              language: widget.language,
              service: widget.monitoringService,
              cattleId: state.pathParameters['cattleId']!,
              onBack: () {
                widget.monitoringService.clear();
                _router.go(
                  '/account/animals/${Uri.encodeComponent(state.pathParameters['ranchId']!)}/${Uri.encodeComponent(state.pathParameters['cattleId']!)}',
                );
              },
              onOpenRanches: () => _router.go('/account/ranches'),
            ),
          ),
          GoRoute(
            path: 'animals',
            builder: (context, state) => CattleListPage(
              language: widget.language,
              service: widget.cattleService,
              management: widget.cattleManagementService,
              onBack: () => _router.go('/account'),
              onOpenRanches: () => _router.go('/account/ranches'),
              onOpenCattle: (id) {
                final ranch = widget.ranchSelection.selectedRanch;
                if (ranch == null) return;
                _router.push(
                  '/account/animals/${Uri.encodeComponent(ranch.ranchId)}/${Uri.encodeComponent(id)}',
                );
              },
            ),
            routes: [
              GoRoute(
                path: ':ranchId/:cattleId',
                builder: (context, state) => CattleProfilePage(
                  language: widget.language,
                  service: widget.cattleService,
                  management: widget.cattleManagementService,
                  cattleId: state.pathParameters['cattleId']!,
                  onBack: () {
                    widget.cattleService.clearProfile();
                    _router.go('/account/animals');
                  },
                  onOpenRanches: () => _router.go('/account/ranches'),
                  onOpenMonitoring: (id) {
                    final ranch = widget.ranchSelection.selectedRanch;
                    if (ranch == null ||
                        ranch.ranchId.toLowerCase() !=
                            state.pathParameters['ranchId']!.toLowerCase()) {
                      return;
                    }
                    _router.push(
                      '/account/animals/${Uri.encodeComponent(ranch.ranchId)}/${Uri.encodeComponent(id)}/monitoring',
                    );
                  },
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'ranches',
            builder: (context, state) => RanchSelectionPage(
              language: widget.language,
              selection: widget.ranchSelection,
              onBack: () => _router.go('/account'),
            ),
          ),
          GoRoute(
            path: 'profile',
            builder: (context, state) => ProfessionalProfilePage(
              language: widget.language,
              profileService: widget.profileService,
              onBack: () => _router.go('/account'),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) =>
            TermsPage(language: widget.language, onBack: _backFromTerms),
      ),
    ],
    errorBuilder: (context, state) {
      final strings = AppLocalizations.of(context);
      return PublicShell(
        language: widget.language,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.notFoundTitle,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 16),
            Text(strings.notFoundBody),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _router.go('/'),
              child: Text(strings.notFoundBack),
            ),
          ],
        ),
      );
    },
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.language,
    builder: (context, _) => MaterialApp.router(
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: IchuTheme.light,
      themeMode: ThemeMode.light,
      locale: Locale(widget.language.current.code),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}
