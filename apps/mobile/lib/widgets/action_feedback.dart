import 'dart:async';

import 'package:flutter/services.dart';

abstract final class ActionFeedback {
  static void tap() => unawaited(HapticFeedback.lightImpact());

  static void selection() => unawaited(HapticFeedback.selectionClick());

  static void warning() => unawaited(HapticFeedback.mediumImpact());

  static void error() => unawaited(HapticFeedback.heavyImpact());
}
