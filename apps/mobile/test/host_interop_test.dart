import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:corhub/data/host_gateway.dart';
import 'package:corhub/data/host_rpc_client.dart';
import 'package:corhub/data/corhub_api.dart';
import 'package:corhub/models/connection_settings.dart';
import 'package:corhub/models/phone_model.dart';

void main() {
  test(
    'real Host interoperates with the default phone client over WebSocket',
    () async {
      final identity =
          jsonDecode(
                await File(
                  '${Platform.environment['RESEARCH_AGENT_SOURCE']}/config/identity.json',
                ).readAsString(),
              )
              as Map;
      expect(hostProtocol, identity['host_protocol']);
      expect(hostLinkProtocol, identity['link_protocol']);
      expect(identity['device_token_prefix'], 'rad_');
      final directory = await Directory(
        Platform.environment['RESEARCH_AGENT_TEST_ROOT']!,
      ).createTemp('p-');
      final process = await Process.start(
        Platform.environment['NODE_BIN'] ?? 'node',
        [
          '--import',
          '${Platform.environment['RESEARCH_AGENT_TEST_PI_RUNTIME_ROOT']!}/packages/coding-agent/src/experimental/source-resolver.ts',
          'test/fixtures/host_interop.mjs',
          directory.path,
        ],
      );
      final lines = StreamQueue(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      final errors = process.stderr.transform(utf8.decoder).map((chunk) {
        File(
          '${Platform.environment['RESEARCH_AGENT_TEST_RUN_ROOT']}/logs/phone-fixture.log',
        ).writeAsStringSync(chunk, mode: FileMode.append);
        return chunk;
      }).join();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final websockets = <WebSocket>[];
      HostGateway? gateway;
      var stopped = false;
      try {
        final ready =
            jsonDecode(await lines.next.timeout(const Duration(seconds: 30)))
                as Map;
        final socketPath = ready['socketPath'] as String;
        server.listen((request) async {
          expect(request.uri.path, '/v1/link');
          expect(
            request.headers.value('authorization'),
            'Bearer rad_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
          );
          final ws = await WebSocketTransformer.upgrade(
            request,
            protocolSelector: (protocols) => 'research-agent-link.v1',
          );
          websockets.add(ws);
          final socket = await Socket.connect(
            InternetAddress(socketPath, type: InternetAddressType.unix),
            0,
          );
          sockets.add(socket);
          ws.listen(
            (bytes) => socket.add(bytes as List<int>),
            onDone: socket.destroy,
          );
          socket.listen(ws.add, onDone: ws.close);
        });
        gateway = HostGateway(
          ConnectionSettings(
            serverUrl: 'http://127.0.0.1:${server.port}',
            serverId: '123e4567-e89b-42d3-a456-426614174000',
            deviceId: '223e4567-e89b-42d3-a456-426614174000',
            token: 'rad_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
          ),
        );
        final projects = await gateway.listWorkspaces();
        expect(projects.single.id, 'ts_001');
        final monitor = (await gateway.listMonitors('ts_001')).single;
        expect(monitor.state, 'failed');
        expect(monitor.pendingCount, 1);
        expect(monitor.lastError, 'fixture delivery paused');
        expect(monitor.lastObservedAt, DateTime.utc(2026, 10, 9));
        expect(
          (await gateway.setMonitorEnabled(
            'ts_001',
            monitor.id,
            false,
          )).enabled,
          isFalse,
        );
        expect(
          (await gateway.setMonitorEnabled('ts_001', monitor.id, true)).enabled,
          isTrue,
        );
        final session = (await gateway.listSessions('ts_001')).single;
        expect(session.canPrompt, isTrue);
        final events = StreamQueue(gateway.events('ts_001', session.sessionId));
        await events.next;
        expect((await gateway.models()).map((model) => model.id), [
          'one',
          'two',
        ]);
        final selected = await gateway.selectModel(
          'ts_001',
          session.sessionId,
          session.sessionRevision,
          const PhoneModel(provider: 'test', id: 'two', name: 'Two'),
        );
        expect(selected.model, 'test/two');
        await gateway.sendMessage(
          'ts_001',
          session.sessionId,
          session.sessionRevision,
          'calculate',
          clientMessageId: 'same-input',
        );
        await gateway.sendMessage(
          'ts_001',
          session.sessionId,
          session.sessionRevision,
          'calculate',
          clientMessageId: 'same-input',
        );
        final started =
            jsonDecode(await lines.next.timeout(const Duration(seconds: 30)))
                as Map;
        expect(started['stage'], 'model-request');
        var messages = await gateway.getMessages('ts_001', session.sessionId);
        for (
          var attempt = 0;
          attempt < 100 &&
              (messages.messages.isEmpty || messages.activeAgentRunId == null);
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          messages = await gateway.getMessages('ts_001', session.sessionId);
        }
        expect(
          messages.messages.where((raw) => (raw! as Map)['role'] == 'user'),
          hasLength(1),
        );
        final turnId = messages.activeAgentRunId;
        expect(turnId, isNotNull);
        await gateway.abort(
          'ts_001',
          session.sessionId,
          sessionRevision: session.sessionRevision,
          agentRunId: turnId!,
        );
        for (
          var attempt = 0;
          attempt < 100 && messages.activeAgentRunId != null;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          messages = await gateway.getMessages('ts_001', session.sessionId);
        }
        expect(messages.activeAgentRunId, isNull);
        await events.cancel();
        gateway.close();
        gateway = null;
        process.stdin.writeln('stop');
        final result =
            jsonDecode(await lines.next.timeout(const Duration(seconds: 30)))
                as Map;
        expect(result['delivered'], 1);
        expect(
          await process.exitCode.timeout(const Duration(seconds: 30)),
          0,
          reason: await errors,
        );
        stopped = true;
        expect(await File(socketPath).exists(), isFalse);
      } on CorHubApiException catch (error) {
        throw StateError('Host RPC failed (${error.code})');
      } finally {
        gateway?.close();
        for (final ws in websockets) {
          unawaited(ws.close());
        }
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close(force: true);
        if (!stopped) {
          process.kill();
          await process.exitCode.timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
        }
        await lines.cancel();
        await directory.delete(recursive: true);
      }
    },
    skip:
        Platform.environment['RESEARCH_AGENT_SOURCE'] == null ||
            Platform.environment['RESEARCH_AGENT_TEST_ROOT'] == null ||
            Platform.environment['RESEARCH_AGENT_TEST_PI_RUNTIME_ROOT'] ==
                null ||
            Platform.environment['RESEARCH_AGENT_PYTHON'] == null ||
            Platform.environment['RESEARCH_AGENT_TEST_SOCKET_ROOT'] == null ||
            Platform.environment['RESEARCH_AGENT_TEST_RUN_ROOT'] == null
        ? 'Set RESEARCH_AGENT_SOURCE, RESEARCH_AGENT_TEST_ROOT, RESEARCH_AGENT_TEST_PI_RUNTIME_ROOT and RESEARCH_AGENT_PYTHON for cross-repository verification'
        : false,
  );
}
