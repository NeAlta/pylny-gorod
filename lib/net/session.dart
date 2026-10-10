// Сессия игры: хост (сервер + движок) или клиент (подключение к хосту).
// Интерфейс одинаковый — экраны не знают, кто они.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../engine/bot.dart';
import '../engine/game.dart';
import 'discovery.dart';
import 'protocol.dart';

abstract class GameSession extends ChangeNotifier {
  int? myId;

  /// {players: [{id, name, connected}], expansion, host}
  Json? lobby;

  /// Состояние партии глазами этого игрока (Game.viewFor) или null, если идёт лобби.
  Json? state;

  /// Текущий запрос к этому игроку (ход или выбор) или null.
  Json? request;

  /// Временное сообщение (переподключение и т.п.).
  String? status;

  /// Сессия завершена с этой причиной — нужно вернуться в меню.
  String? fatal;

  bool get isHost;
  void respond(Json data);
  Future<void> close();

  bool _disposed = false;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ==========================================================================
// Хост
// ==========================================================================

class _Seat {
  final int id;
  final String name;
  final String token;
  LineConn? conn;
  bool auto = false; // отвечаем за игрока автоматически, пока он не вернётся
  final bool bot;
  _Seat(this.id, this.name, this.token, {this.bot = false});
}

class HostSession extends GameSession {
  final String myName;
  HostSession(this.myName);

  @override
  bool get isHost => true;

  ServerSocket? _server;
  Timer? _pingTimer;
  final TableAdvertiser _adv = TableAdvertiser();
  final List<_Seat> _seats = [];
  int _nextId = 1;
  bool expansion = false;
  Game? _game;
  final Map<int, Completer<Json>> _pending = {};
  final Map<int, Json> _pendingReq = {};
  final Map<int, Timer> _autoTimers = {};
  bool _flushScheduled = false;
  bool _closed = false;
  List<String> addresses = [];
  final Random _rng = Random();

  static const _autoDelay = Duration(seconds: 40);

  int get playerCount => _seats.length;
  int get maxPlayers => expansion ? 8 : 7;
  bool get canStart => _game == null && playerCount >= 4 && playerCount <= maxPlayers;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, kPort);
    _server!.listen(_onSocket, onError: (_) {});
    myId = 0;
    _seats.add(_Seat(0, myName, ''));
    addresses = await localAddresses();
    await _adv.start(myName, addresses);
    _pingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _ping());
    _broadcastLobby();
  }

  bool _connected(_Seat s) => s.id == 0 || s.bot || s.conn != null;
  _Seat? _seat(int id) {
    for (final s in _seats) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _onSocket(Socket socket) {
    if (_closed) {
      socket.destroy();
      return;
    }
    _Seat? seat;
    late final LineConn c;
    c = LineConn(socket, onMessage: (m) {
      final t = m['t'];
      if (t == 'ping') return;
      if (seat == null) {
        if (t == 'hello') seat = _hello(c, m);
        return;
      }
      if (t == 'resp') {
        _onResp(seat!, m);
      } else if (t == 'bye') {
        c.close();
        _onDisconnect(seat!, c);
      }
    }, onDone: () {
      if (seat != null) _onDisconnect(seat!, c);
    });
    // соединение без приветствия долго не держим
    Timer(const Duration(seconds: 10), () {
      if (seat == null) c.close();
    });
  }

  _Seat? _hello(LineConn c, Json m) {
    if (m['v'] != kProtocolVersion) {
      _reject(c, 'Версии приложения у хоста и у вас отличаются. Обновите приложение.');
      return null;
    }
    final token = '${m['token'] ?? ''}';
    var name = '${m['name'] ?? ''}'.trim();
    if (name.isEmpty) name = 'Игрок';
    if (name.length > 16) name = name.substring(0, 16);

    // переподключение
    for (final s in _seats) {
      if (s.id != 0 && token.isNotEmpty && s.token == token) {
        final old = s.conn;
        s.conn = c;
        old?.close();
        s.auto = false;
        _autoTimers.remove(s.id)?.cancel();
        c.send({'t': 'welcome', 'id': s.id});
        c.send(_lobbyMsg());
        if (_game != null) {
          c.send({'t': 'state', 's': _viewFor(s.id)});
          final req = _pendingReq[s.id];
          if (req != null) c.send({'t': 'req', 'r': req});
        }
        _broadcastLobby();
        _scheduleFlush();
        return s;
      }
    }
    if (_game != null) {
      _reject(c, 'Партия уже идёт. Дождитесь следующей.');
      return null;
    }
    if (_seats.length >= 8) {
      _reject(c, 'За столом нет мест.');
      return null;
    }
    // одинаковые имена различаем номером
    final names = _seats.map((s) => s.name).toSet();
    var unique = name;
    for (var i = 2; names.contains(unique); i++) {
      unique = '$name $i';
    }
    final s = _Seat(_nextId++, unique, token);
    s.conn = c;
    _seats.add(s);
    // клиент мог вернуться после newRound со старым состоянием прошлой партии
    c.send({'t': 'reset'});
    c.send({'t': 'welcome', 'id': s.id});
    _broadcastLobby();
    return s;
  }

  void _reject(LineConn c, String reason) {
    c.send({'t': 'reject', 'reason': reason});
    Future.delayed(const Duration(milliseconds: 300), c.close);
  }

  void _onDisconnect(_Seat s, LineConn c) {
    if (s.conn != c) return; // устаревшее соединение
    s.conn = null;
    if (_game == null) {
      _seats.remove(s);
    } else if (_pendingReq.containsKey(s.id)) {
      _startAuto(s.id);
    }
    _broadcastLobby();
    _scheduleFlush();
  }

  void _ping() {
    final now = DateTime.now();
    for (final s in List.of(_seats)) {
      final c = s.conn;
      if (c == null) continue;
      if (now.difference(c.lastSeen) > const Duration(seconds: 15)) {
        c.close();
        _onDisconnect(s, c);
      } else {
        c.send({'t': 'ping'});
      }
    }
  }

  // ---------- лобби ----------

  Json _lobbyMsg() => {
        't': 'lobby',
        'host': myName,
        'expansion': expansion,
        'players': [
          for (final s in _seats) {'id': s.id, 'name': s.name, 'connected': _connected(s), 'bot': s.bot}
        ],
      };

  void _broadcastLobby() {
    final m = _lobbyMsg();
    for (final s in _seats) {
      s.conn?.send(m);
    }
    lobby = m;
    changed();
  }

  static const _botNames = [
    'Бот Джанго', 'Бот Кактус', 'Бот Шпора', 'Бот Мустанг', //
    'Бот Койот', 'Бот Пончо', 'Бот Сорока', 'Бот Перекати-поле',
  ];

  bool get canAddBot => _game == null && _seats.length < maxPlayers;

  void addBot() {
    if (!canAddBot) return;
    final used = _seats.map((s) => s.name).toSet();
    final name = _botNames.firstWhere((n) => !used.contains(n), orElse: () => 'Бот $_nextId');
    _seats.add(_Seat(_nextId++, name, '', bot: true));
    _broadcastLobby();
  }

  void removeBot(int id) {
    if (_game != null) return;
    _seats.removeWhere((s) => s.id == id && s.bot);
    _broadcastLobby();
  }

  /// Решение бота — по тому же виду стола, что видел бы игрок на этом месте.
  Json _botAnswer(int pid, Json req) => BotBrain.decide(_game!.viewFor(pid), req, _rng);

  void setExpansion(bool v) {
    if (_game != null) return;
    expansion = v;
    _broadcastLobby();
  }

  // ---------- партия ----------

  void startGame() {
    if (!canStart) return;
    final order = List.of(_seats)..shuffle(Random());
    final players = [for (final s in order) Player(s.id, s.name)];
    final g = Game(players: players, expansion: expansion, ask: _ask, onChange: _scheduleFlush);
    _game = g;
    g.run().then((_) => _flush()).catchError((Object e, StackTrace st) {
      debugPrint('Ошибка движка: $e\n$st');
      status = 'Внутренняя ошибка игры: $e';
      _flush();
    });
  }

  /// Есть ли игроки (кроме хоста), от которых ждём ответа.
  bool get canForceSkip => _game != null && _game!.result == null && _pendingReq.keys.any((id) => id != 0);

  /// Хост пропускает ход/ответ за тех, кто долго не отвечает.
  void forceSkip() {
    for (final id in _pendingReq.keys.where((id) => id != 0).toList()) {
      final req = _pendingReq[id];
      if (req != null) _complete(id, _botAnswer(id, req));
    }
  }

  /// После окончания партии — вернуться в лобби с теми же игроками.
  void newRound() {
    if (_game == null || _game!.result == null) return;
    for (final t in _autoTimers.values) {
      t.cancel();
    }
    _autoTimers.clear();
    _pending.clear();
    _pendingReq.clear();
    _game = null;
    state = null;
    request = null;
    status = null;
    _seats.removeWhere((s) => !_connected(s));
    for (final s in _seats) {
      s.auto = false;
      s.conn?.send({'t': 'reset'});
    }
    _broadcastLobby();
  }

  Future<Json> _ask(int pid, Json req) {
    final comp = Completer<Json>();
    _pending[pid] = comp;
    _pendingReq[pid] = req;
    if (pid == 0) {
      request = req;
      changed();
    } else {
      final s = _seat(pid);
      if (s != null && s.bot) {
        // бот «думает» чуть меньше секунды, чтобы за его ходами можно было следить
        final ms = req['type'] == 'turn' ? 700 + _rng.nextInt(600) : 450 + _rng.nextInt(500);
        _autoTimers[pid] = Timer(Duration(milliseconds: ms), () {
          if (_closed || _pendingReq[pid] != req) return;
          _complete(pid, _botAnswer(pid, req));
        });
      } else if (s != null && s.conn != null && !s.auto) {
        s.conn!.send({'t': 'req', 'r': req});
      } else {
        _startAuto(pid);
      }
    }
    return comp.future;
  }

  void _complete(int pid, Json data) {
    final comp = _pending.remove(pid);
    _pendingReq.remove(pid);
    _autoTimers.remove(pid)?.cancel();
    if (pid == 0) request = null;
    comp?.complete(data);
  }

  void _startAuto(int pid) {
    _autoTimers.remove(pid)?.cancel();
    if (_closed) return; // иначе после выхода хоста движок продолжает играть сам с собой
    final s = _seat(pid);
    final delay = (s?.auto ?? false) ? const Duration(seconds: 2) : _autoDelay;
    _autoTimers[pid] = Timer(delay, () {
      final req = _pendingReq[pid];
      final seat = _seat(pid);
      if (req == null || seat == null || seat.conn != null) return;
      seat.auto = true;
      _complete(pid, _botAnswer(pid, req)); // за отключившегося играет бот
    });
  }

  void _onResp(_Seat s, Json m) {
    final req = _pendingReq[s.id];
    final data = m['data'];
    if (req == null || m['rid'] != req['rid'] || data is! Map) return;
    _complete(s.id, Map<String, dynamic>.from(data));
  }

  @override
  void respond(Json data) {
    if (_pendingReq.containsKey(0)) {
      _complete(0, data);
      changed();
    }
  }

  Json _viewFor(int id) {
    final v = _game!.viewFor(id);
    v['offline'] = [
      for (final s in _seats)
        if (!_connected(s)) s.id
    ];
    v['bots'] = [
      for (final s in _seats)
        if (s.bot) s.id
    ];
    return v;
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    final g = _game;
    if (g == null) return;
    for (final s in _seats) {
      if (s.id == 0) {
        state = _viewFor(0);
      } else {
        s.conn?.send({'t': 'state', 's': _viewFor(s.id)});
      }
    }
    changed();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pingTimer?.cancel();
    for (final t in _autoTimers.values) {
      t.cancel();
    }
    _autoTimers.clear();
    for (final s in _seats) {
      s.conn?.send({'t': 'closed'});
    }
    await Future.delayed(const Duration(milliseconds: 200));
    for (final s in _seats) {
      s.conn?.close();
    }
    await _adv.stop();
    await _server?.close();
  }
}

// ==========================================================================
// Клиент
// ==========================================================================

class ClientSession extends GameSession {
  final String address;
  final String myName;
  final String token;
  ClientSession({required this.address, required this.myName, required this.token});

  @override
  bool get isHost => false;

  LineConn? _conn;
  Timer? _pingTimer;
  bool _closed = false;
  bool _reconnecting = false;

  /// Первое подключение. Бросает исключение, если хост недоступен.
  Future<void> connect() async {
    if (!await _open()) {
      throw const SocketException('Не удалось подключиться');
    }
    _pingTimer = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
  }

  Future<bool> _open() async {
    try {
      final s = await Socket.connect(address, kPort, timeout: const Duration(seconds: 5));
      if (_closed) {
        // пользователь вышел, пока шло подключение
        s.destroy();
        return false;
      }
      final c = LineConn(s, onMessage: _onMsg, onDone: _onLost);
      _conn = c;
      c.send({'t': 'hello', 'name': myName, 'token': token, 'v': kProtocolVersion});
      return true;
    } catch (_) {
      return false;
    }
  }

  void _tick() {
    final c = _conn;
    if (c == null) return;
    if (DateTime.now().difference(c.lastSeen) > const Duration(seconds: 15)) {
      c.close();
      _onLost();
    } else {
      c.send({'t': 'ping'});
    }
  }

  void _onMsg(Json m) {
    switch (m['t']) {
      case 'welcome':
        myId = m['id'] as int?;
        status = null;
        // хост сразу после welcome пришлёт актуальный запрос, если он ещё ждёт ответа;
        // старый (уже отвеченный автоматически) запрос показывать нельзя
        request = null;
        break;
      case 'lobby':
        lobby = m;
        break;
      case 'state':
        state = Map<String, dynamic>.from(m['s'] as Map);
        break;
      case 'req':
        request = Map<String, dynamic>.from(m['r'] as Map);
        break;
      case 'reset':
        state = null;
        request = null;
        break;
      case 'reject':
        fatal = '${m['reason']}';
        _shutdown();
        break;
      case 'closed':
        fatal = 'Хост закрыл стол.';
        _shutdown();
        break;
      default:
        return;
    }
    changed();
  }

  void _onLost() {
    _conn = null;
    if (_closed) return;
    status = 'Связь с хостом потеряна. Переподключаюсь…';
    changed();
    _reconnect();
  }

  Future<void> _reconnect() async {
    if (_reconnecting) return;
    _reconnecting = true;
    for (var i = 0; i < 45 && !_closed; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (_closed) break;
      if (await _open()) {
        _reconnecting = false;
        return;
      }
    }
    _reconnecting = false;
    if (!_closed) {
      fatal = 'Не удаётся связаться с хостом.';
      _shutdown();
      changed();
    }
  }

  @override
  void respond(Json data) {
    final req = request;
    if (req == null) return;
    _conn?.send({'t': 'resp', 'rid': req['rid'], 'data': data});
    request = null;
    changed();
  }

  void _shutdown() {
    _closed = true;
    _pingTimer?.cancel();
    _conn?.close();
    _conn = null;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _conn?.send({'t': 'bye'});
    _closed = true; // сразу: иначе обрыв за эти 100 мс запустит переподключение
    _pingTimer?.cancel();
    await Future.delayed(const Duration(milliseconds: 100));
    _shutdown();
  }
}
