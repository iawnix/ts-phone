import 'package:flutter/material.dart';

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
    required this.warning,
    required this.error,
    required this.codeBackground,
    required this.codeForeground,
    required this.terminalBackground,
    required this.terminalSurface,
    required this.terminalForeground,
    required this.terminalMuted,
  });

  final Color connected;
  final Color warning;
  final Color error;
  final Color codeBackground;
  final Color codeForeground;
  final Color terminalBackground;
  final Color terminalSurface;
  final Color terminalForeground;
  final Color terminalMuted;

  factory TsPhoneStatusTheme.forBrightness(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return TsPhoneStatusTheme(
      connected: isLight ? const Color(0xFF00A884) : const Color(0xFF00C2A8),
      warning: const Color(0xFFFFB020),
      error: const Color(0xFFFF453A),
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
    return theme.extension<TsPhoneStatusTheme>() ??
        TsPhoneStatusTheme.forBrightness(theme.brightness);
  }

  @override
  TsPhoneStatusTheme copyWith({
    Color? connected,
    Color? warning,
    Color? error,
    Color? codeBackground,
    Color? codeForeground,
    Color? terminalBackground,
    Color? terminalSurface,
    Color? terminalForeground,
    Color? terminalMuted,
  }) {
    return TsPhoneStatusTheme(
      connected: connected ?? this.connected,
      warning: warning ?? this.warning,
      error: error ?? this.error,
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
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
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
    required this.border,
    required this.highlight,
    required this.shadow,
    required this.blurSigma,
  });

  final Color surface;
  final Color elevatedSurface;
  final Color border;
  final Color highlight;
  final Color shadow;
  final double blurSigma;

  factory TsPhoneGlassTheme.forBrightness(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return TsPhoneGlassTheme(
      surface: isLight ? const Color(0xC7F7F7FA) : const Color(0xC20B0F14),
      elevatedSurface: isLight
          ? const Color(0xE8FFFFFF)
          : const Color(0xE0141A20),
      border: isLight ? const Color(0xE0FFFFFF) : const Color(0x30FFFFFF),
      highlight: isLight ? const Color(0x80FFFFFF) : const Color(0x12FFFFFF),
      shadow: isLight ? const Color(0x1815222B) : const Color(0x52000000),
      blurSigma: 18,
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
    Color? border,
    Color? highlight,
    Color? shadow,
    double? blurSigma,
  }) {
    return TsPhoneGlassTheme(
      surface: surface ?? this.surface,
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      border: border ?? this.border,
      highlight: highlight ?? this.highlight,
      shadow: shadow ?? this.shadow,
      blurSigma: blurSigma ?? this.blurSigma,
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
      border: Color.lerp(border, other.border, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      blurSigma: blurSigma + (other.blurSigma - blurSigma) * t,
    );
  }
}

abstract final class TsPhoneTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final glassTheme = TsPhoneGlassTheme.forBrightness(brightness);
    final statusTheme = TsPhoneStatusTheme.forBrightness(brightness);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
        ).copyWith(
          primary: const Color(0xFF007AFF),
          onPrimary: Colors.white,
          primaryContainer: isLight
              ? const Color(0xFFDCEEFF)
              : const Color(0xFF0A3155),
          onPrimaryContainer: isLight
              ? const Color(0xFF003A66)
              : const Color(0xFFDCEEFF),
          secondary: statusTheme.connected,
          secondaryContainer: isLight
              ? const Color(0xFFD9F4EE)
              : const Color(0xFF123D36),
          onSecondaryContainer: isLight
              ? const Color(0xFF004C3C)
              : const Color(0xFFD9FFF5),
          tertiary: statusTheme.warning,
          tertiaryContainer: isLight
              ? const Color(0xFFFFEDD1)
              : const Color(0xFF49330C),
          onTertiaryContainer: isLight
              ? const Color(0xFF5C3500)
              : const Color(0xFFFFEACB),
          error: statusTheme.error,
          errorContainer: isLight
              ? const Color(0xFFFFE6E4)
              : const Color(0xFF571B19),
          onErrorContainer: isLight
              ? const Color(0xFF690005)
              : const Color(0xFFFFE8E6),
          surface: isLight ? const Color(0xFFF2F2F7) : const Color(0xFF0B0F14),
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
          outline: const Color(0xFF8E8E93),
          outlineVariant: isLight
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
        color: scheme.outlineVariant.withValues(alpha: 0.72),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[glassTheme, statusTheme],
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkRipple.splashFactory,
      splashColor: scheme.primary.withValues(alpha: 0.16),
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
        fillColor: glassTheme.elevatedSurface,
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
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          animationDuration: TsPhoneMotion.quick,
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
