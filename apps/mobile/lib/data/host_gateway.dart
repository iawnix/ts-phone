import 'dart:async';

import '../models/connection_settings.dart';
import '../models/host_monitor.dart';
import '../models/phone_model.dart';
import '../models/workspace.dart';
import 'app_server_gateway.dart';
import 'host_rpc_client.dart';
import 'ts_phone_api.dart';

/// Adapts the public Host API to the existing mobile presentation models.
/// Pi owns messages and turns. The phone owns only projections and its outbox.
class HostGateway
    implements
        TsPhoneGateway,
        TsPhoneModelGateway,
        AppServerSessionGateway,
        AppServerWorkspaceGateway,
        WorkspaceSessionGateway,
        SessionResumeGateway,
        HostMonitorGateway {
  HostGateway(this.settings, {HostRpcClient? client})
    : _client =
          client ??
          HostRpcClient(
            gateway: Uri.parse(settings.serverUrl),
            serverId: settings.serverId,
            token: settings.token,
          );

  final ConnectionSettings settings;
  final HostRpcClient _client;
  final _sessions = <String, Map<String, Object?>>{};
  final _sessionWorkspaces = <String, String>{};
  String? _workspaceId;
  String? _sessionId;
  bool _closed = false;

  @override
  Future<Map<String, Object?>> version() => _guard(() async {
    final metadata = await _client.connect();
    return {
      'apiVersion': metadata['protocol'],
      'serviceVersion': 'TSPi Host',
      'serverId': metadata['server_id'] ?? settings.serverId,
    };
  });

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() => _guard(() async {
    final result = _object(await _client.request('workspace/list'));
    final workspaces = _list(result['workspaces']);
    return Future.wait(
      workspaces.map((raw) async {
        final workspace = _object(raw);
        final id = _string(workspace['workspace_id']);
        final sessions = await listSessions(id);
        return WorkspaceSummary(
          id: id,
          name: workspace['name'] as String? ?? id,
          runtimeState: RuntimeState.idle,
          isStreaming: sessions.any((session) => session.isStreaming),
          liveSessionCount: sessions
              .where((session) => session.runtimeState.isAvailable)
              .length,
          sessionCount: sessions.length,
        );
      }),
    );
  });

  @override
  Future<WorkspaceSummary> createWorkspace(String workspaceId) =>
      _guard(() async {
        final result = _object(
          await _client.request('workspace/create', {
            'workspace_id': workspaceId,
            'request_id': createTsPhoneClientMessageId(),
          }),
        );
        final workspace = _object(result['workspace'] ?? result);
        final id = _string(workspace['workspace_id']);
        return WorkspaceSummary(
          id: id,
          name: workspace['name'] as String? ?? id,
          runtimeState: RuntimeState.idle,
          isStreaming: false,
          liveSessionCount: 0,
          sessionCount: 0,
        );
      });

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) =>
      _guard(() async {
        final result = _object(
          await _client.request('session/list', {'workspace_id': workspaceId}),
        );
        return _list(
          result['sessions'],
        ).map((raw) => _summary(_object(raw), workspaceId)).toList();
      });

  @override
  Future<SessionSummary> createSession() async {
    final workspace = _workspaceId ?? (await listWorkspaces()).firstOrNull?.id;
    if (workspace == null) {
      throw const TsPhoneApiException(
        'Select a project first',
        code: 'workspace_not_found',
      );
    }
    return createWorkspaceSession(workspace);
  }

  @override
  Future<SessionSummary> createWorkspaceSession(String workspaceId) =>
      _guard(() async {
        final result = _object(
          await _client.request('session/create', {
            'workspace_id': workspaceId,
            'request_id': createTsPhoneClientMessageId(),
          }),
        );
        return _summary(_object(result['session'] ?? result), workspaceId);
      });

  @override
  Future<SessionSummary> resumeWorkspaceSession(
    String workspaceId,
    String sessionId,
  ) => _guard(() async {
    final result = _object(
      await _client.request('session/resume', {
        ..._target(workspaceId, sessionId),
        'request_id': createTsPhoneClientMessageId(),
      }),
    );
    return _summary(_object(result['session'] ?? result), workspaceId);
  });

  @override
  Future<void> removeSession(String sessionId) async {
    final workspace = _sessionWorkspaces[sessionId];
    if (workspace == null) {
      throw const TsPhoneApiException(
        'Session is not in this project',
        code: 'session_not_found',
      );
    }
    await removeWorkspaceSession(workspace, sessionId);
  }

  @override
  Future<void> removeWorkspaceSession(String workspaceId, String sessionId) =>
      _guard(() async {
        await _client.request('session/remove', {
          ..._target(workspaceId, sessionId),
          'request_id': createTsPhoneClientMessageId(),
        });
        _sessions.remove(_key(workspaceId, sessionId));
        _sessionWorkspaces.remove(sessionId);
      });

  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  }) => _guard(() async {
    if (before != null) {
      throw const TsPhoneApiException(
        'Host returns a complete session snapshot',
        code: 'history_window_unsupported',
      );
    }
    final result = _object(
      await _client.request('session/read', _target(workspaceId, sessionId)),
    );
    _rememberRead(result, workspaceId, sessionId);
    final snapshot = _object(result['snapshot']);
    return TsPhoneMessageSnapshot(
      sessionId: sessionId,
      sessionRevision: _revision(workspaceId, sessionId),
      messages: _messages(snapshot),
      lastEventId: _eventId(result),
      activeAgentRunId: snapshot['turn_id'] as String?,
    );
  });

  @override
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
    String? branch,
  }) async {
    throw const TsPhoneApiException(
      'Host exposes Pi session messages',
      code: 'timeline_unsupported',
    );
  }

  @override
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    String message, {
    required String clientMessageId,
  }) => _guard(() async {
    final result = _object(
      await _client.request('input/send', {
        ..._target(workspaceId, sessionId),
        // Reuse the outbox identity across reconnect and uncertain-delivery retry.
        'request_id': clientMessageId, 'client_message_id': clientMessageId,
        'text': message, 'mode': 'auto', 'source': 'phone',
      }),
    );
    if (result['state'] == 'uncertain') {
      throw const TsPhoneApiException(
        'Message delivery is uncertain',
        code: 'command_ambiguous',
      );
    }
    if (result['accepted'] != true) {
      throw const TsPhoneApiException(
        'Host rejected the message',
        code: 'prompt_rejected',
        statusCode: 409,
      );
    }
  });

  @override
  Future<void> abort(
    String workspaceId,
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  }) => _guard(() async {
    await _client.request('turn/interrupt', {
      ..._target(workspaceId, sessionId),
      'request_id': createTsPhoneClientMessageId(),
      'turn_id': agentRunId,
    });
  });

  @override
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  }) async {
    throw const TsPhoneApiException(
      'This request must be answered in Pi',
      code: 'approval_missing',
      statusCode: 404,
    );
  }

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) {
    late final StreamController<TsPhoneEvent> controller;
    StreamSubscription<Map<String, Object?>>? subscription;
    final buffered = <Map<String, Object?>>[];
    var hydrated = false;
    var cancelled = false;
    String? epoch;
    var sequence = -1;

    void emit(Map<String, Object?> value, {bool initial = false}) {
      if (cancelled) return;
      final nextEpoch = _string(value['epoch']);
      final nextSequence = value['sequence'];
      if (nextSequence is! int || nextSequence < 0) {
        throw const FormatException('Invalid Host event sequence');
      }
      if (!initial && epoch == nextEpoch && nextSequence <= sequence) return;
      epoch = nextEpoch;
      sequence = nextSequence;
      if (initial || value['session'] is Map) {
        _rememberRead(value, workspaceId, sessionId);
      }
      final snapshot = _object(value['snapshot']);
      controller.add(
        TsPhoneEvent(
          id: _eventId(value),
          workspaceId: workspaceId,
          sessionId: sessionId,
          sessionRevision: _revision(workspaceId, sessionId),
          instanceEpoch: epoch,
          type: 'session.snapshot',
          payload: _snapshotPayload(workspaceId, sessionId, snapshot),
          at: DateTime.now(),
        ),
      );
    }

    Future<void> start() async {
      subscription = _client.notifications.listen(
        (notification) {
          try {
            if (notification['method'] != 'session/event') return;
            final params = _object(notification['params']);
            if (params['workspace_id'] != workspaceId ||
                params['session_id'] != sessionId) {
              return;
            }
            if (!hydrated) {
              buffered.add(params);
            } else {
              emit(params);
            }
          } on Object catch (error, stack) {
            if (!cancelled) controller.addError(_translate(error), stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!cancelled) controller.addError(_translate(error), stack);
        },
        onDone: () {
          if (!cancelled) unawaited(controller.close());
        },
      );
      try {
        // Every connection reattaches and replaces local state from a snapshot.
        // lastEventId is deliberately not presented as a replay guarantee.
        final result = _object(
          await _client.request(
            'session/attach',
            _target(workspaceId, sessionId),
          ),
        );
        if (cancelled) return;
        emit(result, initial: true);
        hydrated = true;
        for (final value in buffered) {
          emit(value);
        }
        buffered.clear();
        onConnected?.call();
      } on Object catch (error, stack) {
        if (!cancelled) {
          controller.addError(_translate(error), stack);
          await controller.close();
        }
      }
    }

    controller = StreamController<TsPhoneEvent>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        cancelled = true;
        await subscription?.cancel();
        if (hydrated && !_closed && _client.metadata != null) {
          try {
            await _client.request(
              'session/detach',
              _target(workspaceId, sessionId),
            );
          } on Object {
            // A closed connection has already released its Host subscription.
          }
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<List<PhoneModel>> models() => _guard(() async {
    final result = _object(await _client.request('models/list', _activeTarget));
    return _list(result['models']).map((raw) {
      final model = _object(raw);
      final id = _string(model['id'] ?? model['model_id']);
      return PhoneModel(
        provider: _string(model['provider']),
        id: id,
        name: model['name'] as String? ?? id,
      );
    }).toList();
  });

  @override
  Future<SessionSummary> selectModel(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    PhoneModel model,
  ) => _guard(() async {
    final result = _object(
      await _client.request('model/select', {
        ..._target(workspaceId, sessionId),
        'request_id': createTsPhoneClientMessageId(),
        'provider': model.provider,
        'model_id': model.id,
      }),
    );
    if (result['session'] is Map) {
      return _summary(_object(result['session']), workspaceId);
    }
    if (result['accepted'] != true) {
      throw const TsPhoneApiException(
        'Host rejected the model',
        code: 'model_unavailable',
      );
    }
    final refreshed = _object(
      await _client.request('session/read', _target(workspaceId, sessionId)),
    );
    _rememberRead(refreshed, workspaceId, sessionId);
    return _summary(_object(refreshed['session']), workspaceId);
  });

  @override
  Future<List<HostMonitor>> listMonitors(String workspaceId) =>
      _guard(() async {
        final result = _object(
          await _client.request('monitor/list', {'workspace_id': workspaceId}),
        );
        return _list(
          result['monitors'],
        ).map((raw) => HostMonitor.fromJson(_object(raw))).toList();
      });

  @override
  Future<HostMonitor> setMonitorEnabled(
    String workspaceId,
    String monitorId,
    bool enabled,
  ) => _guard(() async {
    final result = _object(
      await _client.request(enabled ? 'monitor/enable' : 'monitor/disable', {
        'workspace_id': workspaceId,
        'monitor_id': monitorId,
        'request_id': createTsPhoneClientMessageId(),
      }),
    );
    return HostMonitor.fromJson(_object(result['monitor'] ?? result));
  });

  Map<String, Object?> get _activeTarget {
    final workspace = _workspaceId;
    final session = _sessionId;
    if (workspace == null || session == null) {
      throw const TsPhoneApiException(
        'Select a session first',
        code: 'session_not_found',
      );
    }
    return _target(workspace, session);
  }

  void _rememberRead(
    Map<String, Object?> value,
    String workspace,
    String session,
  ) {
    final summary = _summary(_object(value['session']), workspace);
    if (summary.sessionId != session) {
      throw const FormatException('Host returned another session');
    }
    _workspaceId = workspace;
    _sessionId = session;
  }

  SessionSummary _summary(Map<String, Object?> value, String workspace) {
    final session = _string(value['session_id']);
    if (value['workspace_id'] != workspace) {
      throw const FormatException(
        'Host returned a session from another project',
      );
    }
    _sessions[_key(workspace, session)] = value;
    _sessionWorkspaces[session] = workspace;
    final online = value['online'] == true;
    final readOnly = value['read_only'] == true;
    final streaming = value['is_streaming'] == true;
    return SessionSummary(
      sessionId: session,
      sessionRevision: _revision(workspace, session),
      sessionName: value['name'] as String?,
      model: _model(value['model']),
      runtimeState: !online
          ? RuntimeState.offline
          : streaming
          ? RuntimeState.running
          : RuntimeState.idle,
      isStreaming: streaming,
      accessMode: readOnly
          ? SessionAccessMode.observer
          : SessionAccessMode.controller,
      activeAgentRunId: value['turn_id'] as String?,
      historyAvailable: true,
      historyOnly: readOnly,
      canPrompt: online && !readOnly,
      capabilities: !readOnly && online ? const {'command.model'} : const {},
      updatedAt: _date(value['updated_at'] ?? value['created_at']),
    );
  }

  Map<String, Object?> _snapshotPayload(
    String workspace,
    String session,
    Map<String, Object?> snapshot,
  ) {
    final known = _sessions[_key(workspace, session)];
    final messages = _messages(snapshot);
    final online = snapshot['online'] ?? known?['online'];
    final readOnly = snapshot['read_only'] ?? known?['read_only'];
    return {
      'messages': messages,
      'isStreaming': snapshot['is_streaming'] == true,
      'runtimeState': online != true
          ? 'offline'
          : snapshot['is_streaming'] == true
          ? 'running'
          : 'idle',
      'activeAgentRunId': snapshot['turn_id'],
      'streamingMessage': snapshot['streaming_message'],
      'historyAvailable': messages.isNotEmpty,
      'canPrompt':
          snapshot['can_prompt'] ?? (online == true && readOnly != true),
      'capabilities': online == true && readOnly != true
          ? const ['command.model']
          : const <String>[],
      'accessMode': readOnly == true ? 'observer' : 'controller',
      'sessionName': known?['name'],
    };
  }

  static List<Object?> _messages(Map<String, Object?> snapshot) {
    final messages = _list(
      snapshot['messages'],
    ).map((value) => _object(value)).toList();
    final receipts = snapshot['receipts'];
    if (receipts is List) {
      for (final raw in receipts) {
        if (raw is! Map) continue;
        final index = raw['message_index'];
        final id = raw['client_message_id'];
        if (index is int &&
            index >= 0 &&
            index < messages.length &&
            id is String &&
            messages[index]['role'] == 'user') {
          messages[index]['clientMessageId'] = id;
        }
      }
    }
    return messages;
  }

  String _revision(String workspace, String session) =>
      '$tspiHostProtocol:${settings.serverId}:$workspace:$session';
  static String _key(String workspace, String session) =>
      '$workspace\u0000$session';
  static Map<String, Object?> _target(String workspace, String session) => {
    'workspace_id': workspace,
    'session_id': session,
  };
  static String _eventId(Map<String, Object?> value) =>
      '${_string(value['epoch'])}:${value['sequence']}';
  static String? _model(Object? value) => value is String
      ? value
      : value is Map && value['provider'] is String && value['id'] is String
      ? '${value['provider']}/${value['id']}'
      : null;
  static DateTime? _date(Object? value) => value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
      : value is String
      ? DateTime.tryParse(value)
      : null;

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (_closed) {
      throw const TsPhoneApiException(
        'Host connection closed',
        code: 'connection_closed',
      );
    }
    try {
      return await action();
    } on Object catch (error) {
      throw _translate(error);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_client.close());
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('Invalid Host response');
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('Invalid Host list');
  return value.cast<Object?>();
}

String _string(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid Host identity');
  }
  return value;
}

Object _translate(Object error) {
  if (error is HostRpcException) {
    final definitiveRejection = const {
      'session_offline',
      'session_not_found',
      'workspace_not_found',
      'session_workspace_mismatch',
      'invalid_params',
      'invalid_input',
      'request_id_reused',
      'legacy_session_read_only',
      'model_unavailable',
    }.contains(error.code);
    return TsPhoneApiException(
      error.message,
      code: error.code,
      retryable: error.retryable,
      statusCode: definitiveRejection ? 409 : null,
    );
  }
  return error;
}
