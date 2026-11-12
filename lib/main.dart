import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'features/iam/application/services/auth_service.dart';
import 'features/iam/application/services/authentication_lifecycle.dart';
import 'features/iam/infrastructure/configuration/firebase_client_config.dart';
import 'features/iam/infrastructure/http/authenticated_api_client.dart';
import 'features/iam/infrastructure/repositories/firebase_auth_repository.dart';
import 'features/iam/infrastructure/repositories/iam_account_repository.dart';
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
  final identity = AuthenticationLifecycle(
    await FirebaseAuthRepository.initialize(
      FirebaseClientConfig.fromEnvironment(platform),
    ),
  );
  final client = http.Client();
  final authentication = AuthService(
    authentication: identity,
    accounts: IamAccountRepository(
      api: config.isApiConfigured
          ? AuthenticatedApiClient(
              baseUri: config.apiBaseUri!,
              client: client,
              authentication: identity,
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
      onDispose: () {
        authentication.dispose();
        identity.dispose();
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
