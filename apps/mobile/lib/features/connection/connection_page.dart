import 'package:flutter/material.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/connection_settings.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';
import '../../widgets/ts_phone_brand_mark.dart';

typedef ConnectionVerifier = Future<void> Function(ConnectionSettings settings);

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({
    super.key,
    required this.onConnected,
    this.initialSettings,
    this.onBack,
    this.onOpenSettings,
    this.verifier,
  });

  final ConnectionSettings? initialSettings;
  final Future<void> Function(ConnectionSettings settings) onConnected;
  final VoidCallback? onBack;
  final VoidCallback? onOpenSettings;
  final ConnectionVerifier? verifier;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverController;
  late final TextEditingController _tokenController;
  bool _obscureToken = true;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(
      text: widget.initialSettings?.serverUrl ?? 'https://tsphone.iawnix.xyz',
    );
    _tokenController = TextEditingController(
      text: widget.initialSettings?.token ?? '',
    );
  }

  @override
  void dispose() {
    _serverController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting || !_formKey.currentState!.validate()) return;
    ActionFeedback.tap();
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      final settings = ConnectionSettings(
        serverUrl: _serverController.text,
        token: _tokenController.text,
      );
      if (widget.verifier != null) {
        await widget.verifier!(settings);
      } else {
        final api = TsPhoneApi(settings);
        try {
          await api.version();
        } finally {
          api.close();
        }
      }
      await widget.onConnected(settings);
    } on Object catch (error) {
      if (!mounted) return;
      ActionFeedback.error();
      setState(() {
        _error = describeTsPhoneProblem(error).localizedMessage(context.l10n);
      });
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return PopScope<void>(
      canPop: widget.onBack == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onBack?.call();
      },
      child: Scaffold(
        appBar: TsGlassAppBar(
          leading: widget.onBack == null
              ? null
              : IconButton(
                  onPressed: () {
                    ActionFeedback.selection();
                    widget.onBack!();
                  },
                  tooltip: l10n.back,
                  icon: const Icon(Icons.arrow_back),
                ),
          title: Text(
            widget.onBack == null ? l10n.appTitle : l10n.connectionSettings,
          ),
          actions: <Widget>[
            if (widget.onOpenSettings != null)
              IconButton(
                onPressed: () {
                  ActionFeedback.selection();
                  widget.onOpenSettings!();
                },
                tooltip: l10n.settings,
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
        body: TsPageBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  TsPhoneSpacing.large,
                  TsPhoneSpacing.xLarge,
                  TsPhoneSpacing.large,
                  TsPhoneSpacing.xLarge,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: TsGlassSurface(
                    elevated: true,
                    blurSigma: 12,
                    padding: const EdgeInsets.all(TsPhoneSpacing.large),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final largeText =
                                  MediaQuery.textScalerOf(context).scale(17) >
                                  24;
                              final compact =
                                  largeText || constraints.maxWidth < 280;
                              const mark = _ConnectionMark();
                              final copy = _ConnectionCopy(
                                theme: theme,
                                title: l10n.connectTsPhone,
                                subtitle: l10n.mobileCompanion,
                              );
                              return compact
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        mark,
                                        const SizedBox(
                                          height: TsPhoneSpacing.medium,
                                        ),
                                        copy,
                                      ],
                                    )
                                  : Row(
                                      children: <Widget>[
                                        mark,
                                        const SizedBox(
                                          width: TsPhoneSpacing.medium,
                                        ),
                                        Expanded(child: copy),
                                      ],
                                    );
                            },
                          ),
                          const SizedBox(height: TsPhoneSpacing.xLarge),
                          TextFormField(
                            controller: _serverController,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const <String>[AutofillHints.url],
                            decoration: InputDecoration(
                              labelText: l10n.server,
                              hintText: l10n.serverHint,
                              prefixIcon: const Icon(Icons.dns_outlined),
                            ),
                            validator: (value) {
                              try {
                                ConnectionSettings.normalizeServerUrl(
                                  value ?? '',
                                );
                                return null;
                              } on ConnectionValidationException catch (error) {
                                return error.reason.localizedMessage(l10n);
                              }
                            },
                          ),
                          const SizedBox(height: TsPhoneSpacing.medium),
                          TextFormField(
                            controller: _tokenController,
                            obscureText: _obscureToken,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const <String>[
                              AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              labelText: l10n.accessToken,
                              prefixIcon: const Icon(Icons.key_outlined),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  ActionFeedback.selection();
                                  setState(
                                    () => _obscureToken = !_obscureToken,
                                  );
                                },
                                tooltip: _obscureToken
                                    ? l10n.showToken
                                    : l10n.hideToken,
                                icon: Icon(
                                  _obscureToken
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              try {
                                ConnectionSettings.validateToken(value ?? '');
                                return null;
                              } on ConnectionValidationException catch (error) {
                                return error.reason.localizedMessage(l10n);
                              }
                            },
                          ),
                          if (_error case final message?) ...<Widget>[
                            const SizedBox(height: TsPhoneSpacing.medium),
                            TsInfoBand(
                              icon: Icons.error_outline,
                              message: message,
                              tone: TsInfoTone.error,
                            ),
                          ],
                          const SizedBox(height: TsPhoneSpacing.large),
                          FilledButton.icon(
                            onPressed: _connecting ? null : _connect,
                            icon: AnimatedSwitcher(
                              duration: TsPhoneMotion.quick,
                              child: _connecting
                                  ? const SizedBox.square(
                                      key: ValueKey<String>('connecting'),
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.link,
                                      key: ValueKey<String>('connect'),
                                    ),
                            ),
                            label: Text(
                              _connecting ? l10n.connecting : l10n.connect,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionMark extends StatelessWidget {
  const _ConnectionMark();

  @override
  Widget build(BuildContext context) {
    return const TsPhoneBrandBadge(size: 58);
  }
}

class _ConnectionCopy extends StatelessWidget {
  const _ConnectionCopy({
    required this.theme,
    required this.title,
    required this.subtitle,
  });

  final ThemeData theme;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: TsPhoneSpacing.xSmall),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
