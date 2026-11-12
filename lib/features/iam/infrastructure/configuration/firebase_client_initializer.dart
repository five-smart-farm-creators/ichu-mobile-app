import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';

import 'firebase_client_config.dart';

abstract final class FirebaseClientInitializer {
  /// Initializes a named Firebase app only when its options match exactly.
  static Future<firebase_auth.FirebaseAuth?> initialize(
    FirebaseClientConfig config, {
    required String name,
  }) async {
    final options = config.options;
    if (options == null) return null;

    try {
      FirebaseApp? existingApp;
      for (final candidate in Firebase.apps) {
        if (candidate.name == name) {
          existingApp = candidate;
          break;
        }
      }

      late final FirebaseApp app;
      if (existingApp != null) {
        if (existingApp.options != options) return null;
        app = existingApp;
      } else {
        app = await Firebase.initializeApp(name: name, options: options);
      }

      return firebase_auth.FirebaseAuth.instanceFor(app: app);
    } on Object {
      // Initialization failures are intentionally not exposed or logged.
      return null;
    }
  }
}
