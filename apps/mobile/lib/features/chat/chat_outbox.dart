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

  void receive(String revision, String id, {required bool preflightAccepted}) {
    if (preflightAccepted) {
      _accepted.add('$revision\u0000$id');
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
