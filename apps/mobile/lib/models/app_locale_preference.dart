import 'package:flutter/widgets.dart';

enum AppLocalePreference {
  system,
  zh,
  en;

  static AppLocalePreference fromStorage(String? value) {
    return AppLocalePreference.values.firstWhere(
      (preference) => preference.name == value,
      orElse: () => AppLocalePreference.system,
    );
  }

  Locale? get locale => switch (this) {
    AppLocalePreference.system => null,
    AppLocalePreference.zh => const Locale('zh'),
    AppLocalePreference.en => const Locale('en'),
  };
}
