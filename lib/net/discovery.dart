// Поиск столов в локальной сети через Bonjour / mDNS (пакет bonsoir).
// Если поиск не работает (например, роутер режет multicast), всегда остаётся
// подключение по IP-адресу.

import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import 'protocol.dart';

class FoundTable {
  final String name;
  final String address;
  FoundTable(this.name, this.address);
}

class TableAdvertiser {
  BonsoirBroadcast? _b;

  Future<void> start(String hostName, List<String> ips) async {
    try {
      final service = BonsoirService(
        name: 'Стол: $hostName',
        type: kServiceType,
        port: kPort,
        attributes: {
          'v': '$kProtocolVersion',
          if (ips.isNotEmpty) 'ip': ips.first,
        },
      );
      final b = BonsoirBroadcast(service: service);
      _b = b;
      await b.initialize();
      await b.start();
    } catch (e) {
      debugPrint('Не удалось объявить стол: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _b?.stop();
    } catch (_) {}
    _b = null;
  }
}

class TableFinder extends ChangeNotifier {
  BonsoirDiscovery? _d;
  StreamSubscription? _sub;
  final Map<String, FoundTable> _tables = {};
  String? error;
  bool _stopped = false; // stop()/dispose() мог прийти, пока идёт initialize()

  List<FoundTable> get tables => _tables.values.toList();

  Future<void> start() async {
    try {
      final d = BonsoirDiscovery(type: kServiceType);
      _d = d;
      await d.initialize();
      if (_stopped) {
        try {
          await d.stop();
        } catch (_) {}
        return;
      }
      _sub = d.eventStream?.listen((event) {
        if (_stopped) return;
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            // resolveService возвращает Future: ошибку платформы гасим, иначе она уйдёт в зону как необработанная
            Future.sync(() => d.serviceResolver.resolveService(event.service)).catchError((_) {});
            break;
          case BonsoirDiscoveryServiceResolvedEvent():
            _add(event.service);
            break;
          case BonsoirDiscoveryServiceUpdatedEvent():
            _add(event.service);
            break;
          case BonsoirDiscoveryServiceLostEvent():
            if (_tables.remove(event.service.name) != null) notifyListeners();
            break;
          default:
            break;
        }
      }, onError: (Object e) {
        // платформа сообщает об ошибках поиска через поток событий
        if (_stopped) return;
        error = 'Автопоиск недоступен: $e';
        notifyListeners();
      });
      await d.start();
    } catch (e) {
      if (_stopped) return;
      error = 'Автопоиск недоступен: $e';
      notifyListeners();
    }
  }

  void _add(BonsoirService s) {
    // Сначала IP из атрибутов, затем любой IPv4 из разрешённых адресов.
    final fromAttr = s.attributes['ip'] ?? '';
    final v4 = s.hostAddresses.where((a) => isPrivateIp(a)).toList();
    final addr = fromAttr.isNotEmpty ? fromAttr : (v4.isNotEmpty ? v4.first : (s.hostAddress ?? ''));
    if (addr.isEmpty) return;
    _tables[s.name] = FoundTable(s.name, addr);
    notifyListeners();
  }

  Future<void> stop() async {
    _stopped = true;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    final d = _d;
    _d = null;
    try {
      await d?.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
