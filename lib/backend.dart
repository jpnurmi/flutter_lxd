import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xterm/xterm.dart';

class LxdTerminalBackend implements TerminalBackend {
  LxdTerminalBackend(this.http, this.name);

  final String name;
  final HttpClient http;
  final _exitCode = Completer<int>();
  final _out = StreamController<String>();

  WebSocket? _ws0;
  WebSocket? _wsc;

  @override
  Stream<String> get out => _out.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  void init() => _execBash(name);

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {
    _wsc?.add(jsonEncode({
      'command': 'window-resize',
      'args': {'width': '$width', 'height': '$height'},
    }));
  }

  @override
  void write(String input) => _ws0?.add(utf8.encode(input));

  @override
  void ackProcessed() {}

  @override
  void terminate() {
    _ws0?.close();
    _wsc = null;
    _wsc?.close();
    _wsc = null;
  }

  Future<void> _execBash(String name) async {
    final response =
        await _sendRequest('POST', '/1.0/instances/$name/exec', body: {
      'command': ['/bin/bash'],
      'environment': {
        'TERM': 'xterm-256color',
      },
      'interactive': true,
      'wait-for-websocket': true,
      'width': 80,
      'height': 25,
    });

    final op = response['metadata'];
    print(op);

    final id = op['id'] as String;
    _wsc = await _createWebSocket(id, op['metadata']['fds']['control']);
    _ws0 = await _createWebSocket(id, op['metadata']['fds']['0']);
    _ws0!.listen(_receiveData);
  }

  void _receiveData(dynamic data) {
    if (data is List<int>) {
      _out.sink.add(utf8.decode(data));
    } else if (data is String) {
      _out.sink.add('$data\r\n');
    } else {
      throw UnsupportedError(data);
    }
  }

  Future<WebSocket> _createWebSocket(String id, String fd) {
    return WebSocket.connect(
      'ws://localhost/1.0/operations/$id/websocket?secret=$fd',
      customClient: http,
    );
  }

  Future<Map<String, dynamic>> _sendRequest(
    String method,
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? body,
  }) async {
    final url = Uri.http('localhost', path, params);
    final request = await http.openUrl(method, url);
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close().then((response) => response
        .transform(utf8.decoder)
        .join()
        .then((data) => jsonDecode(data)));
    if (response['type'] == 'error') {
      throw ArgumentError(const JsonEncoder.withIndent('  ').convert(response));
    }
    return response;
  }
}

Future<String> resolveLxdSocketPath() async {
  String socketPath;
  var lxdDir = Platform.environment['LXD_DIR'];
  var snapSocketPath = '/var/snap/lxd/common/lxd/unix.socket';
  if (lxdDir != null) {
    socketPath = '$lxdDir/unix.socket';
  } else if (await File(snapSocketPath).exists()) {
    socketPath = snapSocketPath;
  } else {
    socketPath = '/var/lib/lxd/unix.socket';
  }
  return socketPath;
}
