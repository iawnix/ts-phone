import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../data/corhub_api.dart';
import '../../models/host_monitor.dart';

class MonitorMutation {
  MonitorMutation(this.method, this.params);
  final String method;
  final Map<String, Object?> params;
}

/// Keeps an uncertain command identity across page navigation, without owning
/// task state. A manual retry must repeat the exact original payload.
class MonitorController extends ChangeNotifier {
  MonitorController(this.gateway, this.workspaceId, this.sessionId);
  final HostMonitorGateway gateway;
  final String workspaceId, sessionId;
  static final _ledgers = Expando<Map<String, MonitorMutation>>();
  Map<String, MonitorMutation> get _ledger => _ledgers[gateway] ??= {};
  String get _key => '$workspaceId/$sessionId';
  MonitorMutation? get pending => _ledger[_key];
  MonitorOverview? overview;
  Object? error;
  Set<String> capabilities = {};
  bool loading = false, busy = false, disposed = false, _foreground = true;
  int _generation = 0;
  Timer? _timer;
  StreamSubscription<void>? _events;

  Future<void> start() async {
    try {
      capabilities = await gateway.monitorCapabilities();
      if (!capabilities.contains('monitor/overview')) {
        throw const CorHubApiException(
          'Monitor upgrade required',
          code: 'method_not_found',
        );
      }
      if (disposed) return;
      _events = gateway.monitorChanges(workspaceId, sessionId).listen((_) {
        if (_foreground) unawaited(refresh());
      });
      _timer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (_foreground) unawaited(refresh());
      });
      await refresh();
    } catch (e) {
      if (!disposed) {
        error = e;
        notifyListeners();
      }
    }
  }

  void foreground(bool value) {
    _foreground = value;
    if (value && capabilities.contains('monitor/overview')) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (loading || busy || disposed) return;
    loading = true;
    final generation = _generation;
    try {
      final result = await gateway.monitorRequest(
        workspaceId,
        sessionId,
        'monitor/overview',
      );
      if (disposed || generation != _generation) return;
      overview = MonitorOverview(result);
      // Preserve actionable errors and unknown receipts until resolved.
      if (pending == null) error = null;
    } catch (e) {
      if (!disposed && generation == _generation) error = e;
    } finally {
      loading = false;
      if (!disposed) notifyListeners();
    }
  }

  Future<bool> control(String method, Map<String, Object?> params) async {
    if (busy || disposed || pending != null) return false;
    if (!capabilities.contains(method)) {
      error = const CorHubApiException(
        'Unsupported control',
        code: 'method_not_found',
      );
      notifyListeners();
      return false;
    }
    _ledger[_key] = MonitorMutation(
      method,
      Map.unmodifiable({
        ...params,
        'request_id': createCorHubClientMessageId(),
      }),
    );
    return retry();
  }

  Future<bool> retry() async {
    final command = pending;
    if (busy || command == null || disposed) return false;
    busy = true;
    error = null;
    _generation++;
    notifyListeners();
    var accepted = false;
    try {
      await gateway.monitorRequest(
        workspaceId,
        sessionId,
        command.method,
        params: command.params,
      );
      _ledger.remove(_key);
      accepted = true;
    } catch (e) {
      // Only explicit rejection proves no mutation needs receipt recovery.
      if (e is CorHubApiException &&
          const {
            'task_revision_conflict',
            'revision_conflict',
            'task_not_found',
            'task_not_active',
            'job_not_found',
            'task_cancel_policy_required',
            'task_action_invalid',
            'task_terminal',
            'task_state_invalid',
            'invalid_params',
            'method_not_found',
            'session_not_found',
            'workspace_not_found',
            'unauthorized',
            'authentication',
          }.contains(e.code)) {
        _ledger.remove(_key);
      }
      error = e;
    } finally {
      busy = false;
      if (!disposed) {
        final operationError = error;
        // Await an older refresh before the authoritative post-control read.
        while (loading && !disposed) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (!disposed) {
          await refresh();
          error = operationError ?? error;
          notifyListeners();
        }
      }
    }
    return accepted;
  }

  @override
  void dispose() {
    disposed = true;
    _timer?.cancel();
    unawaited(_events?.cancel());
    super.dispose();
  }
}
