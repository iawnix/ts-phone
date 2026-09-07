import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_identity.dart';
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
          serviceVersion: version['serviceVersion'] as String?,
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
    final protocolValue = diagnostics?.apiVersion ?? l10n.diagnosticNotChecked;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onClose),
        title: Text(l10n.settings),
      ),
      body: TsPageBackdrop(
        child: SafeArea(
          top: false,
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
                            _PreferenceRow<AppThemePreference>(
                              key: const ValueKey('appearance-setting'),
                              label: l10n.appearance,
                              saving: _savingTheme,
                              value: widget.themePreference,
                              choices: <AppThemePreference, String>{
                                AppThemePreference.system: l10n.themeSystem,
                                AppThemePreference.light: l10n.themeLight,
                                AppThemePreference.dark: l10n.themeDark,
                              },
                              onChanged: _changeTheme,
                            ),
                            const _SettingsDivider(),
                            _PreferenceRow<AppLocalePreference>(
                              key: const ValueKey('language-setting'),
                              label: l10n.language,
                              saving: _savingLocale,
                              value: widget.localePreference,
                              choices: <AppLocalePreference, String>{
                                AppLocalePreference.system: l10n.languageSystem,
                                AppLocalePreference.zh: l10n.languageChinese,
                                AppLocalePreference.en: l10n.languageEnglish,
                              },
                              onChanged: _changeLocale,
                            ),
                          ],
                        ),
                      ),
                      TsSettingsSection(
                        title: l10n.connection,
                        child: Column(
                          children: <Widget>[
                            _ConnectionServiceRow(
                              key: const ValueKey<String>(
                                'connection-service-edit',
                              ),
                              title: l10n.tsPhoneService,
                              endpoint: endpointSummary,
                              onTap: () {
                                ActionFeedback.selection();
                                widget.onEditConnection();
                              },
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
                                      label: l10n.endpoint,
                                      value:
                                          connection?.serverUrl ??
                                          l10n.notConfigured,
                                      stacked: true,
                                      selectable: connection != null,
                                    ),
                                    const _SettingsDivider(),
                                    _DiagnosticRow(
                                      label: l10n.auth,
                                      value: authValue,
                                      valueColor: authColor,
                                    ),
                                    const _SettingsDivider(),
                                    _DiagnosticRow(
                                      label: l10n.protocol,
                                      value: protocolValue,
                                    ),
                                    const _SettingsDivider(),
                                    _DiagnosticRow(
                                      label: l10n.hostVersion,
                                      value:
                                          diagnostics?.serviceVersion ??
                                          l10n.diagnosticNotChecked,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      TsSettingsSection(
                        title: l10n.aboutApp,
                        child: const _AppIdentityFooter(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionDiagnostics {
  const _ConnectionDiagnostics({
    this.apiVersion,
    this.serviceVersion,
    this.problem,
  });

  final String? apiVersion;
  final String? serviceVersion;
  final TsPhoneProblem? problem;
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: TsPhoneSpacing.large,
      color: theme.dividerTheme.color,
    );
  }
}

class _PreferenceRow<T extends Object> extends StatelessWidget {
  const _PreferenceRow({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    required this.saving,
  });

  final String label;
  final T value;
  final Map<T, String> choices;
  final Future<void> Function(T) onChanged;
  final bool saving;

  Future<void> _choose(BuildContext context) async {
    ActionFeedback.selection();
    final selected = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: TsPhoneSpacing.large),
              for (final entry in choices.entries)
                Semantics(
                  label: entry.value,
                  checked: entry.key == value,
                  inMutuallyExclusiveGroup: true,
                  excludeSemantics: true,
                  onTap: () => Navigator.of(context).pop(entry.key),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value),
                    trailing: entry.key == value
                        ? Icon(
                            Icons.check_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(entry.key),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (context.mounted && selected != null) await onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: !saving,
      child: InkWell(
        onTap: saving ? null : () => _choose(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final labelText = Text(
                      label,
                      style: theme.textTheme.bodyMedium,
                    );
                    final valueText = Text(
                      choices[value]!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                    // Measure the actual strings, including the user's text scale.
                    // Neither a fixed label column nor clipped segment labels fit
                    // reliably across languages and accessibility sizes.
                    double widthOf(String text) {
                      final painter = TextPainter(
                        text: TextSpan(
                          text: text,
                          style: theme.textTheme.bodyMedium,
                        ),
                        textDirection: Directionality.of(context),
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout();
                      final width = painter.width;
                      painter.dispose();
                      return width;
                    }

                    final stacked =
                        widthOf(label) + widthOf(choices[value]!) + 24 >
                        constraints.maxWidth;
                    return stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              labelText,
                              const SizedBox(height: 4),
                              valueText,
                            ],
                          )
                        : Row(
                            children: <Widget>[
                              labelText,
                              const Spacer(),
                              valueText,
                            ],
                          );
                  },
                ),
              ),
              const SizedBox(width: 10),
              if (saving)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionServiceRow extends StatelessWidget {
  const _ConnectionServiceRow({
    super.key,
    required this.title,
    required this.endpoint,
    required this.onTap,
  });

  final String title;
  final String endpoint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TsPhoneSpacing.large,
              vertical: 10,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: TsPhoneSpacing.xSmall),
                      Text(
                        endpoint,
                        key: const ValueKey<String>(
                          'connection-service-endpoint',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: TsPhoneSpacing.medium),
                Icon(
                  Icons.edit_outlined,
                  key: const ValueKey<String>('connection-edit-affordance'),
                  size: 19,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
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
            tsPhoneAppName,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            context.l10n.clientVersionBuild(tsPhoneAppVersion, tsPhoneAppBuild),
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
    required this.label,
    required this.value,
    this.valueColor,
    this.stacked = false,
    this.selectable = false,
  });

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
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: TsPhoneSpacing.xSmall),
                  valueWidget,
                ],
              )
            : Row(
                children: <Widget>[
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
    final (label, color) = diagnosing
        ? (l10n.diagnosticsRunning, theme.colorScheme.primary)
        : !enabled
        ? (l10n.notConfigured, theme.colorScheme.onSurfaceVariant)
        : problem != null
        ? (l10n.diagnosticFailed, status.error)
        : diagnostics != null
        ? (l10n.diagnosticVerified, status.connected)
        : (l10n.diagnosticNotChecked, theme.colorScheme.onSurfaceVariant);
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
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TsPhoneSpacing.large,
              vertical: 6,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.runDiagnostics,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: motionDuration,
                        child: Text(
                          key: ValueKey<String>(
                            diagnosing ? 'diagnostics-running' : label,
                          ),
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
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
