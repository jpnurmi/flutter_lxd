import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xterm/flutter.dart';
import 'package:xterm/xterm.dart';

import 'backend.dart';

void main(List<String> args) {
  if (args.length != 1) {
    print('Usage: flutter_lxd <running instance>');
    exit(1);
  }

  final http = HttpClient();
  http.connectionFactory = (uri, proxyHost, proxyPort) async {
    final path = await resolveLxdSocketPath();
    final address = InternetAddress(path, type: InternetAddressType.unix);
    return Socket.startConnect(address, 0);
  };

  final backend = LxdTerminalBackend(http, args.single);
  final terminal = Terminal(backend: backend, maxLines: 10000);
  runApp(MaterialApp(home: Scaffold(body: TerminalView(terminal: terminal))));
}
