import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class GatewayService extends ChangeNotifier {
  WebSocketChannel? _channel;
  final List<Map<String, dynamic>> messages = [];
  String gatewayHost = 'ws://192.168.4.1:81';

  void connect() {
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(Uri.parse(gatewayHost));
    _channel!.stream.listen((event) {
      final parsed = jsonDecode(event as String) as Map<String, dynamic>;
      messages.insert(0, parsed);
      if (messages.length > 200) messages.removeLast();
      notifyListeners();
    });
  }

  void sendCommand({required String deviceId, required String command, required Map<String, dynamic> payload}) {
    final msg = {'type': 'send_command', 'device_id': int.tryParse(deviceId) ?? 0, 'command': command, 'payload': payload};
    _channel?.sink.add(jsonEncode(msg));
  }
}
