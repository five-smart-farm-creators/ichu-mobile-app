import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('English and Spanish define identical non-empty message keys', () {
    Map<String, dynamic> catalog(String language) =>
        jsonDecode(
              File(
                'lib/shared/infrastructure/i18n/app_$language.arb',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    final english = catalog('en');
    final spanish = catalog('es');
    Set<String> messages(Map<String, dynamic> value) =>
        value.keys.where((key) => !key.startsWith('@')).toSet();
    expect(messages(english), messages(spanish));
    for (final value in [english, spanish]) {
      for (final key in messages(value)) {
        expect(value[key], isA<String>());
        expect((value[key] as String).trim(), isNotEmpty, reason: key);
      }
    }
  });
}
