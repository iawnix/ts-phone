import 'package:flutter/material.dart';

import 'app.dart';
import 'data/settings_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TsPhoneApp(settingsStore: SecureSettingsStore()));
}
