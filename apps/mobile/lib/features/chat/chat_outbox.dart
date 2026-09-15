import 'package:flutter/foundation.dart';

import '../../models/chat_message.dart';

class OutgoingChatMessage {
  OutgoingChatMessage({
    required this.revision,
    required this.id,
    required this.text,
  }) : at = DateTime.now();

  final String revision;
  final String id;
  final String text;
  final DateTime at;
  ChatDeliveryState state = ChatDeliveryState.sending;
}

/// Session-scoped receipts survive route disposal, but never dispatch messages.
class ChatOutbox extends ChangeNotifier {
  final _messages = <String, OutgoingChatMessage>{};
  final _inFlight = <String>{};
  final _accepted = <String>{};
  final _delivered = <String>{};

  Iterable<OutgoingChatMessage> get messages => _messages.values;
  bool get isSending => _inFlight.isNotEmpty;
  bool get hasUnresolved =>
      isSending ||
      _messages.values.any(
        (value) => value.state == ChatDeliveryState.uncertain,
      );

  OutgoingChatMessage? uncertain(String text) => _messages.values
      .where(
        (value) =>
            value.state == ChatDeliveryState.uncertain && value.text == text,
      )
      .firstOrNull;

  bool accepted(OutgoingChatMessage message) =>
      _accepted.contains('${message.revision}\u0000${message.id}');

  void reconcile(String revision, Iterable<ChatMessage> history) {
    final available = history
        .where((value) => value.role == ChatRole.user)
        .toList();
    for (final message in _messages.values.toList()) {
      if (message.revision != revision) continue;
      final index = available.indexWhere(
        (value) =>
            value.clientMessageId == message.id ||
            // Text matching only removes an already acknowledged local echo.
            // It can never turn uncertain delivery into accepted delivery.
            message.state == ChatDeliveryState.synchronizing &&
                value.text == message.text &&
                value.timestamp != null &&
                !value.timestamp!.isBefore(message.at) &&
                value.timestamp!.difference(message.at) <
                    const Duration(minutes: 2),
      );
      if (index < 0) continue;
      available.removeAt(index);
      receive(revision, message.id, preflightAccepted: true);
    }
  }

  void begin(OutgoingChatMessage message) {
    message.state = ChatDeliveryState.sending;
    _messages[message.id] = message;
    _inFlight.add(message.id);
    notifyListeners();
  }

  void finish(
    OutgoingChatMessage message, {
    required bool sent,
    bool uncertain = false,
  }) {
    _inFlight.remove(message.id);
    if (accepted(message)) {
      _messages.remove(message.id);
    } else if (sent || uncertain) {
      message.state = sent
          ? ChatDeliveryState.synchronizing
          : ChatDeliveryState.uncertain;
      _messages[message.id] = message;
    } else {
      _messages.remove(message.id);
    }
    notifyListeners();
  }

  /// Records local delivery state while keeping the optimistic message
  /// visible until the App Server publishes the matching transcript. Admission is
  /// already confirmed, but execution has not started yet, so the message is
  /// shown as waiting for live synchronization rather than as an uncertain
  /// delivery.
  void admit(OutgoingChatMessage message) {
    final identity = '${message.revision}\u0000${message.id}';
    _accepted.add(identity);
    while (_accepted.length > 200) {
      _accepted.remove(_accepted.first);
    }
    _inFlight.remove(message.id);
    // A fast App Server can publish the transcript before the request response arrives.
    // In that case the canonical message is already in the timeline and the
    // optimistic copy must not be re-added by the late receipt.
    if (_delivered.contains(identity)) {
      _messages.remove(message.id);
      notifyListeners();
      return;
    }
    message.state = ChatDeliveryState.synchronizing;
    _messages[message.id] = message;
    notifyListeners();
  }

  /// Drops a local optimistic copy after a request is rejected before execution.
  /// The App Server transcript remains the source of
  /// truth; this only removes the transient chat rendering.
  void discard(String revision, String id) {
    _messages.removeWhere(
      (key, value) => key == id && value.revision == revision,
    );
    _inFlight.remove(id);
    notifyListeners();
  }

  void receive(String revision, String id, {required bool preflightAccepted}) {
    final identity = '$revision\u0000$id';
    _delivered.add(identity);
    while (_delivered.length > 200) {
      _delivered.remove(_delivered.first);
    }
    if (preflightAccepted) {
      _accepted.add(identity);
      while (_accepted.length > 200) {
        _accepted.remove(_accepted.first);
      }
    }
    if (_messages[id]?.revision == revision) {
      _messages.remove(id);
      notifyListeners();
    }
  }
}
