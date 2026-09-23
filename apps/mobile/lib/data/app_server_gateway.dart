import 'dart:async';

import '../models/connection_settings.dart';
import '../models/phone_model.dart';
import '../models/workspace.dart';
import 'pi_app_server_client.dart';
import 'ts_phone_api.dart';

const appServerWorkspaceId = 'app-server';

abstract interface class AppServerSessionGateway {
  Future<SessionSummary> createSession();
  Future<void> removeSession(String sessionId);
}

abstract interface class AppServerWorkspaceGateway {
  Future<WorkspaceSummary> createWorkspace(String workspaceId);
}

abstract interface class WorkspaceSessionGateway {
  Future<SessionSummary> createWorkspaceSession(String workspaceId);
  Future<void> removeWorkspaceSession(String workspaceId, String sessionId);
}

abstract interface class SessionResumeGateway {
  Future<SessionSummary> resumeWorkspaceSession(
    String workspaceId,
    String sessionId,
  );
}

extension AppServerWorkspaceSessionGateway on AppServerSessionGateway {
  Future<SessionSummary> createWorkspaceSession(String workspaceId) {
    final gateway = this;
    return gateway is WorkspaceSessionGateway
        ? gateway.createWorkspaceSession(workspaceId)
        : gateway.createSession();
  }

  Future<void> removeWorkspaceSession(String workspaceId, String sessionId) {
    final gateway = this;
    return gateway is WorkspaceSessionGateway
        ? gateway.removeWorkspaceSession(workspaceId, sessionId)
        : gateway.removeSession(sessionId);
  }
}

class PiAppServerGateway
    implements
        TsPhoneGateway,
        TsPhoneModelGateway,
        AppServerSessionGateway,
        AppServerWorkspaceGateway,
        WorkspaceSessionGateway {
  PiAppServerGateway(this.settings, {PiAppServerClient? client})
    : _client =
          client ??
          PiAppServerClient(
            gateway: Uri.parse(settings.serverUrl),
            serverId: settings.serverId,
            token: settings.token,
          );

  final ConnectionSettings settings;
  final PiAppServerClient _client;
  final Map<String, Map<String, Object?>> _transcripts = {};
  final Map<String, String> _sessionRevisions = {};
  final Map<String, WorkspaceSummary> _workspaces = {};
  final Map<String, String> _workspaceRoots = {};
  final Map<String, String> _sessionWorkspaces = {};
  int _eventSequence = 0;
  bool _closed = false;

  @override
  Future<Map<String, Object?>> version() async {
    await _guard(() => _client.connect());
    return {
      'apiVersion': 'pi-app-server/$piAppServerProtocolVersion',
      'serviceVersion': 'Pi App Server',
      'serverId': settings.serverId,
    };
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    try {
      return await _guard(() async {
        final raw = await _client.request(
          _client.serverTarget,
          'tspi.workspace-directory',
          'list',
          const [],
        );
        if (raw is! List) {
          throw const FormatException('Workspace directory is invalid');
        }
        final roots = <String, String>{};
        final workspaces = <WorkspaceSummary>[];
        for (final value in raw) {
          final item = _object(value, 'workspace');
          final id = _string(item['workspaceId'], 'workspace id');
          final name = _string(item['name'], 'workspace name');
          final root = _string(item['root'], 'workspace root');
          roots[id] = root;
          workspaces.add(
            WorkspaceSummary(
              id: id,
              name: name,
              runtimeState: RuntimeState.idle,
              isStreaming: false,
              liveSessionCount: 0,
              sessionCount: 0,
            ),
          );
        }
        _workspaceRoots
          ..clear()
          ..addAll(roots);
        final sessions = await _listSessionSummaries();
        final counts = <String, List<SessionSummary>>{};
        for (final session in sessions) {
          final workspaceId = _sessionWorkspaces[session.sessionId];
          if (workspaceId != null) {
            counts.putIfAbsent(workspaceId, () => []).add(session);
          }
        }
        final projected = workspaces
            .map((workspace) {
              final matching = counts[workspace.id] ?? const <SessionSummary>[];
              return WorkspaceSummary(
                id: workspace.id,
                name: workspace.name,
                runtimeState: RuntimeState.idle,
                isStreaming: matching.any((session) => session.isStreaming),
                liveSessionCount: matching.length,
                sessionCount: matching.length,
              );
            })
            .toList(growable: false);
        _workspaces
          ..clear()
          ..addEntries(
            projected.map((workspace) => MapEntry(workspace.id, workspace)),
          );
        return projected;
      });
    } on TsPhoneApiException catch (error) {
      // Older App Server builds exposed no workspace directory. Keep a
      // compatibility presentation until the managed Host is upgraded.
      if (error.code != 'service_not_found' &&
          error.code != 'service_member_not_found') {
        rethrow;
      }
      final sessions = await _guard(_listSessionSummaries);
      for (final session in sessions) {
        _sessionWorkspaces[session.sessionId] = appServerWorkspaceId;
      }
      final fallback = WorkspaceSummary(
        id: appServerWorkspaceId,
        name: 'App Server',
        runtimeState: RuntimeState.idle,
        isStreaming: sessions.any((session) => session.isStreaming),
        liveSessionCount: sessions.length,
        sessionCount: sessions.length,
      );
      _workspaces[appServerWorkspaceId] = fallback;
      return [fallback];
    }
  }

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async {
    await _ensureWorkspace(workspaceId);
    final sessions = await _guard(_listSessionSummaries);
    if (workspaceId == appServerWorkspaceId) return sessions;
    return sessions
        .where(
          (session) => _sessionWorkspaces[session.sessionId] == workspaceId,
        )
        .toList(growable: false);
  }

  @override
  Future<SessionSummary> createSession() =>
      createWorkspaceSession(_defaultWorkspaceId);

  @override
  Future<WorkspaceSummary> createWorkspace(String workspaceId) =>
      _guard(() async {
        final value = await _client.request(
          _client.serverTarget,
          'tspi.workspace-directory',
          'create',
          [workspaceId],
        );
        final item = _object(value, 'workspace');
        final id = _string(item['workspaceId'], 'workspace id');
        final name = _string(item['name'], 'workspace name');
        final root = _string(item['root'], 'workspace root');
        final workspace = WorkspaceSummary(
          id: id,
          name: name,
          runtimeState: RuntimeState.idle,
          isStreaming: false,
          liveSessionCount: 0,
          sessionCount: 0,
        );
        _workspaceRoots[id] = root;
        _workspaces[id] = workspace;
        return workspace;
      });

  @override
  Future<SessionSummary> createWorkspaceSession(String workspaceId) =>
      _guard(() async {
        final selectedWorkspace = workspaceId;
        await _ensureWorkspace(selectedWorkspace);
        final result = await _client.request(
          _client.serverTarget,
          'pi.session-management',
          'create',
          [
            <String, Object?>{
              if (_workspaceRoots[selectedWorkspace] != null)
                'workspaceId': selectedWorkspace,
            },
          ],
        );
        final summary = _sessionSummary(result);
        _sessionWorkspaces[summary.sessionId] = selectedWorkspace;
        return summary;
      });

  @override
  Future<void> removeSession(String sessionId) =>
      removeWorkspaceSession('', sessionId);

  @override
  Future<void> removeWorkspaceSession(String workspaceId, String sessionId) =>
      _guard(() async {
        final selectedSession = sessionId;
        await _client.request(
          _client.serverTarget,
          'pi.session-management',
          'remove',
          [selectedSession],
        );
        _transcripts.remove(selectedSession);
        _sessionRevisions.remove(selectedSession);
        _sessionWorkspaces.remove(selectedSession);
      });

  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  }) async {
    _requireWorkspace(workspaceId);
    if (before != null) {
      throw const TsPhoneApiException(
        'Pi App Server publishes the complete active transcript',
        code: 'history_window_unsupported',
      );
    }
    return _guard(() async {
      await _client.attach(sessionId);
      final state = await _client.subscribe(
        _client.sessionTarget,
        'pi.transcript',
      );
      try {
        final transcript = _object(state.value, 'transcript state');
        _transcripts[sessionId] = transcript;
        return _messageSnapshot(sessionId, transcript);
      } finally {
        await state.close();
      }
    });
  }

  @override
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
    String? branch,
  }) {
    throw const TsPhoneApiException(
      'Pi App Server does not expose the legacy timeline projection',
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
  }) async {
    await _ensureWorkspace(workspaceId);
    await _guard(() async {
      await _client.attach(sessionId);
      final current = _transcripts[sessionId];
      final snapshot = current?['snapshot'];
      final operation = snapshot is Map ? snapshot['operation'] : null;
      final member = operation == null ? 'prompt' : 'followUp';
      final response = _object(
        await _client.request(
          _client.sessionTarget,
          'pi.agent-controller',
          member,
          [
            {'message': message, 'images': null},
          ],
        ),
        'agent operation response',
      );
      if (response['accepted'] != true) {
        final error = response['error'];
        final details = error is Map
            ? Map<String, Object?>.from(error)
            : const <String, Object?>{};
        throw TsPhoneApiException(
          details['message'] as String? ?? 'App Server rejected the prompt',
          code: details['code'] as String? ?? 'prompt_rejected',
          statusCode: 409,
        );
      }
    });
  }

  @override
  Future<void> abort(
    String workspaceId,
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  }) async {
    await _ensureWorkspace(workspaceId);
    await _guard(() async {
      await _client.attach(sessionId);
      await _client.request(
        _client.sessionTarget,
        'pi.agent-controller',
        'requestAbort',
        [agentRunId],
      );
    });
  }

  @override
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  }) {
    throw const TsPhoneApiException(
      'App Server does not expose remote approval responses',
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
    _requireWorkspace(workspaceId);
    late final StreamController<TsPhoneEvent> controller;
    PiServiceState? state;
    StreamSubscription<Object?>? updates;

    Future<void> stop() async {
      await updates?.cancel();
      await state?.close();
    }

    Future<void> start() async {
      try {
        await _guard(() => _client.attach(sessionId));
        state = await _guard(
          () => _client.subscribe(_client.sessionTarget, 'pi.transcript'),
        );
        final initial = _object(state!.value, 'transcript state');
        _transcripts[sessionId] = initial;
        onConnected?.call();
        updates = state!.updates.listen(
          (value) {
            try {
              final transcript = _object(value, 'transcript state');
              _transcripts[sessionId] = transcript;
              controller.add(_transcriptEvent(sessionId, transcript));
            } on Object catch (error, stackTrace) {
              controller.addError(_translateError(error), stackTrace);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            controller.addError(_translateError(error), stackTrace);
          },
          onDone: controller.close,
        );
      } on Object catch (error, stackTrace) {
        controller.addError(_translateError(error), stackTrace);
        await controller.close();
      }
    }

    controller = StreamController<TsPhoneEvent>(
      onListen: () => unawaited(start()),
      onCancel: stop,
    );
    return controller.stream;
  }

  @override
  Future<List<PhoneModel>> models() => _guard(() async {
    final attachment = _client.sessionTarget;
    final state = await _client.subscribe(attachment, 'pi.models');
    try {
      final models = _object(state.value, 'models state');
      final catalog = _object(models['catalog'], 'model catalog');
      final available = catalog['availableModels'];
      if (available is! List) {
        throw const FormatException('Model catalog is invalid');
      }
      return available
          .map((value) {
            final model = _object(value, 'model');
            return PhoneModel(
              provider: _string(model['provider'], 'model provider'),
              id: _string(model['modelId'], 'model id'),
              name: _string(model['name'], 'model name'),
            );
          })
          .toList(growable: false);
    } finally {
      await state.close();
    }
  });

  @override
  Future<SessionSummary> selectModel(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    PhoneModel model,
  ) async {
    _requireWorkspace(workspaceId);
    return _guard(() async {
      await _client.attach(sessionId);
      await _client.request(_client.sessionTarget, 'pi.models', 'select', [
        {'provider': model.provider, 'modelId': model.id},
      ]);
      return _summaryFromTranscript(
        sessionId,
        _transcripts[sessionId],
        model: model.reference,
      );
    });
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_client.close());
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (_closed) {
      throw const TsPhoneApiException(
        'App Server connection is closed',
        code: 'connection_closed',
      );
    }
    try {
      return await action();
    } on Object catch (error) {
      throw _translateError(error);
    }
  }

  TsPhoneEvent _transcriptEvent(String sessionId, Map<String, Object?> state) {
    final eventId = 'pi-${++_eventSequence}';
    return TsPhoneEvent(
      id: eventId,
      workspaceId: _sessionWorkspaces[sessionId] ?? appServerWorkspaceId,
      sessionId: sessionId,
      sessionRevision: _revision(sessionId),
      instanceEpoch: settings.serverId,
      sessionGeneration: null,
      type: 'session.snapshot',
      payload: _snapshotPayload(state),
      at: DateTime.now(),
    );
  }

  TsPhoneMessageSnapshot _messageSnapshot(
    String sessionId,
    Map<String, Object?> state,
  ) {
    final projected = _projectMessages(state['snapshot']);
    return TsPhoneMessageSnapshot(
      sessionId: sessionId,
      sessionRevision: _revision(sessionId),
      messages: projected.messages,
      messageIds: projected.ids,
      lastEventId: 'pi-$_eventSequence',
      activeAgentRunId: _operationId(state['snapshot']),
    );
  }

  Map<String, Object?> _snapshotPayload(Map<String, Object?> state) {
    final snapshot = state['snapshot'];
    final projected = _projectMessages(snapshot);
    final snapshotMap = snapshot is Map
        ? Map<String, Object?>.from(snapshot)
        : const <String, Object?>{};
    final operation = snapshotMap['operation'];
    final operationMap = operation is Map
        ? Map<String, Object?>.from(operation)
        : null;
    return {
      'messages': projected.messages,
      'isStreaming': operationMap != null,
      'activeAgentRunId': operationMap?['id'],
      'streamingMessage': operationMap?['streamingMessage'],
      'historyAvailable': projected.messages.isNotEmpty,
      'canPrompt': true,
      'capabilities': const <String>['command.model'],
      'accessMode': 'controller',
    };
  }

  SessionSummary _sessionSummary(Object? value) {
    final session = _object(value, 'session');
    final sessionId = _string(session['sessionId'], 'session id');
    final createdAt = session['createdAt'];
    if (createdAt is! num || createdAt < 0) {
      throw const FormatException('Session creation time is invalid');
    }
    if (session['serverId'] != settings.serverId) {
      throw const FormatException('Session belongs to another App Server');
    }
    final cwd = session['cwd'];
    if (cwd is String && cwd.isNotEmpty) {
      final workspaceId = _workspaceRoots.entries
          .where((entry) => entry.value == cwd)
          .map((entry) => entry.key)
          .firstOrNull;
      if (workspaceId != null) _sessionWorkspaces[sessionId] = workspaceId;
    }
    _sessionRevisions[sessionId] =
        'pi-app-server-$piAppServerProtocolVersion-${settings.serverId}-$sessionId-${createdAt.toInt()}';
    return _summaryFromTranscript(
      sessionId,
      _transcripts[sessionId],
      updatedAt: DateTime.fromMillisecondsSinceEpoch(createdAt.toInt()),
    );
  }

  SessionSummary _summaryFromTranscript(
    String sessionId,
    Map<String, Object?>? state, {
    DateTime? updatedAt,
    String? model,
  }) {
    final snapshot = state?['snapshot'];
    final operationId = _operationId(snapshot);
    final snapshotMap = snapshot is Map
        ? Map<String, Object?>.from(snapshot)
        : const <String, Object?>{};
    final configuration = snapshotMap['configuration'];
    final configurationMap = configuration is Map
        ? Map<String, Object?>.from(configuration)
        : const <String, Object?>{};
    final selectedModel = configurationMap['model'];
    final selectedModelMap = selectedModel is Map
        ? Map<String, Object?>.from(selectedModel)
        : null;
    final modelReference =
        model ??
        (selectedModelMap == null
            ? null
            : '${selectedModelMap['provider']}/${selectedModelMap['modelId']}');
    return SessionSummary(
      sessionId: sessionId,
      sessionRevision: _revision(sessionId),
      runtimeState: operationId == null
          ? RuntimeState.idle
          : RuntimeState.running,
      isStreaming: operationId != null,
      accessMode: SessionAccessMode.controller,
      model: modelReference,
      activeAgentRunId: operationId,
      historyAvailable: _projectMessages(snapshot).messages.isNotEmpty,
      canPrompt: true,
      capabilities: const {'command.model'},
      updatedAt: updatedAt,
    );
  }

  String _revision(String sessionId) =>
      _sessionRevisions[sessionId] ??
      'pi-app-server-$piAppServerProtocolVersion-${settings.serverId}-$sessionId';

  static String? _operationId(Object? snapshot) {
    if (snapshot is! Map) return null;
    final operation = snapshot['operation'];
    if (operation is! Map) return null;
    return operation['id'] as String?;
  }

  static _ProjectedMessages _projectMessages(Object? rawSnapshot) {
    if (rawSnapshot is! Map) return const _ProjectedMessages([], []);
    final transcript = rawSnapshot['transcript'];
    if (transcript is! List) return const _ProjectedMessages([], []);
    final messages = <Object?>[];
    final ids = <String>[];
    for (final rawEntry in transcript) {
      if (rawEntry is! Map) continue;
      final entry = Map<String, Object?>.from(rawEntry);
      final id = entry['id'];
      if (id is! String || id.isEmpty) continue;
      if (entry['type'] == 'message' && entry['message'] is Map) {
        messages.add(Map<String, Object?>.from(entry['message']! as Map));
        ids.add(id);
      } else if (entry['type'] == 'compaction' &&
          entry['retainedTail'] is List) {
        final retained = entry['retainedTail']! as List;
        for (var index = 0; index < retained.length; index += 1) {
          final message = retained[index];
          if (message is! Map) continue;
          messages.add(Map<String, Object?>.from(message));
          ids.add('$id:retained:$index');
        }
      }
    }
    return _ProjectedMessages(messages, ids);
  }

  String get _defaultWorkspaceId =>
      _workspaces.keys.firstOrNull ?? appServerWorkspaceId;

  Future<void> _ensureWorkspace(String workspaceId) async {
    if (workspaceId == appServerWorkspaceId && _workspaces.isEmpty) {
      _workspaces[workspaceId] = const WorkspaceSummary(
        id: appServerWorkspaceId,
        name: 'App Server',
        runtimeState: RuntimeState.idle,
        isStreaming: false,
        liveSessionCount: 0,
        sessionCount: 0,
      );
      return;
    }
    if (!_workspaces.containsKey(workspaceId)) {
      await listWorkspaces();
    }
    _requireWorkspace(workspaceId);
  }

  void _requireWorkspace(String workspaceId) {
    if (!_workspaces.containsKey(workspaceId) &&
        workspaceId != appServerWorkspaceId) {
      throw const TsPhoneApiException(
        'Workspace is not present in the connected Host',
        code: 'workspace_not_found',
        statusCode: 404,
      );
    }
  }

  Future<List<SessionSummary>> _listSessionSummaries() async {
    final state = await _client.subscribe(
      _client.serverTarget,
      'pi.session-directory',
    );
    try {
      final directory = _object(state.value, 'session directory');
      _positiveInt(directory['revision'], 'directory revision');
      final rawSessions = directory['sessions'];
      if (rawSessions is! List) {
        throw const FormatException('Session directory is invalid');
      }
      return rawSessions.map(_sessionSummary).toList(growable: false);
    } finally {
      await state.close();
    }
  }
}

class _ProjectedMessages {
  const _ProjectedMessages(this.messages, this.ids);

  final List<Object?> messages;
  final List<String> ids;
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('$label is invalid');
  return Map<String, Object?>.from(value);
}

String _string(Object? value, String label) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$label is invalid');
  }
  return value;
}

int _positiveInt(Object? value, String label) {
  if (value is! int || value < 0) {
    throw FormatException('$label is invalid');
  }
  return value;
}

TsPhoneApiException _translateError(Object error) {
  if (error is TsPhoneApiException) return error;
  if (error is PiAppServerException) {
    return TsPhoneApiException(error.message, code: error.code);
  }
  if (error is TimeoutException) {
    return const TsPhoneApiException(
      'App Server request timed out',
      code: 'request_timeout',
    );
  }
  return TsPhoneApiException(error.toString(), code: 'connection_failed');
}
