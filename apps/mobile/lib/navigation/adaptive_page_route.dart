import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class TsAdaptivePage<T> extends Page<T> {
  const TsAdaptivePage({required this.child, super.key});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    late final Route<T> route;
    route = tsAdaptivePageRoute<T>(
      context: context,
      settings: this,
      builder: (_) => (route.settings as TsAdaptivePage<T>).child,
    );
    return route;
  }
}

Route<T> tsAdaptivePageRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    return PageRouteBuilder<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, _, _, child) => child,
    );
  }
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return CupertinoPageRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }
  return MaterialPageRoute<T>(
    builder: builder,
    settings: settings,
    fullscreenDialog: fullscreenDialog,
  );
}

Future<T?> pushTsPhonePage<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  return Navigator.of(context).push<T>(
    tsAdaptivePageRoute<T>(
      context: context,
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    ),
  );
}
