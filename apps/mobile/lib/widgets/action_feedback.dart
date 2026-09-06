import 'dart:async';

import 'package:flutter/services.dart';

abstract final class ActionFeedback {
  /// Routine taps already have visual press feedback and stay deliberately
  /// silent. Haptics are reserved for selection and consequential outcomes.
  static void tap() {}

  static void selection() => unawaited(HapticFeedback.selectionClick());

  static void warning() => unawaited(HapticFeedback.mediumImpact());

  static void error() => unawaited(HapticFeedback.mediumImpact());
}
