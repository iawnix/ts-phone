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
  bool _showConnectionDetails = false;
  _ConnectionDiagnostics? _diagnostics;
  int _diagnosticsGeneration = 0;

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.connectionSettings;
    final current = widget.connectionSettings;
    if (previous?.serverUrl != current?.serverUrl ||
        previous?.token != current?.token) {
      _diagnosticsGeneration += 1;
      _diagnostics = null;
      _diagnosing = false;
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
    final generation = ++_diagnosticsGeneration;
    setState(() {
      _diagnosing = true;
      _diagnostics = null;
    });
    TsPhoneGateway? gateway;
    try {
      gateway =
          widget.gatewayBuilder?.call(connection) ?? TsPhoneApi(connection);
      final version = await gateway.version();
      if (!mounted || generation != _diagnosticsGeneration) return;
      setState(() {
        _diagnostics = _ConnectionDiagnostics(
          apiVersion: version['apiVersion'] as String?,
        );
      });
      ActionFeedback.selection();
    } on Object catch (error) {
      if (!mounted || generation != _diagnosticsGeneration) return;
      setState(() {
        _diagnostics = _ConnectionDiagnostics(
          problem: describeTsPhoneProblem(error),
        );
      });
      ActionFeedback.error();
    } finally {
      try {
        gateway?.close();
      } on Object {
        // Closing is best-effort; the visible diagnostics state must settle.
      }
      if (mounted && generation == _diagnosticsGeneration) {
        setState(() => _diagnosing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.connectionSettings;
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final endpointSummary = connection?.serverUrl ?? l10n.notConfigured;
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
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TsSettingsSection(
                          title: l10n.preferences,
                          child: Column(
                            children: <Widget>[
                              _PreferenceControlRow(
                                label: l10n.appearance,
                                saving: _savingTheme,
                                control:
                                    _AdaptiveChoiceControl<AppThemePreference>(
                                      groupValue: widget.themePreference,
                                      choices: <AppThemePreference, String>{
                                        AppThemePreference.system:
                                            l10n.themeSystem,
                                        AppThemePreference.light:
                                            l10n.themeLight,
                                        AppThemePreference.dark: l10n.themeDark,
                                      },
                                      onValueChanged: (value) =>
                                          unawaited(_changeTheme(value)),
                                    ),
                              ),
                              const _SettingsDivider(),
                              _PreferenceControlRow(
                                label: l10n.language,
                                saving: _savingLocale,
                                control:
                                    _AdaptiveChoiceControl<AppLocalePreference>(
                                      groupValue: widget.localePreference,
                                      choices: <AppLocalePreference, String>{
                                        AppLocalePreference.system:
                                            l10n.languageSystem,
                                        AppLocalePreference.zh:
                                            l10n.languageChinese,
                                        AppLocalePreference.en:
                                            l10n.languageEnglish,
                                      },
                                      onValueChanged: (value) =>
                                          unawaited(_changeLocale(value)),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        TsSettingsSection(
                          title: l10n.connection,
                          child: Column(
                            children: <Widget>[
                              ListTile(
                                key: const ValueKey<String>(
                                  'connection-service-edit',
                                ),
                                onTap: () {
                                  ActionFeedback.selection();
                                  widget.onEditConnection();
                                },
                                leading: Icon(
                                  Icons.dns_outlined,
                                  size: 22,
                                  color: colors.onSurfaceVariant,
                                ),
                                title: Text(l10n.tsPhoneService),
                                subtitle: TsMonoText(
                                  endpointSummary,
                                  key: const ValueKey<String>(
                                    'connection-service-endpoint',
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                                trailing: Icon(
                                  Icons.edit_outlined,
                                  key: const ValueKey<String>(
                                    'connection-edit-affordance',
                                  ),
                                  size: 20,
                                  color: colors.primary,
                                ),
                              ),
                              const _SettingsDivider(),
                              _DiagnosticsActionRow(
                                enabled: connection != null,
                                diagnosing: _diagnosing,
                                diagnostics: diagnostics,
                                onTap: _runDiagnostics,
                              ),
                              if (diagnostics?.problem
                                  case final problem?) ...<Widget>[
                                const _SettingsDivider(),
                                _ConnectionProblem(
                                  message: problem.localizedMessage(l10n),
                                ),
                              ],
                              const _SettingsDivider(),
                              _ConnectionDetailsToggle(
                                expanded: _showConnectionDetails,
                                onTap: () {
                                  ActionFeedback.selection();
                                  setState(
                                    () => _showConnectionDetails =
                                        !_showConnectionDetails,
                                  );
                                },
                              ),
                              if (_showConnectionDetails) ...<Widget>[
                                const _SettingsDivider(),
                                KeyedSubtree(
                                  key: const ValueKey<String>(
                                    'connection-details',
                                  ),
                                  child: Column(
                                    children: <Widget>[
                                      _DiagnosticRow(
                                        icon: Icons.link_rounded,
                                        label: l10n.endpoint,
                                        value:
                                            connection?.serverUrl ??
                                            l10n.notConfigured,
                                        stacked: true,
                                        selectable: connection != null,
                                      ),
                                      const _SettingsDivider(),
                                      _DiagnosticRow(
                                        icon: Icons.key_rounded,
                                        label: l10n.auth,
                                        value: authValue,
                                        valueColor: authColor,
                                      ),
                                      const _SettingsDivider(),
                                      _DiagnosticRow(
                                        icon: Icons.lan_outlined,
                                        label: l10n.protocol,
                                        value: protocolValue,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const _AppIdentityFooter(),
                      ],
                    ),
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

class _PreferenceControlRow extends StatelessWidget {
  const _PreferenceControlRow({
    required this.label,
    required this.control,
    required this.saving,
  });

  final String label;
  final Widget control;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TsPhoneSpacing.large,
            10,
            TsPhoneSpacing.large,
            10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: TsPhoneSpacing.small),
              control,
            ],
          ),
        ),
        if (saving) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}

class _ConnectionDetailsToggle extends StatelessWidget {
  const _ConnectionDetailsToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      expanded: expanded,
      child: InkWell(
        key: const ValueKey<String>('connection-details-toggle'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TsPhoneSpacing.large,
              vertical: TsPhoneSpacing.small,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 19,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: TsPhoneSpacing.medium),
                Expanded(
                  child: Text(
                    context.l10n.connectionDetails,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: colors.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionProblem extends StatelessWidget {
  const _ConnectionProblem({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final error = TsPhoneStatusTheme.resolve(context).error;
    return Padding(
      padding: const EdgeInsets.all(TsPhoneSpacing.medium),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: error),
          const SizedBox(width: TsPhoneSpacing.small),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: error),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIdentityFooter extends StatelessWidget {
  const _AppIdentityFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey<String>('settings-app-identity'),
      padding: const EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        TsPhoneSpacing.large,
        TsPhoneSpacing.large,
        0,
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: TsPhoneSpacing.small,
        runSpacing: TsPhoneSpacing.xSmall,
        children: <Widget>[
          const TsPhoneBrandBadge(size: 18),
          Text(
            'TS Phone',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            context.l10n.clientVersionBuild('0.11.0', '34'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.stacked = false,
    this.selectable = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool stacked;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final useStacked =
        stacked || MediaQuery.textScalerOf(context).scale(13) > 18;
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: valueColor ?? theme.colorScheme.onSurfaceVariant,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    final valueWidget = selectable
        ? SelectableText(
            value,
            textAlign: useStacked ? TextAlign.start : TextAlign.end,
            style: valueStyle,
          )
        : TsMonoText(
            value,
            maxLines: useStacked ? null : 2,
            overflow: useStacked ? null : TextOverflow.ellipsis,
            textAlign: useStacked ? TextAlign.start : TextAlign.end,
            style: valueStyle,
          );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: useStacked ? 64 : 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TsPhoneSpacing.large,
          vertical: TsPhoneSpacing.small,
        ),
        child: useStacked
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      icon,
                      size: 17,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: TsPhoneSpacing.medium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(label, style: theme.textTheme.bodyMedium),
                        const SizedBox(height: TsPhoneSpacing.xSmall),
                        valueWidget,
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  Icon(
                    icon,
                    size: 17,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: TsPhoneSpacing.medium),
                  Expanded(
                    child: Text(label, style: theme.textTheme.bodyMedium),
                  ),
                  const SizedBox(width: TsPhoneSpacing.medium),
                  Flexible(child: valueWidget),
                ],
              ),
      ),
    );
  }
}

class _DiagnosticsActionRow extends StatelessWidget {
  const _DiagnosticsActionRow({
    required this.enabled,
    required this.diagnosing,
    required this.diagnostics,
    required this.onTap,
  });

  final bool enabled;
  final bool diagnosing;
  final _ConnectionDiagnostics? diagnostics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final status = TsPhoneStatusTheme.resolve(context);
    final problem = diagnostics?.problem;
    final (label, color, statusIcon) = diagnosing
        ? (
            l10n.diagnosticsRunning,
            theme.colorScheme.primary,
            Icons.sync_rounded,
          )
        : !enabled
        ? (
            l10n.notConfigured,
            theme.colorScheme.outline,
            Icons.remove_circle_outline_rounded,
          )
        : problem != null
        ? (l10n.diagnosticFailed, status.error, Icons.error_outline_rounded)
        : diagnostics != null
        ? (
            l10n.diagnosticVerified,
            status.connected,
            Icons.check_circle_outline_rounded,
          )
        : (
            l10n.diagnosticNotChecked,
            theme.colorScheme.onSurfaceVariant,
            Icons.help_outline_rounded,
          );
    final motionDuration = TsPhoneMotion.resolve(
      context,
      TsPhoneMotion.standard,
    );
    return Semantics(
      button: true,
      enabled: enabled && !diagnosing,
      child: InkWell(
        key: const ValueKey<String>('run-connection-diagnostics'),
        onTap: enabled && !diagnosing ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TsPhoneSpacing.large,
              vertical: TsPhoneSpacing.small,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.monitor_heart_outlined,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: TsPhoneSpacing.medium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        l10n.runDiagnostics,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: motionDuration,
                        child: Row(
                          key: ValueKey<String>(
                            diagnosing ? 'diagnostics-running' : label,
                          ),
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(statusIcon, size: 15, color: color),
                            const SizedBox(width: TsPhoneSpacing.xSmall),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: TsPhoneSpacing.small),
                AnimatedSwitcher(
                  duration: motionDuration,
                  child: diagnosing
                      ? SizedBox.square(
                          key: const ValueKey<String>('diagnostics-spinner'),
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        )
                      : Icon(
                          Icons.refresh_rounded,
                          key: const ValueKey<String>('diagnostics-refresh'),
                          size: 20,
                          color: enabled
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
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
        final useRows = scaledLabelSize > 17 || constraints.maxWidth < 180;
        if (useRows) return _buildRows(context);

        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        return SizedBox(
          width: double.infinity,
          height: 44,
          child: CupertinoSlidingSegmentedControl<T>(
            groupValue: groupValue,
            proportionalWidth: false,
            backgroundColor: colors.surfaceContainerHigh.withValues(
              alpha: 0.68,
            ),
            thumbColor: colors.surfaceContainerLowest,
            padding: const EdgeInsets.all(3),
            children: <T, Widget>{
              for (final entry in choices.entries)
                entry.key: Center(
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                ),
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
                      const SizedBox(width: 24),
                      Expanded(
                        child: Text(
                          entries[index].value,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(
                        width: 24,
                        child: entries[index].key == groupValue
                            ? Icon(
                                Icons.check_rounded,
                                size: 20,
                                color: colors.primary,
                              )
                            : null,
                      ),
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
