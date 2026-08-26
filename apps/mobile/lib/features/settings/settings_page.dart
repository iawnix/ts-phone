import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../data/ts_phone_api.dart';
import '../../models/app_theme_preference.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/app_locale_preference.dart';
import '../../models/connection_settings.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';
import '../../widgets/ts_phone_brand_mark.dart';

typedef SettingsGatewayBuilder =
    TsPhoneGateway Function(ConnectionSettings settings);

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.connectionSettings,
    required this.themePreference,
    required this.localePreference,
    required this.onThemeChanged,
    required this.onLocaleChanged,
    required this.onEditConnection,
    required this.onClose,
    this.gatewayBuilder,
  });

  final ConnectionSettings? connectionSettings;
  final AppThemePreference themePreference;
  final AppLocalePreference localePreference;
  final Future<void> Function(AppThemePreference preference) onThemeChanged;
  final Future<void> Function(AppLocalePreference preference) onLocaleChanged;
  final VoidCallback onEditConnection;
  final VoidCallback onClose;
  final SettingsGatewayBuilder? gatewayBuilder;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _savingTheme = false;
  bool _savingLocale = false;
  bool _diagnosing = false;
  _ConnectionDiagnostics? _diagnostics;

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.connectionSettings;
    final current = widget.connectionSettings;
    if (previous?.serverUrl != current?.serverUrl ||
        previous?.token != current?.token) {
      _diagnostics = null;
    }
  }

  Future<void> _changeTheme(AppThemePreference? preference) async {
    if (_savingTheme || preference == null) return;
    if (preference == widget.themePreference) return;
    ActionFeedback.selection();
    setState(() => _savingTheme = true);
    try {
      await widget.onThemeChanged(preference);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.saveAppearanceFailed)),
      );
    } finally {
      if (mounted) setState(() => _savingTheme = false);
    }
  }

  Future<void> _changeLocale(AppLocalePreference? preference) async {
    if (_savingLocale || preference == null) return;
    if (preference == widget.localePreference) return;
    ActionFeedback.selection();
    setState(() => _savingLocale = true);
    try {
      await widget.onLocaleChanged(preference);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.saveLanguageFailed)));
    } finally {
      if (mounted) setState(() => _savingLocale = false);
    }
  }

  Future<void> _runDiagnostics() async {
    final connection = widget.connectionSettings;
    if (_diagnosing || connection == null) return;
    ActionFeedback.tap();
    setState(() => _diagnosing = true);
    final gateway =
        widget.gatewayBuilder?.call(connection) ?? TsPhoneApi(connection);
    try {
      final version = await gateway.version();
      if (!mounted) return;
      setState(() {
        _diagnostics = _ConnectionDiagnostics(
          apiVersion: version['apiVersion'] as String?,
        );
      });
      ActionFeedback.selection();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _diagnostics = _ConnectionDiagnostics(
          problem: describeTsPhoneProblem(error),
        );
      });
      ActionFeedback.error();
    } finally {
      gateway.close();
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.connectionSettings;
    final l10n = context.l10n;
    final authority = connection == null
        ? l10n.notConfigured
        : Uri.parse(connection.serverUrl).authority;
    final diagnostics = _diagnostics;
    final statusTheme = TsPhoneStatusTheme.resolve(context);
    final authValue = connection == null
        ? l10n.notConfigured
        : diagnostics?.problem?.kind == TsPhoneProblemKind.authentication
        ? l10n.diagnosticFailed
        : diagnostics?.problem == null && diagnostics != null
        ? l10n.diagnosticVerified
        : l10n.diagnosticConfigured;
    final authColor =
        diagnostics?.problem?.kind == TsPhoneProblemKind.authentication
        ? statusTheme.error
        : diagnostics?.problem == null && diagnostics != null
        ? statusTheme.connected
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final protocolValue = diagnostics?.apiVersion ?? 'ts-phone-api/3';
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onClose();
      },
      child: Scaffold(
        appBar: TsGlassAppBar(
          leading: IconButton(
            onPressed: () {
              ActionFeedback.selection();
              widget.onClose();
            },
            tooltip: l10n.back,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(l10n.settings),
        ),
        body: TsPageBackdrop(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.only(bottom: TsPhoneSpacing.xxLarge),
              children: <Widget>[
                TsSettingsSection(
                  title: l10n.appearance,
                  child: Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(TsPhoneSpacing.medium),
                        child: _AdaptiveChoiceControl<AppThemePreference>(
                          groupValue: widget.themePreference,
                          choices: <AppThemePreference, String>{
                            AppThemePreference.system: l10n.themeSystem,
                            AppThemePreference.light: l10n.themeLight,
                            AppThemePreference.dark: l10n.themeDark,
                          },
                          onValueChanged: (value) =>
                              unawaited(_changeTheme(value)),
                        ),
                      ),
                      if (_savingTheme)
                        const LinearProgressIndicator(minHeight: 2),
                    ],
                  ),
                ),
                TsSettingsSection(
                  title: l10n.language,
                  child: Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(TsPhoneSpacing.medium),
                        child: _AdaptiveChoiceControl<AppLocalePreference>(
                          groupValue: widget.localePreference,
                          choices: <AppLocalePreference, String>{
                            AppLocalePreference.system: l10n.languageSystem,
                            AppLocalePreference.zh: l10n.languageChinese,
                            AppLocalePreference.en: l10n.languageEnglish,
                          },
                          onValueChanged: (value) =>
                              unawaited(_changeLocale(value)),
                        ),
                      ),
                      if (_savingLocale)
                        const LinearProgressIndicator(minHeight: 2),
                    ],
                  ),
                ),
                TsSettingsSection(
                  title: l10n.connection,
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        onTap: () {
                          ActionFeedback.selection();
                          widget.onEditConnection();
                        },
                        leading: TsSettingsIcon(
                          icon: Icons.dns_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(l10n.tsPhoneService),
                        subtitle: TsMonoText(
                          authority,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              onPressed: connection == null || _diagnosing
                                  ? null
                                  : _runDiagnostics,
                              tooltip: _diagnosing
                                  ? l10n.diagnosticsRunning
                                  : l10n.runDiagnostics,
                              icon: _diagnosing
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.monitor_heart_outlined),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ],
                        ),
                      ),
                      _SettingsDivider(),
                      _DiagnosticRow(
                        icon: Icons.link_rounded,
                        label: l10n.endpoint,
                        value: connection?.serverUrl ?? l10n.notConfigured,
                      ),
                      _SettingsDivider(),
                      _DiagnosticRow(
                        icon: Icons.key_rounded,
                        label: l10n.auth,
                        value: authValue,
                        valueColor: authColor,
                      ),
                      _SettingsDivider(),
                      _DiagnosticRow(
                        icon: Icons.lan_outlined,
                        label: l10n.protocol,
                        value: protocolValue,
                      ),
                      if (diagnostics?.problem case final problem?) ...<Widget>[
                        _SettingsDivider(),
                        Padding(
                          padding: const EdgeInsets.all(TsPhoneSpacing.medium),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(
                                Icons.error_outline_rounded,
                                size: 18,
                                color: statusTheme.error,
                              ),
                              const SizedBox(width: TsPhoneSpacing.small),
                              Expanded(
                                child: Text(
                                  problem.localizedMessage(l10n),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: statusTheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                TsSettingsSection(
                  title: l10n.about,
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        leading: const TsPhoneBrandBadge(size: 32),
                        title: const Text('TS Phone'),
                        subtitle: Text(l10n.mobileCompanion),
                      ),
                      const _SettingsDivider(),
                      _DiagnosticRow(
                        icon: Icons.phone_iphone_rounded,
                        label: l10n.client,
                        value: '0.8.5',
                      ),
                      const _SettingsDivider(),
                      _DiagnosticRow(
                        icon: Icons.build_outlined,
                        label: l10n.build,
                        value: '27',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionDiagnostics {
  const _ConnectionDiagnostics({this.apiVersion, this.problem});

  final String? apiVersion;
  final TsPhoneProblem? problem;
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 52,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TsPhoneSpacing.large,
          vertical: TsPhoneSpacing.small,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 17, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: TsPhoneSpacing.medium),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            const SizedBox(width: TsPhoneSpacing.medium),
            Flexible(
              child: TsMonoText(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: valueColor ?? theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdaptiveChoiceControl<T extends Object> extends StatelessWidget {
  const _AdaptiveChoiceControl({
    required this.groupValue,
    required this.choices,
    required this.onValueChanged,
  });

  final T groupValue;
  final Map<T, String> choices;
  final ValueChanged<T?> onValueChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledLabelSize = MediaQuery.textScalerOf(context).scale(13);
        final useRows = scaledLabelSize > 17 || constraints.maxWidth < 280;
        if (useRows) return _buildRows(context);

        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final glass = TsPhoneGlassTheme.resolve(context);
        return SizedBox(
          width: double.infinity,
          height: 44,
          child: CupertinoSlidingSegmentedControl<T>(
            groupValue: groupValue,
            backgroundColor: colors.surfaceContainerHigh.withValues(
              alpha: 0.68,
            ),
            thumbColor: glass.elevatedSurface,
            padding: const EdgeInsets.all(3),
            children: <T, Widget>{
              for (final entry in choices.entries)
                entry.key: Text(entry.value, maxLines: 1),
            },
            onValueChanged: onValueChanged,
          ),
        );
      },
    );
  }

  Widget _buildRows(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = choices.entries.toList(growable: false);
    return Column(
      children: <Widget>[
        for (var index = 0; index < entries.length; index++) ...<Widget>[
          if (index > 0)
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: TsPhoneSpacing.large,
              color: colors.outlineVariant,
            ),
          Semantics(
            selected: entries[index].key == groupValue,
            button: true,
            child: InkWell(
              onTap: entries[index].key == groupValue
                  ? null
                  : () => onValueChanged(entries[index].key),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TsPhoneSpacing.large,
                    vertical: TsPhoneSpacing.small,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: Text(entries[index].value)),
                      const SizedBox(width: TsPhoneSpacing.medium),
                      if (entries[index].key == groupValue)
                        Icon(Icons.check_rounded, color: colors.primary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
