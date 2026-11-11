import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'shared/application/services/language_service.dart';
import 'shared/infrastructure/preferences/device_language_preference_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  final language = LanguageService(
    DeviceLanguagePreferenceRepository(SharedPreferencesAsync()),
  );
  await language.initialize();
  runApp(IchuApp(language: language, config: AppConfig.fromEnvironment()));
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
