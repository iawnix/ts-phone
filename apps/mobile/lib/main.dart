import 'package:flutter/material.dart';

import 'app.dart';
import 'data/settings_store.dart';
import 'widgets/content_display_error.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (_) => const ContentDisplayError();
  runApp(TsPhoneApp(settingsStore: SecureSettingsStore()));
}
