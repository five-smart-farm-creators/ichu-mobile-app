import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'features/cattle_information/application/services/cattle_read_service.dart';
import 'features/cattle_information/infrastructure/http/cattle_api_client.dart';
import 'features/cattle_information/infrastructure/repositories/rest_cattle_repository.dart';
import 'features/iam/application/facades/authorized_ranch_session.dart';
import 'features/iam/application/services/auth_service.dart';
import 'features/iam/application/services/authentication_lifecycle.dart';
import 'features/iam/application/services/registration_service.dart';
import 'features/iam/application/services/professional_profile_service.dart';
import 'features/iam/application/services/ranch_selection_service.dart';
import 'features/iam/infrastructure/configuration/firebase_client_config.dart';
import 'features/iam/infrastructure/http/authenticated_api_client.dart';
import 'features/iam/infrastructure/repositories/firebase_auth_repository.dart';
import 'features/iam/infrastructure/repositories/firebase_registration_repository.dart';
import 'features/iam/infrastructure/repositories/iam_account_repository.dart';
import 'features/iam/infrastructure/repositories/iam_professional_profile_repository.dart';
import 'features/iam/infrastructure/repositories/iam_account_registration_repository.dart';
import 'features/operations_monitoring/application/services/monitoring_read_service.dart';
import 'features/operations_monitoring/infrastructure/http/monitoring_api_client.dart';
import 'features/operations_monitoring/infrastructure/repositories/rest_monitoring_repository.dart';
import 'shared/application/services/language_service.dart';
import 'shared/infrastructure/preferences/device_language_preference_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  final language = LanguageService(
    DeviceLanguagePreferenceRepository(SharedPreferencesAsync()),
  );
  await language.initialize();
  final config = AppConfig.fromEnvironment();
  final platform = switch (defaultTargetPlatform) {
    TargetPlatform.android when !kIsWeb => FirebaseNativePlatform.android,
    TargetPlatform.iOS when !kIsWeb => FirebaseNativePlatform.ios,
    _ => FirebaseNativePlatform.unsupported,
  };
  final firebaseConfig = FirebaseClientConfig.fromEnvironment(platform);
  final identity = AuthenticationLifecycle(
    await FirebaseAuthRepository.initialize(firebaseConfig),
  );
  final registrationIdentity = AuthenticationLifecycle(
    await FirebaseRegistrationRepository.initialize(firebaseConfig),
  );
  final client = http.Client();
  final registration = RegistrationService(
    authentication: registrationIdentity,
    accounts: IamAccountRegistrationRepository(
      api: config.isApiConfigured
          ? AuthenticatedApiClient(
              baseUri: config.apiBaseUri!,
              client: client,
              authentication: registrationIdentity,
              languageTag: () =>
                  language.current.code == 'es' ? 'es-419' : 'en-US',
            )
          : null,
    ),
  );
  final api = config.isApiConfigured
      ? AuthenticatedApiClient(
          baseUri: config.apiBaseUri!,
          client: client,
          authentication: identity,
          languageTag: () => language.current.code == 'es' ? 'es-419' : 'en-US',
        )
      : null;
  final authentication = AuthService(
    authentication: identity,
    accounts: IamAccountRepository(api: api),
  );
  final profileService = ProfessionalProfileService(
    session: authentication,
    profiles: IamProfessionalProfileRepository(api: api),
  );
  final ranchSelection = RanchSelectionService(session: authentication);
  final ranchAccess = AuthorizedRanchSession(
    session: authentication,
    selection: ranchSelection,
    authentication: identity,
  );
  final cattleService = CattleReadService(
    access: ranchAccess,
    cattle: RestCattleRepository(
      api: config.isApiConfigured
          ? CattleApiClient(
              baseUri: config.apiBaseUri!,
              client: client,
              session: ranchAccess,
              languageTag: () =>
                  language.current.code == 'es' ? 'es-419' : 'en-US',
            )
          : null,
    ),
  );
  final monitoringService = MonitoringReadService(
    access: ranchAccess,
    monitoring: RestMonitoringRepository(
      api: config.isApiConfigured
          ? MonitoringApiClient(
              baseUri: config.apiBaseUri!,
              client: client,
              session: ranchAccess,
              languageTag: () =>
                  language.current.code == 'es' ? 'es-419' : 'en-US',
            )
          : null,
    ),
  );
  runApp(
    IchuApp(
      language: language,
      authentication: authentication,
      registration: registration,
      profileService: profileService,
      ranchSelection: ranchSelection,
      cattleService: cattleService,
      monitoringService: monitoringService,
      onDispose: () {
        monitoringService.dispose();
        cattleService.dispose();
        ranchAccess.dispose();
        profileService.dispose();
        ranchSelection.dispose();
        authentication.dispose();
        registration.dispose();
        identity.dispose();
        registrationIdentity.dispose();
        client.close();
        language.dispose();
      },
    ),
  );
}

void _registerFontLicenses() {
  for (final (family, folder) in [
    ('Outfit', 'outfit'),
    ('Plus Jakarta Sans', 'plus_jakarta_sans'),
  ]) {
    LicenseRegistry.addLicense(() async* {
      final text = await rootBundle.loadString('assets/fonts/$folder/OFL.txt');
      yield LicenseEntryWithLineBreaks([family], text);
    });
  }
}
