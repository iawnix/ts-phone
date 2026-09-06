import 'package:flutter/widgets.dart';

/// App-level visual accessibility preferences that Flutter does not expose
/// consistently across every supported platform.
///
/// The platform bridge owns discovery of the native preference. Presentation
/// widgets consume only this policy, which keeps native channels out of the
/// design system.
class TsVisualAccessibility extends InheritedWidget {
  const TsVisualAccessibility({
    super.key,
    required this.reduceTransparency,
    required super.child,
  });

  final bool reduceTransparency;

  static bool reduceTransparencyOf(BuildContext context) {
    final policy = context
        .dependOnInheritedWidgetOfExactType<TsVisualAccessibility>();
    return policy?.reduceTransparency ?? false;
  }

  @override
  bool updateShouldNotify(TsVisualAccessibility oldWidget) =>
      reduceTransparency != oldWidget.reduceTransparency;
}
