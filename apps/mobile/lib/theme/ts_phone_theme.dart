import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class TsPhoneSpacing {
  static const double xSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double xLarge = 24;
  static const double xxLarge = 32;
}

abstract final class TsPhoneRadii {
  static const double small = 6;
  static const double medium = 8;
  static const double panel = 8;
  static const double bubble = 16;
  static const double composer = 20;
}

abstract final class TsPhoneMotion {
  static const Duration quick = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration statusPulse = Duration(milliseconds: 720);

  static Duration resolve(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

@immutable
class TsPhoneStatusTheme extends ThemeExtension<TsPhoneStatusTheme> {
  const TsPhoneStatusTheme({
    required this.connected,
    required this.onConnected,
    required this.connectedContainer,
    required this.onConnectedContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.codeBackground,
    required this.codeForeground,
    required this.terminalBackground,
    required this.terminalSurface,
    required this.terminalForeground,
    required this.terminalMuted,
  });

  final Color connected;
  final Color onConnected;
  final Color connectedContainer;
  final Color onConnectedContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color codeBackground;
  final Color codeForeground;
  final Color terminalBackground;
  final Color terminalSurface;
  final Color terminalForeground;
  final Color terminalMuted;

  factory TsPhoneStatusTheme.forBrightness(
    Brightness brightness, {
    bool highContrast = false,
  }) {
    final isLight = brightness == Brightness.light;
    return TsPhoneStatusTheme(
      connected: isLight
          ? highContrast
                ? const Color(0xFF005A46)
                : const Color(0xFF007A5E)
          : highContrast
          ? const Color(0xFF7FFFD4)
          : const Color(0xFF63E6BE),
      onConnected: isLight ? Colors.white : Colors.black,
      connectedContainer: isLight
          ? const Color(0xFFD6F5EC)
          : const Color(0xFF123D36),
      onConnectedContainer: isLight
          ? const Color(0xFF00382C)
          : const Color(0xFFD9FFF5),
      warning: isLight
          ? highContrast
                ? const Color(0xFF6B3900)
                : const Color(0xFF8A4B00)
          : highContrast
          ? const Color(0xFFFFE08A)
          : const Color(0xFFFFD166),
      onWarning: isLight ? Colors.white : Colors.black,
      warningContainer: isLight
          ? const Color(0xFFFFF0D8)
          : const Color(0xFF49330C),
      onWarningContainer: isLight
          ? const Color(0xFF4A2900)
          : const Color(0xFFFFF1D2),
      error: isLight
          ? highContrast
                ? const Color(0xFFA81712)
                : const Color(0xFFC52A23)
          : highContrast
          ? const Color(0xFFFF928D)
          : const Color(0xFFFF6961),
      onError: isLight ? Colors.white : Colors.black,
      errorContainer: isLight
          ? const Color(0xFFFFE8E5)
          : const Color(0xFF571B19),
      onErrorContainer: isLight
          ? const Color(0xFF5F0C08)
          : const Color(0xFFFFE8E6),
      codeBackground: isLight
          ? const Color(0xFFE5F1F1)
          : const Color(0xFF13302D),
      codeForeground: isLight
          ? const Color(0xFF173D3A)
          : const Color(0xFF8EF0D9),
      terminalBackground: const Color(0xFF08110F),
      terminalSurface: const Color(0xFF0D1916),
      terminalForeground: const Color(0xFF8EF0D9),
      terminalMuted: const Color(0xFF6E9C91),
    );
  }

  static TsPhoneStatusTheme resolve(BuildContext context) {
    final theme = Theme.of(context);
    if (MediaQuery.highContrastOf(context)) {
      return TsPhoneStatusTheme.forBrightness(
        theme.brightness,
        highContrast: true,
      );
    }
    return theme.extension<TsPhoneStatusTheme>() ??
        TsPhoneStatusTheme.forBrightness(theme.brightness);
  }

  @override
  TsPhoneStatusTheme copyWith({
    Color? connected,
    Color? onConnected,
    Color? connectedContainer,
    Color? onConnectedContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? codeBackground,
    Color? codeForeground,
    Color? terminalBackground,
    Color? terminalSurface,
    Color? terminalForeground,
    Color? terminalMuted,
  }) {
    return TsPhoneStatusTheme(
      connected: connected ?? this.connected,
      onConnected: onConnected ?? this.onConnected,
      connectedContainer: connectedContainer ?? this.connectedContainer,
      onConnectedContainer: onConnectedContainer ?? this.onConnectedContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      codeBackground: codeBackground ?? this.codeBackground,
      codeForeground: codeForeground ?? this.codeForeground,
      terminalBackground: terminalBackground ?? this.terminalBackground,
      terminalSurface: terminalSurface ?? this.terminalSurface,
      terminalForeground: terminalForeground ?? this.terminalForeground,
      terminalMuted: terminalMuted ?? this.terminalMuted,
    );
  }

  @override
  TsPhoneStatusTheme lerp(
    covariant ThemeExtension<TsPhoneStatusTheme>? other,
    double t,
  ) {
    if (other is! TsPhoneStatusTheme) return this;
    return TsPhoneStatusTheme(
      connected: Color.lerp(connected, other.connected, t)!,
      onConnected: Color.lerp(onConnected, other.onConnected, t)!,
      connectedContainer: Color.lerp(
        connectedContainer,
        other.connectedContainer,
        t,
      )!,
      onConnectedContainer: Color.lerp(
        onConnectedContainer,
        other.onConnectedContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer: Color.lerp(
        onErrorContainer,
        other.onErrorContainer,
        t,
      )!,
      codeBackground: Color.lerp(codeBackground, other.codeBackground, t)!,
      codeForeground: Color.lerp(codeForeground, other.codeForeground, t)!,
      terminalBackground: Color.lerp(
        terminalBackground,
        other.terminalBackground,
        t,
      )!,
      terminalSurface: Color.lerp(terminalSurface, other.terminalSurface, t)!,
      terminalForeground: Color.lerp(
        terminalForeground,
        other.terminalForeground,
        t,
      )!,
      terminalMuted: Color.lerp(terminalMuted, other.terminalMuted, t)!,
    );
  }
}

@immutable
class TsPhoneGlassTheme extends ThemeExtension<TsPhoneGlassTheme> {
  const TsPhoneGlassTheme({
    required this.surface,
    required this.elevatedSurface,
    required this.controlSurface,
    required this.border,
    required this.strongBorder,
    required this.highlight,
    required this.shadow,
    required this.blurSigma,
    required this.floatingBlurSigma,
  });

  final Color surface;
  final Color elevatedSurface;
  final Color controlSurface;
  final Color border;
  final Color strongBorder;
  final Color highlight;
  final Color shadow;
  final double blurSigma;
  final double floatingBlurSigma;

  factory TsPhoneGlassTheme.forBrightness(
    Brightness brightness, {
    bool highContrast = false,
  }) {
    final isLight = brightness == Brightness.light;
    if (highContrast) {
      return TsPhoneGlassTheme(
        surface: isLight ? Colors.white : Colors.black,
        elevatedSurface: isLight ? Colors.white : const Color(0xFF111111),
        controlSurface: isLight ? Colors.white : const Color(0xFF1C1C1E),
        border: isLight ? const Color(0xFF3A3A3C) : const Color(0xFFC7C7CC),
        strongBorder: isLight ? Colors.black : Colors.white,
        highlight: Colors.transparent,
        shadow: Colors.transparent,
        blurSigma: 0,
        floatingBlurSigma: 0,
      );
    }
    return TsPhoneGlassTheme(
      surface: isLight ? const Color(0xBDF7F9FC) : const Color(0xBA10161D),
      elevatedSurface: isLight
          ? const Color(0xD9FFFFFF)
          : const Color(0xD9161D25),
      controlSurface: isLight
          ? const Color(0xA8FFFFFF)
          : const Color(0xA326303A),
      border: isLight ? const Color(0xB8FFFFFF) : const Color(0x3DFFFFFF),
      strongBorder: isLight ? const Color(0xF2FFFFFF) : const Color(0x66FFFFFF),
      highlight: isLight ? const Color(0xA6FFFFFF) : const Color(0x26FFFFFF),
      shadow: isLight ? const Color(0x24142633) : const Color(0x78000000),
      blurSigma: 22,
      floatingBlurSigma: 28,
    );
  }

  static TsPhoneGlassTheme resolve(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<TsPhoneGlassTheme>() ??
        TsPhoneGlassTheme.forBrightness(theme.brightness);
  }

  @override
  TsPhoneGlassTheme copyWith({
    Color? surface,
    Color? elevatedSurface,
    Color? controlSurface,
    Color? border,
    Color? strongBorder,
    Color? highlight,
    Color? shadow,
    double? blurSigma,
    double? floatingBlurSigma,
  }) {
    return TsPhoneGlassTheme(
      surface: surface ?? this.surface,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      controlSurface: controlSurface ?? this.controlSurface,
      border: border ?? this.border,
      strongBorder: strongBorder ?? this.strongBorder,
      highlight: highlight ?? this.highlight,
      shadow: shadow ?? this.shadow,
      blurSigma: blurSigma ?? this.blurSigma,
      floatingBlurSigma: floatingBlurSigma ?? this.floatingBlurSigma,
    );
  }

  @override
  TsPhoneGlassTheme lerp(
    covariant ThemeExtension<TsPhoneGlassTheme>? other,
    double t,
  ) {
    if (other is! TsPhoneGlassTheme) return this;
    return TsPhoneGlassTheme(
      surface: Color.lerp(surface, other.surface, t)!,
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      controlSurface: Color.lerp(controlSurface, other.controlSurface, t)!,
      border: Color.lerp(border, other.border, t)!,
      strongBorder: Color.lerp(strongBorder, other.strongBorder, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      blurSigma: blurSigma + (other.blurSigma - blurSigma) * t,
      floatingBlurSigma:
          floatingBlurSigma + (other.floatingBlurSigma - floatingBlurSigma) * t,
    );
  }
}

abstract final class TsPhoneTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData highContrastLight() =>
      _build(Brightness.light, highContrast: true);

  static ThemeData highContrastDark() =>
      _build(Brightness.dark, highContrast: true);

  static SystemUiOverlayStyle systemUiOverlayStyle(ColorScheme scheme) {
    final isLight = scheme.brightness == Brightness.light;
    final iconBrightness = isLight ? Brightness.dark : Brightness.light;

    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: scheme.brightness,
      systemStatusBarContrastEnforced: true,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData _build(Brightness brightness, {bool highContrast = false}) {
    final isLight = brightness == Brightness.light;
    final glassTheme = TsPhoneGlassTheme.forBrightness(
      brightness,
      highContrast: highContrast,
    );
    final statusTheme = TsPhoneStatusTheme.forBrightness(
      brightness,
      highContrast: highContrast,
    );
    final primary = switch ((brightness, highContrast)) {
      (Brightness.light, false) => const Color(0xFF0068D0),
      (Brightness.light, true) => const Color(0xFF004F9E),
      (Brightness.dark, false) => const Color(0xFF409CFF),
      (Brightness.dark, true) => const Color(0xFF78B7FF),
    };
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primary: primary,
          onPrimary: isLight ? Colors.white : Colors.black,
          primaryContainer: isLight
              ? const Color(0xFFDCEEFF)
              : const Color(0xFF0A3155),
          onPrimaryContainer: isLight
              ? const Color(0xFF003A66)
              : const Color(0xFFDCEEFF),
          secondary: statusTheme.connected,
          onSecondary: statusTheme.onConnected,
          secondaryContainer: statusTheme.connectedContainer,
          onSecondaryContainer: statusTheme.onConnectedContainer,
          tertiary: statusTheme.warning,
          onTertiary: statusTheme.onWarning,
          tertiaryContainer: statusTheme.warningContainer,
          onTertiaryContainer: statusTheme.onWarningContainer,
          error: statusTheme.error,
          onError: statusTheme.onError,
          errorContainer: statusTheme.errorContainer,
          onErrorContainer: statusTheme.onErrorContainer,
          surface: highContrast
              ? isLight
                    ? Colors.white
                    : Colors.black
              : isLight
              ? const Color(0xFFF2F2F7)
              : const Color(0xFF0B0F14),
          onSurface: isLight
              ? const Color(0xFF1C1C1E)
              : const Color(0xFFF2F2F7),
          onSurfaceVariant: isLight
              ? const Color(0xFF636366)
              : const Color(0xFFAEAEB2),
          surfaceContainerLowest: isLight
              ? const Color(0xFFFFFFFF)
              : const Color(0xFF0B0F14),
          surfaceContainerLow: isLight
              ? const Color(0xFFF7F7FA)
              : const Color(0xFF10161C),
          surfaceContainer: isLight
              ? const Color(0xFFEFEFF4)
              : const Color(0xFF141A20),
          surfaceContainerHigh: isLight
              ? const Color(0xFFE5E5EA)
              : const Color(0xFF1B232B),
          surfaceContainerHighest: isLight
              ? const Color(0xFFD8D8DE)
              : const Color(0xFF252E37),
          outline: highContrast
              ? isLight
                    ? const Color(0xFF3A3A3C)
                    : const Color(0xFFC7C7CC)
              : const Color(0xFF8E8E93),
          outlineVariant: highContrast
              ? isLight
                    ? const Color(0xFF747477)
                    : const Color(0xFF636366)
              : isLight
              ? const Color(0xFFC7C7CC)
              : const Color(0xFF343D46),
        );

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final textTheme = baseTextTheme.copyWith(
      displaySmall: baseTextTheme.displaySmall?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        height: 1.16,
      ),
      headlineSmall: baseTextTheme.headlineSmall?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.18,
      ),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.4),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
      bodySmall: baseTextTheme.bodySmall?.copyWith(fontSize: 13, height: 1.35),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: baseTextTheme.labelMedium?.copyWith(fontSize: 13),
      labelSmall: baseTextTheme.labelSmall?.copyWith(fontSize: 11),
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(TsPhoneRadii.medium),
      borderSide: BorderSide(
        color: highContrast
            ? scheme.outline
            : scheme.outlineVariant.withValues(alpha: 0.72),
      ),
    );
    final overlayShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TsPhoneRadii.panel),
      side: BorderSide(
        color: highContrast ? scheme.outline : scheme.outlineVariant,
        width: highContrast ? 1 : 0.5,
      ),
    );
    final overlayStyle = systemUiOverlayStyle(scheme);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[glassTheme, statusTheme],
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: scheme.primary.withValues(alpha: 0.08),
      focusColor: scheme.primary.withValues(alpha: 0.12),
      hoverColor: scheme.primary.withValues(alpha: 0.06),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        systemOverlayStyle: overlayStyle,
        shape: const Border(),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TsPhoneRadii.panel),
          side: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.5,
        space: 0.5,
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 52,
        minVerticalPadding: TsPhoneSpacing.xSmall,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TsPhoneSpacing.large,
          vertical: TsPhoneSpacing.xSmall,
        ),
        iconColor: scheme.primary,
        titleTextStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TsPhoneSpacing.large,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TsPhoneRadii.medium),
          ),
          animationDuration: TsPhoneMotion.quick,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TsPhoneRadii.medium),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          animationDuration: TsPhoneMotion.quick,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TsPhoneRadii.medium),
          ),
          animationDuration: TsPhoneMotion.quick,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size.square(44)),
          animationDuration: TsPhoneMotion.quick,
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.pressed)) {
              return scheme.primary.withValues(alpha: 0.18);
            }
            if (states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)) {
              return scheme.primary.withValues(alpha: 0.10);
            }
            return null;
          }),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight
            ? const Color(0xFF2C2C2E)
            : const Color(0xFFE5E5EA),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? Colors.white : const Color(0xFF1C1C1E),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TsPhoneRadii.panel),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: highContrast ? 0 : 8,
        shadowColor: glassTheme.shadow,
        shape: overlayShape,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: scheme.onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        barrierColor: Colors.black.withValues(alpha: 0.42),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        modalBackgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: highContrast ? 0 : 8,
        shadowColor: glassTheme.shadow,
        modalBarrierColor: Colors.black.withValues(alpha: 0.42),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(TsPhoneRadii.bubble),
          ),
          side: BorderSide(
            color: highContrast ? scheme.outline : scheme.outlineVariant,
            width: highContrast ? 1 : 0.5,
          ),
        ),
        showDragHandle: false,
        dragHandleColor: scheme.onSurfaceVariant,
        clipBehavior: Clip.antiAlias,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: highContrast ? 0 : 8,
        shadowColor: glassTheme.shadow,
        shape: overlayShape,
        textStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        position: PopupMenuPosition.under,
        iconColor: scheme.onSurfaceVariant,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          animationDuration: TsPhoneMotion.quick,
          minimumSize: const WidgetStatePropertyAll<Size>(Size(44, 44)),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.surfaceContainerLow;
            }
            if (states.contains(WidgetState.selected)) {
              return highContrast ? scheme.primary : scheme.primaryContainer;
            }
            return scheme.surfaceContainerHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            if (states.contains(WidgetState.selected)) {
              return highContrast
                  ? scheme.onPrimary
                  : scheme.onPrimaryContainer;
            }
            return scheme.onSurface;
          }),
          iconColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: 0.38);
            }
            if (states.contains(WidgetState.selected)) {
              return highContrast
                  ? scheme.onPrimary
                  : scheme.onPrimaryContainer;
            }
            return scheme.onSurfaceVariant;
          }),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(
              color: highContrast ? scheme.outline : scheme.outlineVariant,
              width: highContrast ? 1.5 : 0.7,
            ),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TsPhoneRadii.medium),
            ),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}
