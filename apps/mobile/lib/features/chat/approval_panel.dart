import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../data/ts_phone_api.dart';
import '../../l10n/app_localizations_extensions.dart';
import '../../models/workspace.dart';
import '../../theme/ts_phone_theme.dart';
import '../../widgets/action_feedback.dart';
import '../../widgets/presentation.dart';
import 'chat_controller.dart';

enum ApprovalPanelOutcome {
  approved,
  rejected,
  deferred,
  expired,
  stale,
  missing,
}

Future<ApprovalPanelOutcome?> showApprovalPanel({
  required BuildContext context,
  required ExtensionUiRequest request,
  required ChatController controller,
  required String workspaceName,
  required String sessionName,
  required SessionAccessMode accessMode,
  required int queuedAfter,
}) {
  final phoneLayout = MediaQuery.sizeOf(context).width < 600;
  final panel = _ApprovalPanel(
    request: request,
    controller: controller,
    workspaceName: workspaceName,
    sessionName: sessionName,
    accessMode: accessMode,
    queuedAfter: queuedAfter,
    phoneLayout: phoneLayout,
  );
  if (phoneLayout) {
    return showModalBottomSheet<ApprovalPanelOutcome>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (context) => panel,
    );
  }
  return showDialog<ApprovalPanelOutcome>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (context) => panel,
  );
}

enum _ApprovalPanelPhase {
  pending,
  approving,
  rejecting,
  failed,
  expired,
  stale,
  missing,
}

class _ApprovalPanel extends StatefulWidget {
  const _ApprovalPanel({
    required this.request,
    required this.controller,
    required this.workspaceName,
    required this.sessionName,
    required this.accessMode,
    required this.queuedAfter,
    required this.phoneLayout,
  });

  final ExtensionUiRequest request;
  final ChatController controller;
  final String workspaceName;
  final String sessionName;
  final SessionAccessMode accessMode;
  final int queuedAfter;
  final bool phoneLayout;

  @override
  State<_ApprovalPanel> createState() => _ApprovalPanelState();
}

class _ApprovalPanelState extends State<_ApprovalPanel>
    with WidgetsBindingObserver {
  static const Set<int> _countdownAnnouncementThresholds = <int>{60, 30, 10};

  _ApprovalPanelPhase _phase = _ApprovalPanelPhase.pending;
  TsPhoneProblem? _failure;
  Timer? _countdownTimer;
  Timer? _expiryTimer;
  Timer? _terminalTimer;
  final Set<int> _announcedCountdownThresholds = <int>{};
  int _remainingSeconds = 0;

  bool get _canRespond =>
      _phase == _ApprovalPanelPhase.pending ||
      _phase == _ApprovalPanelPhase.failed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_checkSessionIdentity);
    _resetCountdown();
    scheduleMicrotask(_checkSessionIdentity);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resetCountdown();
      _checkSessionIdentity();
    }
  }

  void _resetCountdown() {
    _countdownTimer?.cancel();
    _expiryTimer?.cancel();
    if (!_canRespond) return;
    final remaining = widget.request.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _markTerminal(_ApprovalPanelPhase.expired);
      return;
    }
    _remainingSeconds = math.max(1, (remaining.inMilliseconds + 999) ~/ 1000);
    if (mounted) setState(() {});
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_canRespond) return;
      final nextSeconds = math.max(0, _remainingSeconds - 1);
      setState(() {
        _remainingSeconds = nextSeconds;
      });
      _announceCountdownThreshold(nextSeconds);
    });
    _expiryTimer = Timer(remaining, () {
      if (mounted && _canRespond) {
        _markTerminal(_ApprovalPanelPhase.expired);
      }
    });
  }

  void _announceCountdownThreshold(int seconds) {
    if (!_countdownAnnouncementThresholds.contains(seconds) ||
        !MediaQuery.supportsAnnounceOf(context) ||
        !_announcedCountdownThresholds.add(seconds)) {
      return;
    }
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        context.l10n.approvalExpiresIn(seconds),
        Directionality.of(context),
      ),
    );
  }

  void _checkSessionIdentity() {
    if (!mounted || !_canRespond) return;
    if (widget.controller.sessionRevision != widget.request.sessionRevision) {
      _markTerminal(_ApprovalPanelPhase.stale);
    }
  }

  void _markTerminal(_ApprovalPanelPhase phase) {
    if (!mounted) return;
    _countdownTimer?.cancel();
    _expiryTimer?.cancel();
    setState(() {
      _phase = phase;
      _failure = null;
      _remainingSeconds = 0;
    });
    _terminalTimer?.cancel();
    _terminalTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pop(switch (phase) {
        _ApprovalPanelPhase.expired => ApprovalPanelOutcome.expired,
        _ApprovalPanelPhase.stale => ApprovalPanelOutcome.stale,
        _ApprovalPanelPhase.missing => ApprovalPanelOutcome.missing,
        _ => null,
      });
    });
  }

  Future<void> _respond(bool approved) async {
    if (!_canRespond) return;
    _checkSessionIdentity();
    if (!_canRespond) return;
    if (!widget.request.expiresAt.isAfter(DateTime.now())) {
      _markTerminal(_ApprovalPanelPhase.expired);
      return;
    }
    approved ? ActionFeedback.warning() : ActionFeedback.tap();
    setState(() {
      _phase = approved
          ? _ApprovalPanelPhase.approving
          : _ApprovalPanelPhase.rejecting;
      _failure = null;
    });
    final failure = await widget.controller.respondToUi(
      widget.request,
      approved: approved,
    );
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(
        approved
            ? ApprovalPanelOutcome.approved
            : ApprovalPanelOutcome.rejected,
      );
      return;
    }
    switch (failure.code) {
      case TsPhoneProblemCode.approvalExpired:
        _markTerminal(_ApprovalPanelPhase.expired);
      case TsPhoneProblemCode.approvalStale ||
          TsPhoneProblemCode.sessionChanged:
        _markTerminal(_ApprovalPanelPhase.stale);
      case TsPhoneProblemCode.approvalMissing:
        _markTerminal(_ApprovalPanelPhase.missing);
      default:
        ActionFeedback.error();
        setState(() {
          _phase = _ApprovalPanelPhase.failed;
          _failure = failure;
        });
        _resetCountdown();
    }
  }

  Future<void> _handleBack() async {
    if (_canRespond) Navigator.of(context).pop(ApprovalPanelOutcome.deferred);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_checkSessionIdentity);
    _countdownTimer?.cancel();
    _expiryTimer?.cancel();
    _terminalTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    final radius = widget.phoneLayout
        ? const BorderRadius.vertical(top: Radius.circular(26))
        : BorderRadius.circular(TsPhoneRadii.panel);
    return PopScope<ApprovalPanelOutcome>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Align(
        alignment: widget.phoneLayout
            ? Alignment.bottomCenter
            : Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.phoneLayout ? double.infinity : 520,
            maxHeight: media.size.height * (widget.phoneLayout ? 0.88 : 0.82),
          ),
          child: TsGlassSurface(
            elevated: true,
            blurSigma: 20,
            borderRadius: radius,
            child: Material(
              color: Colors.transparent,
              child: SafeArea(
                top: !widget.phoneLayout,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _buildHeader(context),
                    Flexible(
                      child: Material(
                        key: const ValueKey<String>(
                          'approval-readable-surface',
                        ),
                        color: colors.surfaceContainerLowest,
                        child: _buildContent(context),
                      ),
                    ),
                    _buildActions(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        TsPhoneSpacing.large,
        TsPhoneSpacing.large,
        TsPhoneSpacing.medium,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackHeader =
              MediaQuery.textScalerOf(context).scale(17) > 22 ||
              constraints.maxWidth < 328;
          final identity = _buildHeaderIdentity(context);
          final countdown = _buildCountdownBadge(context);
          if (stackHeader) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                identity,
                const SizedBox(height: TsPhoneSpacing.small),
                Align(alignment: Alignment.centerRight, child: countdown),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: identity),
              const SizedBox(width: TsPhoneSpacing.small),
              countdown,
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderIdentity(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.shield_outlined, color: colors.onTertiaryContainer),
        ),
        const SizedBox(width: TsPhoneSpacing.medium),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.approvalTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: TsPhoneSpacing.xSmall),
              Text(
                l10n.approvalRequestDescription,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownBadge(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Semantics(
      key: const ValueKey<String>('approval-countdown'),
      container: true,
      liveRegion: false,
      label: l10n.approvalExpiresIn(_remainingSeconds),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: BorderRadius.circular(TsPhoneRadii.small),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Text(
              '${_remainingSeconds}s',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.onTertiaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        0,
        TsPhoneSpacing.large,
        TsPhoneSpacing.large,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ApprovalFact(
            icon: Icons.folder_outlined,
            label: l10n.approvalWorkspace,
            value: widget.workspaceName,
          ),
          _ApprovalFact(
            icon: widget.accessMode == SessionAccessMode.controller
                ? Icons.admin_panel_settings_outlined
                : Icons.visibility_outlined,
            label: l10n.approvalSession,
            value:
                '${widget.sessionName} · ${widget.accessMode.localizedLabel(l10n)}',
          ),
          _ApprovalFact(
            icon: Icons.build_outlined,
            label: l10n.approvalTool,
            value: widget.request.toolName,
          ),
          const SizedBox(height: TsPhoneSpacing.medium),
          Text(
            l10n.approvalDetails,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: TsPhoneSpacing.small),
          Container(
            padding: const EdgeInsets.all(TsPhoneSpacing.medium),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(TsPhoneRadii.medium),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.72),
                width: 0.6,
              ),
            ),
            child: SelectableText(
              widget.request.preview,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
          if (widget.queuedAfter > 0) ...<Widget>[
            const SizedBox(height: TsPhoneSpacing.medium),
            Text(
              l10n.approvalQueueRemaining(widget.queuedAfter),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
          if (_statusMessage(context) case final message?) ...<Widget>[
            const SizedBox(height: TsPhoneSpacing.medium),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(TsPhoneSpacing.medium),
                decoration: BoxDecoration(
                  color: _phase == _ApprovalPanelPhase.failed
                      ? colors.errorContainer
                      : colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(TsPhoneRadii.small),
                ),
                child: Row(
                  children: <Widget>[
                    if (_phase == _ApprovalPanelPhase.approving ||
                        _phase == _ApprovalPanelPhase.rejecting)
                      const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        _phase == _ApprovalPanelPhase.failed
                            ? Icons.error_outline_rounded
                            : Icons.info_outline_rounded,
                        size: 19,
                        color: _phase == _ApprovalPanelPhase.failed
                            ? colors.onErrorContainer
                            : colors.onSurfaceVariant,
                      ),
                    const SizedBox(width: TsPhoneSpacing.small),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: _phase == _ApprovalPanelPhase.failed
                              ? colors.onErrorContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _statusMessage(BuildContext context) => switch (_phase) {
    _ApprovalPanelPhase.pending => null,
    _ApprovalPanelPhase.approving => context.l10n.approvalApproving,
    _ApprovalPanelPhase.rejecting => context.l10n.approvalRejecting,
    _ApprovalPanelPhase.failed => _failure?.localizedMessage(context.l10n),
    _ApprovalPanelPhase.expired => context.l10n.approvalExpired,
    _ApprovalPanelPhase.stale => context.l10n.approvalStale,
    _ApprovalPanelPhase.missing => context.l10n.approvalMissing,
  };

  Widget _buildActions(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final busy =
        _phase == _ApprovalPanelPhase.approving ||
        _phase == _ApprovalPanelPhase.rejecting;
    final reject = OutlinedButton.icon(
      key: const ValueKey<String>('approval-reject'),
      onPressed: _canRespond ? () => _respond(false) : null,
      icon: const Icon(Icons.block_outlined),
      label: Text(l10n.reject),
    );
    final approve = FilledButton.icon(
      key: const ValueKey<String>('approval-approve'),
      onPressed: _canRespond ? () => _respond(true) : null,
      style: FilledButton.styleFrom(
        backgroundColor: colors.tertiary,
        foregroundColor: colors.onTertiary,
      ),
      icon: const Icon(Icons.shield_outlined),
      label: Text(l10n.approveOnce),
    );
    final stackActions =
        MediaQuery.textScalerOf(context).scale(14) > 18 ||
        MediaQuery.sizeOf(context).width < 340;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        TsPhoneSpacing.large,
        TsPhoneSpacing.medium,
        TsPhoneSpacing.large,
        TsPhoneSpacing.large,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.72),
            width: 0.6,
          ),
        ),
      ),
      child: IgnorePointer(
        ignoring: busy,
        child: stackActions
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  approve,
                  const SizedBox(height: TsPhoneSpacing.small),
                  reject,
                ],
              )
            : Row(
                children: <Widget>[
                  Expanded(child: reject),
                  const SizedBox(width: TsPhoneSpacing.small),
                  Expanded(child: approve),
                ],
              ),
      ),
    );
  }
}

class _ApprovalFact extends StatelessWidget {
  const _ApprovalFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TsPhoneSpacing.xSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: TsPhoneSpacing.small),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
