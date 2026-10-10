// Простой протокол: JSON-сообщения по TCP, по одному на строку.
//
// клиент → хост: hello {name, token, v}, resp {rid, data}, ping, bye
// хост → клиент: welcome {id}, lobby {...}, state {s}, req {r}, reject {reason},
//                reset, closed, ping

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../engine/game.dart' show Json;

const int kPort = 47321;
const int kProtocolVersion = 1;
const String kServiceType = '_pylgorod._tcp';

class LineConn {
  final Socket socket;
  late final StreamSubscription<String> _sub;
  DateTime lastSeen = DateTime.now();
  bool closed = false;
  final void Function() _onDone;

  LineConn(this.socket, {required void Function(Json) onMessage, required void Function() onDone})
      : _onDone = onDone {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    socket.done.then((_) {}, onError: (Object _) {});
    _sub = socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        lastSeen = DateTime.now();
        if (line.isEmpty) return;
        try {
          final m = jsonDecode(line);
          if (m is Map<String, dynamic>) onMessage(m);
        } catch (_) {
          // повреждённое сообщение — пропускаем
        }
      },
      onDone: _finish,
      onError: (_) => _finish(),
      cancelOnError: true,
    );
  }

  String get remote {
    try {
      return socket.remoteAddress.address;
    } catch (_) {
      return '?';
    }
  }

  void send(Json m) {
    if (closed) return;
    try {
      socket.write('${jsonEncode(m)}\n');
    } catch (_) {
      _finish();
    }
  }

  void _finish() {
    if (closed) return;
    closed = true;
    _sub.cancel();
    socket.destroy();
    _onDone();
  }

  /// Закрыть без вызова onDone.
  void close() {
    if (closed) return;
    closed = true;
    _sub.cancel();
    socket.destroy();
  }
}

/// IPv4-адреса телефона в локальной сети (Wi-Fi или точка доступа).
Future<List<String>> localAddresses() async {
  try {
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    final out = <String>[];
    for (final i in ifs) {
      for (final a in i.addresses) {
        if (isPrivateIp(a.address)) out.add(a.address);
      }
    }
    // Wi-Fi обычно 192.168.x.x — показываем его первым
    out.sort((a, b) => (b.startsWith('192.168') ? 1 : 0) - (a.startsWith('192.168') ? 1 : 0));
    return out;
  } catch (_) {
    return [];
  }
}

bool isPrivateIp(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.any((x) => x == null)) return false;
  final a = p[0]!, b = p[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}
