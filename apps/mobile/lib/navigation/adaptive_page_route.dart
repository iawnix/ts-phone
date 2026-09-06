import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Route<T> tsAdaptivePageRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
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
