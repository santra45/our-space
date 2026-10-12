import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract class SignalSocket {
  void Function()? onOpen;
  void Function(String data)? onMessage;
  void Function()? onClose;

  bool get isOpen;

  void send(String data);

  void close();
}

typedef SignalSocketConnector = SignalSocket Function(Uri url);

class IoSignalSocket implements SignalSocket {
  IoSignalSocket(Uri url, {Duration connectTimeout = const Duration(seconds: 20)}) {
    WebSocket.connect(url.toString()).timeout(connectTimeout).then(_adopt, onError: (Object _) => _lost());
  }

  static SignalSocket connect(Uri url) => IoSignalSocket(url);

  WebSocket? _ws;
  StreamSubscription<dynamic>? _subscription;
  bool _closedLocally = false;
  bool _lostReported = false;

  @override
  void Function()? onOpen;
  @override
  void Function(String data)? onMessage;
  @override
  void Function()? onClose;

  void _adopt(WebSocket ws) {
    if (_closedLocally) {
      unawaited(ws.close());
      return;
    }
    _ws = ws;
    _subscription = ws.listen(
      (data) {
        if (_closedLocally) return;
        final text = data is String ? data : utf8.decode(data as List<int>, allowMalformed: true);
        onMessage?.call(text);
      },
      onDone: _lost,
      onError: (Object _) => _lost(),
      cancelOnError: true,
    );
    onOpen?.call();
  }

  void _lost() {
    if (_closedLocally || _lostReported) return;
    _lostReported = true;
    _ws = null;
    onClose?.call();
  }

  @override
  bool get isOpen => !_closedLocally && _ws != null && _ws!.readyState == WebSocket.open;

  @override
  void send(String data) {
    final ws = _ws;
    if (!isOpen || ws == null) return;
    ws.add(data);
  }

  @override
  void close() {
    if (_closedLocally) return;
    _closedLocally = true;
    onOpen = null;
    onMessage = null;
    onClose = null;
    unawaited(_subscription?.cancel());
    final ws = _ws;
    _ws = null;
    if (ws != null) unawaited(ws.close());
  }
}
