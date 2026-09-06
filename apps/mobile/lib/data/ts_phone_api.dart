import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/connection_settings.dart';
import '../models/session_timeline.dart';
import '../models/workspace.dart';
import 'sse_parser.dart';

class TsPhoneApiException implements Exception {
  const TsPhoneApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

enum TsPhoneProblemKind { authentication, incompatible, unavailable, request }

enum TsPhoneProblemCode {
  incompatible,
  authentication,
  sessionOffline,
  sessionChanged,
  serviceUnavailable,
  connectionFailed,
  requestTimeout,
  requestFailed,
  networkRetrying,
  invalidMessage,
  invalidApproval,
  invalidHistoryMessage,
  approvalExpired,
  approvalStale,
  approvalMissing,
  agentRunChanged,
}

class TsPhoneProblem {
  const TsPhoneProblem(this.kind, this.code);

  final TsPhoneProblemKind kind;
  final TsPhoneProblemCode code;
}

TsPhoneProblem describeTsPhoneProblem(Object error) {
  if (error is TimeoutException) {
    return const TsPhoneProblem(
      TsPhoneProblemKind.unavailable,
      TsPhoneProblemCode.requestTimeout,
    );
  }
  if (error is FormatException) {
    return const TsPhoneProblem(
      TsPhoneProblemKind.incompatible,
      TsPhoneProblemCode.incompatible,
    );
  }
  if (error is TsPhoneApiException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return const TsPhoneProblem(
        TsPhoneProblemKind.authentication,
        TsPhoneProblemCode.authentication,
      );
    }
    if (error.code == 'session_offline') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.sessionOffline,
      );
    }
    if (error.code == 'session_resync_required') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.sessionChanged,
      );
    }
    if (error.code == 'approval_expired') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.approvalExpired,
      );
    }
    if (error.code == 'approval_stale') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.approvalStale,
      );
    }
    if (error.code == 'approval_not_found') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.approvalMissing,
      );
    }
    if (error.code == 'agent_run_stale' || error.code == 'agent_not_running') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.request,
        TsPhoneProblemCode.agentRunChanged,
      );
    }
    if (error.code == 'request_timeout') {
      return const TsPhoneProblem(
        TsPhoneProblemKind.unavailable,
        TsPhoneProblemCode.requestTimeout,
      );
    }
    if (error.statusCode != null && error.statusCode! >= 500) {
      return const TsPhoneProblem(
        TsPhoneProblemKind.unavailable,
        TsPhoneProblemCode.serviceUnavailable,
      );
    }
    return const TsPhoneProblem(
      TsPhoneProblemKind.request,
      TsPhoneProblemCode.requestFailed,
    );
  }
  return const TsPhoneProblem(
    TsPhoneProblemKind.unavailable,
    TsPhoneProblemCode.connectionFailed,
  );
}

class TsPhoneEvent {
  const TsPhoneEvent({
    required this.id,
    required this.workspaceId,
    required this.sessionId,
    required this.sessionRevision,
    required this.instanceEpoch,
    required this.sessionGeneration,
    required this.type,
    required this.payload,
    required this.at,
  });

  factory TsPhoneEvent.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Event must be an object');
    final json = value.cast<String, Object?>();
    if (json['protocolVersion'] != 'ts-phone-events/3' ||
        json['id'] is! String ||
        json['workspaceId'] is! String ||
        json['sessionId'] is! String ||
        json['sessionRevision'] is! String ||
        json['type'] is! String ||
        json['at'] is! String) {
      throw const FormatException('Event envelope is invalid');
    }
    return TsPhoneEvent(
      id: json['id']! as String,
      workspaceId: json['workspaceId']! as String,
      sessionId: json['sessionId']! as String,
      sessionRevision: json['sessionRevision']! as String,
      instanceEpoch: json['instanceEpoch'] as String?,
      sessionGeneration: json['sessionGeneration'] as int?,
      type: json['type']! as String,
      payload: json['payload'],
      at: DateTime.parse(json['at']! as String),
    );
  }

  final String id;
  final String workspaceId;
  final String sessionId;
  final String sessionRevision;
  final String? instanceEpoch;
  final int? sessionGeneration;
  final String type;
  final Object? payload;
  final DateTime at;
}

class TsPhoneMessageSnapshot {
  const TsPhoneMessageSnapshot({
    required this.sessionId,
    required this.sessionRevision,
    required this.messages,
    required this.lastEventId,
    this.activeAgentRunId,
    this.messageIds,
    this.hasMore = false,
    this.nextBefore,
  });

  final String sessionId;
  final String sessionRevision;
  final List<Object?> messages;
  final String lastEventId;
  final String? activeAgentRunId;
  final List<String>? messageIds;
  final bool hasMore;
  final String? nextBefore;
}

class TsPhoneTimelineSnapshot {
  const TsPhoneTimelineSnapshot({
    required this.sessionId,
    required this.sessionRevision,
    required this.items,
    required this.history,
    required this.hasMore,
    required this.lastEventId,
    required this.capabilities,
    this.activeAgentRunId,
    this.nextBefore,
  });

  final String sessionId;
  final String sessionRevision;
  final List<SessionTimelineItem> items;
  final TimelineHistorySummary history;
  final bool hasMore;
  final String? nextBefore;
  final String lastEventId;
  final Set<String> capabilities;
  final String? activeAgentRunId;
}

abstract interface class TsPhoneGateway {
  Future<Map<String, Object?>> version();
  Future<List<WorkspaceSummary>> listWorkspaces();
  Future<List<SessionSummary>> listSessions(String workspaceId);
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  });
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
    String? branch,
  });
  Future<void> sendMessage(
    String workspaceId,
    String sessionId,
    String sessionRevision,
    String message, {
    required String clientMessageId,
  });
  Future<void> abort(
    String workspaceId,
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  });
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  });
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  });
  void close();
}

class TsPhoneApi implements TsPhoneGateway {
  TsPhoneApi(
    this.settings, {
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : assert(!requestTimeout.isNegative && requestTimeout != Duration.zero),
       _client = client ?? http.Client();

  final ConnectionSettings settings;
  final http.Client _client;
  final Duration requestTimeout;

  Map<String, String> get _authorization => <String, String>{
    'Authorization': 'Bearer ${settings.token}',
  };

  @override
  Future<Map<String, Object?>> version() async {
    final data = await _request('GET', 'version');
    return _asMap(data, 'Version response');
  }

  @override
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final data = await _request('GET', 'workspaces');
    if (data is! List) throw const FormatException('Workspace list is invalid');
    return data
        .map((value) => WorkspaceSummary.fromJson(_asMap(value, 'Workspace')))
        .toList(growable: false);
  }

  @override
  Future<List<SessionSummary>> listSessions(String workspaceId) async {
    final data = await _request('GET', _workspacePath(workspaceId, 'sessions'));
    if (data is! List) throw const FormatException('Session list is invalid');
    return data
        .map((value) => SessionSummary.fromJson(_asMap(value, 'Session')))
        .toList(growable: false);
  }

  @override
  Future<TsPhoneMessageSnapshot> getMessages(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
  }) async {
    if (limit != null && (limit < 1 || limit > 500)) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 500');
    }
    final data = _asMap(
      await _request(
        'GET',
        _sessionPath(workspaceId, sessionId, 'messages'),
        queryParameters: <String, String>{
          'before': ?before,
          if (limit != null) 'limit': '$limit',
        },
      ),
      'Messages response',
    );
    final messages = data['messages'];
    final rawMessageIds = data['messageIds'];
    final rawHasMore = data['hasMore'];
    final rawNextBefore = data['nextBefore'];
    final lastEventId = data['lastEventId'];
    final responseSessionId = data['sessionId'];
    final sessionRevision = data['sessionRevision'];
    final activeAgentRunId = data['activeAgentRunId'];
    if (messages is! List ||
        lastEventId is! String ||
        lastEventId.isEmpty ||
        responseSessionId is! String ||
        responseSessionId != sessionId ||
        sessionRevision is! String ||
        !data.containsKey('activeAgentRunId') ||
        !_isOptionalBoundedId(activeAgentRunId)) {
      throw const FormatException('Messages response is invalid');
    }
    List<String>? messageIds;
    if (rawMessageIds != null) {
      if (rawMessageIds is! List ||
          rawMessageIds.length != messages.length ||
          rawMessageIds.any((value) => value is! String)) {
        throw const FormatException('Message ids are invalid');
      }
      messageIds = rawMessageIds.cast<String>();
      if (messageIds.toSet().length != messageIds.length ||
          messageIds.any((id) => !RegExp(r'^[0-9a-f]{8}$').hasMatch(id))) {
        throw const FormatException('Message ids are invalid or not unique');
      }
    }
    final hasMore = rawHasMore ?? false;
    if (hasMore is! bool ||
        (rawNextBefore != null && rawNextBefore is! String) ||
        (hasMore &&
            (messageIds == null ||
                messageIds.isEmpty ||
                rawNextBefore != messageIds.first)) ||
        (!hasMore && rawNextBefore != null)) {
      throw const FormatException('Message pagination is invalid');
    }
    return TsPhoneMessageSnapshot(
      sessionId: responseSessionId,
      sessionRevision: sessionRevision,
      messages: messages.cast<Object?>(),
      lastEventId: lastEventId,
      activeAgentRunId: activeAgentRunId as String?,
      messageIds: messageIds,
      hasMore: hasMore,
      nextBefore: rawNextBefore as String?,
    );
  }

  @override
  Future<TsPhoneTimelineSnapshot> getTimeline(
    String workspaceId,
    String sessionId, {
    String? before,
    int? limit,
    String? branch,
  }) async {
    if (limit != null && (limit < 1 || limit > 500)) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 500');
    }
    final data = _asMap(
      await _request(
        'GET',
        _sessionPath(workspaceId, sessionId, 'timeline'),
        queryParameters: <String, String>{
          'before': ?before,
          if (limit != null) 'limit': '$limit',
          'branch': ?branch,
        },
      ),
      'Timeline response',
    );
    if (data['schemaVersion'] != 'ts-phone-timeline/1' ||
        data['sessionId'] != sessionId ||
        data['sessionRevision'] is! String ||
        data['lastEventId'] is! String ||
        (data['lastEventId']! as String).isEmpty ||
        !data.containsKey('activeAgentRunId') ||
        !_isOptionalBoundedId(data['activeAgentRunId']) ||
        data['items'] is! List ||
        data['hasMore'] is! bool ||
        data['capabilities'] is! List ||
        (data['capabilities']! as List).any((value) => value is! String)) {
      throw const FormatException('Timeline response is invalid');
    }
    final items = (data['items']! as List)
        .map(SessionTimelineItem.fromJson)
        .toList(growable: false);
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Timeline item ids are not unique');
    }
    final hasMore = data['hasMore']! as bool;
    final nextBefore = data['nextBefore'];
    if ((nextBefore != null && nextBefore is! String) ||
        (hasMore && (items.isEmpty || nextBefore != items.first.id)) ||
        (!hasMore && nextBefore != null)) {
      throw const FormatException('Timeline pagination is invalid');
    }
    final history = TimelineHistorySummary.fromJson(data['history']);
    if (history.totalItems < items.length) {
      throw const FormatException('Timeline history totals are invalid');
    }
    return TsPhoneTimelineSnapshot(
      sessionId: sessionId,
      sessionRevision: data['sessionRevision']! as String,
      items: List<SessionTimelineItem>.unmodifiable(items),
      history: history,
      hasMore: hasMore,
      nextBefore: nextBefore as String?,
      lastEventId: data['lastEventId']! as String,
      capabilities: Set<String>.unmodifiable(
        (data['capabilities']! as List).cast<String>(),
      ),
      activeAgentRunId: data['activeAgentRunId'] as String?,
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
    final body = <String, Object?>{
      'clientMessageId': clientMessageId,
      'sessionRevision': sessionRevision,
      'message': message,
    };
    await _request(
      'POST',
      _sessionPath(workspaceId, sessionId, 'messages'),
      body: body,
    );
  }

  @override
  Future<void> abort(
    String workspaceId,
    String sessionId, {
    required String sessionRevision,
    required String agentRunId,
  }) async {
    await _request(
      'POST',
      _sessionPath(workspaceId, sessionId, 'abort'),
      body: <String, Object?>{
        'sessionRevision': sessionRevision,
        'agentRunId': agentRunId,
      },
    );
  }

  @override
  Future<void> respondToApproval(
    String workspaceId,
    String sessionId,
    String approvalId, {
    required String sessionRevision,
    required bool approved,
  }) async {
    await _request(
      'POST',
      '${_sessionPath(workspaceId, sessionId, 'approvals')}/${Uri.encodeComponent(approvalId)}',
      body: <String, Object?>{
        'approved': approved,
        'sessionRevision': sessionRevision,
      },
    );
  }

  @override
  Stream<TsPhoneEvent> events(
    String workspaceId,
    String sessionId, {
    String? lastEventId,
    void Function()? onConnected,
  }) async* {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(
            'GET',
            settings.endpoint(_sessionPath(workspaceId, sessionId, 'events')),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll(<String, String>{
            ..._authorization,
            'Accept': 'text/event-stream',
          });
    if (lastEventId != null) request.headers['Last-Event-ID'] = lastEventId;
    late final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(requestTimeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw const TsPhoneApiException(
        'Request timed out',
        code: 'request_timeout',
      );
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw _apiError(response.statusCode, body);
    }
    onConnected?.call();
    final parser = SseParser();
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final record = parser.addLine(line);
      if (record == null) continue;
      final event = TsPhoneEvent.fromJson(jsonDecode(record.data));
      if (record.id != null && record.id != event.id) {
        throw const FormatException('SSE id does not match its event envelope');
      }
      yield event;
    }
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
  }) async {
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(
            method,
            settings
                .endpoint(path)
                .replace(
                  queryParameters: queryParameters?.isEmpty == true
                      ? null
                      : queryParameters,
                ),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll(_authorization);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    late final http.Response response;
    try {
      response = await _client
          .send(request)
          .then((streamed) => http.Response.fromStream(streamed))
          .timeout(requestTimeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw const TsPhoneApiException(
        'Request timed out',
        code: 'request_timeout',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiError(response.statusCode, response.body);
    }
    final payload = _asMap(jsonDecode(response.body), 'API response');
    if (payload['apiVersion'] != 'ts-phone-api/4') {
      throw const FormatException('Server API version is not supported');
    }
    return payload['data'];
  }

  TsPhoneApiException _apiError(int status, String body) {
    try {
      final payload = _asMap(jsonDecode(body), 'Error response');
      final error = _asMap(payload['error'], 'Error');
      return TsPhoneApiException(
        error['message'] is String
            ? error['message']! as String
            : 'Request failed',
        statusCode: status,
        code: error['code'] as String?,
      );
    } on Object {
      return TsPhoneApiException(
        'Server returned HTTP $status',
        statusCode: status,
      );
    }
  }

  String _workspacePath(String workspaceId, String resource) {
    return 'workspaces/${Uri.encodeComponent(workspaceId)}/$resource';
  }

  String _sessionPath(String workspaceId, String sessionId, String resource) {
    return '${_workspacePath(workspaceId, 'sessions')}/${Uri.encodeComponent(sessionId)}/$resource';
  }

  static Map<String, Object?> _asMap(Object? value, String label) {
    if (value is! Map) throw FormatException('$label is invalid');
    return value.cast<String, Object?>();
  }

  static bool _isOptionalBoundedId(Object? value) =>
      value == null ||
      (value is String && RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(value));

  @override
  void close() => _client.close();
}

String createTsPhoneClientMessageId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final random = Random.secure();
  final entropy = List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return 'phone-$timestamp-$entropy';
}
