import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ts_phone/data/host_gateway.dart';
import 'package:ts_phone/models/connection_settings.dart';
import 'package:ts_phone/models/phone_model.dart';

void main() {
  test(
    'real Host interoperates with the default phone client over WebSocket',
    () async {
      final directory = await Directory(
        Platform.environment['TSPI_TEST_ROOT']!,
      ).createTemp('phone-wire-');
      final process = await Process.start(
        Platform.environment['NODE_BIN'] ?? 'node',
        ['test/fixtures/host_interop.mjs', directory.path],
      );
      final lines = StreamQueue(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      final errors = process.stderr.transform(utf8.decoder).join();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final websockets = <WebSocket>[];
      HostGateway? gateway;
      var stopped = false;
      try {
        final ready =
            jsonDecode(await lines.next.timeout(const Duration(seconds: 10)))
                as Map;
        final socketPath = ready['socketPath'] as String;
        server.listen((request) async {
          expect(request.uri.path, '/v1/link');
          expect(
            request.headers.value('authorization'),
            'Bearer tspd_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
          );
          final ws = await WebSocketTransformer.upgrade(
            request,
            protocolSelector: (protocols) => 'tspi-link.v1',
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
            token: 'tspd_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ',
          ),
        );
        final projects = await gateway.listWorkspaces();
        expect(projects.single.id, 'ts_001');
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
        final messages = await gateway.getMessages('ts_001', session.sessionId);
        expect(messages.messages, hasLength(1));
        expect(
          (messages.messages.single! as Map)['clientMessageId'],
          'same-input',
        );
        expect(messages.activeAgentRunId, 'turn-1');
        await gateway.abort(
          'ts_001',
          session.sessionId,
          sessionRevision: session.sessionRevision,
          agentRunId: 'turn-1',
        );
        expect(
          (await gateway.getMessages(
            'ts_001',
            session.sessionId,
          )).activeAgentRunId,
          isNull,
        );
        await events.cancel();
        gateway.close();
        gateway = null;
        process.stdin.writeln('stop');
        final result =
            jsonDecode(await lines.next.timeout(const Duration(seconds: 10)))
                as Map;
        expect(result['delivered'], 1);
        expect(
          await process.exitCode.timeout(const Duration(seconds: 10)),
          0,
          reason: await errors,
        );
        stopped = true;
        expect(await File(socketPath).exists(), isFalse);
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
            const Duration(seconds: 10),
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
        Platform.environment['TSPI_SOURCE'] == null ||
            Platform.environment['TSPI_TEST_ROOT'] == null
        ? 'Set TSPI_SOURCE and TSPI_TEST_ROOT for isolated cross-repository verification'
        : false,
  );
}
