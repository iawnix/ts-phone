import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/ts_phone_api.dart';
import '../../data/tspi_link_pairing.dart';
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
    this.pairingRedeemer,
  });

  final ConnectionSettings? initialSettings;
  final Future<void> Function(ConnectionSettings settings) onConnected;
  final VoidCallback? onBack;
  final VoidCallback? onOpenSettings;
  final ConnectionVerifier? verifier;
  final TspiLinkPairingRedeemer? pairingRedeemer;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _relayController;
  late final TextEditingController _pairingCodeController;
  late final TextEditingController _deviceNameController;
  bool _connecting = false;
  bool _committing = false;
  String? _error;
  ConnectionSettings? _redeemedSettings;
  String? _redeemedInput;

  @override
  void initState() {
    super.initState();
    _relayController = TextEditingController(
      text: widget.initialSettings?.serverUrl ?? '',
    );
    _pairingCodeController = TextEditingController();
    _deviceNameController = TextEditingController(text: 'TS Phone');
  }

  @override
  void dispose() {
    _relayController.dispose();
    _pairingCodeController.dispose();
    _deviceNameController.dispose();
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
      final input = _pairingInputIdentity();
      final settings = _redeemedInput == input && _redeemedSettings != null
          ? _redeemedSettings!
          : await _redeemPairing();
      _redeemedInput = input;
      _redeemedSettings = settings;
      if (widget.verifier != null) {
        await widget.verifier!(settings);
      }
      if (!mounted) return;
      setState(() => _committing = true);
      await widget.onConnected(settings);
    } on Object catch (error) {
      if (!mounted) return;
      ActionFeedback.error();
      setState(() {
        _error = switch (error) {
          TspiLinkPairingException pairing => pairing.localizedMessage(
            context.l10n,
          ),
          ConnectionValidationException validation =>
            validation.reason.localizedMessage(context.l10n),
          _ => describeTsPhoneProblem(error).localizedMessage(context.l10n),
        };
      });
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
          _committing = false;
        });
      }
    }
  }

  String _pairingInputIdentity() => <String>[
    _relayController.text.trim(),
    _pairingCodeController.text.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    ),
    _deviceNameController.text.trim(),
  ].join('\n');

  Future<ConnectionSettings> _redeemPairing() async {
    final redeem = widget.pairingRedeemer;
    if (redeem != null) {
      return redeem(
        relayUrl: _relayController.text,
        pairingCode: _pairingCodeController.text,
        deviceName: _deviceNameController.text,
      );
    }
    final client = TspiLinkPairingClient();
    try {
      return await client.redeem(
        relayUrl: _relayController.text,
        pairingCode: _pairingCodeController.text,
        deviceName: _deviceNameController.text,
      );
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return PopScope<void>(
      canPop: !_committing,
      child: Scaffold(
        appBar: TsGlassAppBar(
          leading: widget.onBack == null
              ? null
              : BackButton(onPressed: _committing ? null : widget.onBack),
          title: Text(
            widget.onBack == null ? l10n.appTitle : l10n.connectionSettings,
          ),
          actions: <Widget>[
            if (widget.onOpenSettings != null)
              IconButton(
                key: const ValueKey<String>('connection-settings'),
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
                  child: TsContentSurface(
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
                            key: const ValueKey<String>('relay-url-field'),
                            controller: _relayController,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            autofillHints: const <String>[AutofillHints.url],
                            decoration: InputDecoration(
                              labelText: l10n.relay,
                              hintText: l10n.relayHint,
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
                            key: const ValueKey<String>('pairing-code-field'),
                            controller: _pairingCodeController,
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9-]'),
                              ),
                              LengthLimitingTextInputFormatter(9),
                            ],
                            decoration: InputDecoration(
                              labelText: l10n.pairingCode,
                              hintText: l10n.pairingCodeHint,
                              prefixIcon: const Icon(Icons.pin_outlined),
                            ),
                            validator: (value) {
                              final normalized = (value ?? '')
                                  .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
                                  .toUpperCase();
                              return normalized.length == 8
                                  ? null
                                  : l10n.validationPairingCode;
                            },
                          ),
                          const SizedBox(height: TsPhoneSpacing.medium),
                          TextFormField(
                            key: const ValueKey<String>('device-name-field'),
                            controller: _deviceNameController,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: l10n.deviceName,
                              hintText: l10n.deviceNameHint,
                              prefixIcon: const Icon(Icons.smartphone_outlined),
                            ),
                            validator: (value) {
                              final name = (value ?? '').trim();
                              return name.isNotEmpty &&
                                      name.length <= 80 &&
                                      !name.codeUnits.any((v) => v < 32)
                                  ? null
                                  : l10n.validationDeviceName;
                            },
                            onFieldSubmitted: (_) => _connect(),
                          ),
                          if (_error case final message?) ...<Widget>[
                            const SizedBox(height: TsPhoneSpacing.medium),
                            TsInfoBand(
                              icon: Icons.error_outline_rounded,
                              message: message,
                              tone: TsInfoTone.error,
                            ),
                          ],
                          const SizedBox(height: TsPhoneSpacing.large),
                          TsCenteredAction(
                            child: FilledButton.icon(
                              key: const ValueKey<String>('connect-action'),
                              onPressed: _connecting ? null : _connect,
                              icon: AnimatedSwitcher(
                                duration: TsPhoneMotion.resolve(
                                  context,
                                  TsPhoneMotion.quick,
                                ),
                                child: _connecting
                                    ? const SizedBox.square(
                                        key: ValueKey<String>('connecting'),
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.link_rounded,
                                        key: ValueKey<String>('connect'),
                                      ),
                              ),
                              label: Text(
                                _connecting ? l10n.pairing : l10n.pair,
                                textAlign: TextAlign.center,
                              ),
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
