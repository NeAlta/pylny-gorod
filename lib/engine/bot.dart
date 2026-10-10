// Бот «Пыльного города». Видит только то же, что живой игрок: свой вид стола
// (Game.viewFor) и текущий запрос. Решает по роли:
//  • шериф и помощники бьют тех, кто нападал на шерифа;
//  • бандиты охотятся на шерифа и не трогают тех, кто сам в него стреляет;
//  • одиночка помогает закону, пока в живых больше двоих, а в конце идёт на шерифа.

import 'dart:math';

import 'cards.dart';
import 'characters.dart';
import 'game.dart';

class BotBrain {
  final Json v;
  final Json req;
  final Random rng;
  BotBrain(this.v, this.req, this.rng);

  /// Ответ бота на запрос. При любой неожиданности — безопасный ответ по умолчанию.
  static Json decide(Json view, Json req, [Random? rng]) {
    try {
      final b = BotBrain(view, req, rng ?? Random());
      return req['type'] == 'turn' ? b._turn() : b._choose();
    } catch (_) {
      return Game.defaultResponse(req);
    }
  }

  // ------------------------------------------------------------------
  // Что бот знает о столе
  // ------------------------------------------------------------------

  int get me => v['me'] as int;
  List<Map> get _players => (v['players'] as List).cast<Map>();
  Map _p(int id) => _players.firstWhere((p) => p['id'] == id);
  Map get _mine => _p(me);
  Role? _role(Map p) => p['role'] == null ? null : Role.values[p['role'] as int];
  Role get _myRole => _role(_mine)!;
  int get _hp => _mine['hp'] as int;
  int get _maxHp => _mine['maxHp'] as int;
  List<Map> get _hand => (v['hand'] as List).cast<Map>();
  int get _sheriff => _players.firstWhere((p) => p['role'] == Role.sheriff.index)['id'] as int;
  int get _aliveCount => _players.where((p) => p['alive'] == true).length;
  bool _has(Ab a) => characterDefs[_mine['ch']]?.ab == a;

  int _aggr(int a, int t) {
    for (final e in (v['aggr'] as List?) ?? const []) {
      final l = e as List;
      if (l[0] == a && l[1] == t) return l[2] as int;
    }
    return 0;
  }

  /// > 0 — враг, < 0 — союзник.
  double score(int id) {
    if (id == me) return -100;
    final p = _p(id);
    if (p['alive'] != true) return 0;
    final r = _role(p);
    final s = _sheriff;
    double x = 0;
    switch (_myRole) {
      case Role.outlaw:
        if (r == Role.sheriff) return 100;
        x = 1 - 3.0 * _aggr(id, s) - 1.0 * _aggr(s, id) + 3.0 * _aggr(id, me);
        break;
      case Role.sheriff:
        x = 0.6 + 4.0 * _aggr(id, me) + 0.5 * _aggr(me, id);
        break;
      case Role.deputy:
        if (r == Role.sheriff) return -100;
        x = 0.3 + 4.0 * _aggr(id, s) + 2.0 * _aggr(id, me) + 1.0 * _aggr(s, id);
        break;
      case Role.renegade:
        if (r == Role.sheriff) return _aliveCount <= 2 ? 100 : -30;
        x = 0.8 + 3.0 * _aggr(id, s) + 2.0 * _aggr(id, me);
        break;
    }
    if (x > 0 && p['hp'] == 1) x += 0.5; // добить раненого
    return x;
  }

  int? _best(List<int>? targets, {double min = 0.2}) {
    if (targets == null || targets.isEmpty) return null;
    int? best;
    var bestScore = min;
    for (final t in targets) {
      final sc = score(t) + rng.nextDouble() * 0.1;
      if (sc > bestScore) {
        bestScore = sc;
        best = t;
      }
    }
    return best;
  }

  static const _baseValue = {
    'promah': 8, 'nyrok': 9, 'vystrel': 7, 'nastoyka': 7, 'viski': 7, 'ukrytie': 8, //
    'skakun': 7, 'taynik': 7, 'truba': 6, 'binokl': 6, 'tyurma': 6, 'dinamit': 2,
    'karmannik': 6, 'pogrom': 5, 'duel': 5, 'pulemet': 6, 'nabeg': 6, 'kabak': 4,
    'dilizhans': 6, 'seyf': 7, 'yarmarka': 4, 'draka': 4, 'udar': 6, 'regtaym': 4,
    'ruzhyo': 5, 'tekila': 4, 'skorostrel': 5, 'revolver': 4, 'karabin': 5, 'dlinnostvol': 6,
    'dalnoboy': 6, 'plastina': 6, 'bibliya': 7, 'shlyapa': 6, 'sombrero': 6, 'flyazhka': 5,
    'derrindzher': 5, 'gaubitsa': 6, 'perechnitsa': 5, 'bizonya': 6, 'nozh': 5, 'furgon': 5,
    'kankan': 5, 'poni': 6,
  };

  int _value(String? k) {
    if (k == null) return 3;
    var x = _baseValue[k] ?? 4;
    if ((k == 'nastoyka' || k == 'viski') && _hp <= 2) x += 3;
    return x;
  }

  String? _optKey(Map o) => (o['card'] as Map?)?['k'] as String?;

  bool _isShotLike(String k) {
    final d = cardDefs[k]!;
    return k == 'vystrel' || (_has(Ab.swapShotMissed) && d.color == CardColor.brown && d.isMissedLike);
  }

  int get _shotsInHand => _hand.where((c) => _isShotLike(c['k'] as String)).length;
  int get _missesInHand =>
      _hand.where((c) => cardDefs[c['k']]!.isMissedLike && cardDefs[c['k']]!.color == CardColor.brown).length;

  // ------------------------------------------------------------------
  // Ход
  // ------------------------------------------------------------------

  Map<int, List<int>?> _targetsMap(Object? list) {
    final m = <int, List<int>?>{};
    for (final e in (list as List?) ?? const []) {
      final t = (e as Map)['targets'];
      m[e['card'] as int] = t == null ? null : (t as List).cast<int>();
    }
    return m;
  }

  Json _turn() {
    final plays = _targetsMap(req['plays']);
    final acts = _targetsMap(req['acts']);
    final abil = <String, List<int>?>{
      for (final a in (req['abilities'] as List? ?? const []))
        (a as Map)['id'] as String: (a['targets'] as List?)?.cast<int>()
    };
    final handKeys = {for (final c in _hand) c['id'] as int: c['k'] as String};
    final tableKeys = {for (final c in (_mine['table'] as List)) (c as Map)['id'] as int: c['k'] as String};
    final hurt = _hp < _maxHp;
    final myRange = v['myRange'] as int? ?? 1;

    Json play(int id, [int? t]) => {'action': 'play', 'card': id, if (t != null) 'target': t};
    Json act(int id, [int? t]) => {'action': 'act', 'card': id, if (t != null) 'target': t};
    CardDef dh(int id) => cardDefs[handKeys[id]]!;
    CardDef dt(int id) => cardDefs[tableKeys[id]]!;

    // 1. Лечение
    for (final e in plays.entries) {
      final d = dh(e.key);
      if (d.color != CardColor.brown) continue;
      if (d.eff == Eff.heal && hurt && (_hp <= 2 || _hand.length > _hp)) return play(e.key);
      if (d.eff == Eff.healAny && e.value != null) {
        if (hurt && e.value!.contains(me)) return play(e.key, me);
        final friend = e.value!.where((t) => t != me && score(t) < 0).toList();
        if (friend.isNotEmpty) return play(e.key, friend.first);
      }
      if (d.eff == Eff.healAll && hurt) return play(e.key);
    }
    for (final e in acts.entries) {
      if (dt(e.key).eff == Eff.heal && hurt) return act(e.key);
    }

    // 2. Снаряжение
    for (final e in plays.entries) {
      final d = dh(e.key);
      if (d.color == CardColor.blue) {
        switch (d.eff) {
          case Eff.weapon:
            if (d.value > myRange || (d.key == 'skorostrel' && myRange <= 1 && _shotsInHand >= 2)) {
              return play(e.key);
            }
            break;
          case Eff.horse:
          case Eff.scope:
          case Eff.barrel:
            return play(e.key);
          case Eff.jail:
            final t = _best(e.value, min: 0.5);
            if (t != null) return play(e.key, t);
            break;
          case Eff.dynamite:
            if (rng.nextDouble() < 0.4) return play(e.key);
            break;
          default:
            break;
        }
      } else if (d.color == CardColor.green) {
        return play(e.key);
      }
    }

    // 3. Добор карт
    for (final e in plays.entries) {
      final d = dh(e.key);
      if (d.color == CardColor.brown && (d.eff == Eff.draw || d.eff == Eff.store)) return play(e.key);
    }
    for (final e in acts.entries) {
      if (dt(e.key).eff == Eff.draw) return act(e.key);
    }

    // 4. Отнять или сбросить карту врага
    for (final e in plays.entries) {
      final d = dh(e.key);
      if (d.color == CardColor.brown && (d.eff == Eff.steal || d.eff == Eff.discardTarget)) {
        final t = _best(e.value);
        if (t != null) return play(e.key, t);
      }
    }
    for (final e in acts.entries) {
      final d = dt(e.key);
      if (d.eff == Eff.steal || d.eff == Eff.discardTarget) {
        final t = _best(e.value);
        if (t != null) return act(e.key, t);
      }
    }

    // 5. Удар по всем
    if (_areaOk()) {
      for (final e in plays.entries) {
        final d = dh(e.key);
        if (d.color == CardColor.brown && (d.eff == Eff.gatling || d.eff == Eff.indians || d.eff == Eff.brawl)) {
          return play(e.key);
        }
      }
      for (final e in acts.entries) {
        if (dt(e.key).eff == Eff.gatling) return act(e.key);
      }
    }

    // 6. Дуэль
    if (_shotsInHand >= 1) {
      for (final e in plays.entries) {
        if (dh(e.key).eff == Eff.duel) {
          final t = _best(e.value, min: 0.5);
          if (t != null) return play(e.key, t);
        }
      }
    }

    // 7. Выстрелы: сначала те, что не тратят лимит
    final shotPlays = plays.entries.where((e) {
      final d = dh(e.key);
      if (d.color != CardColor.brown) return false;
      if (d.eff == Eff.shot) return true;
      // Мэгги стреляет «Промахом», только если промахов в запасе больше одного
      return d.isMissedLike && _missesInHand > 1;
    }).toList()
      ..sort((a, b) => (dh(a.key).countsBang ? 1 : 0) - (dh(b.key).countsBang ? 1 : 0));
    for (final e in acts.entries) {
      if (dt(e.key).eff == Eff.shot) {
        final t = _best(e.value);
        if (t != null) return act(e.key, t);
      }
    }
    for (final e in shotPlays) {
      final t = _best(e.value);
      if (t != null) return play(e.key, t);
    }

    // 8. Способности персонажа
    if (abil.containsKey('silas') && hurt) return {'action': 'ability', 'id': 'silas'};
    if (abil.containsKey('jose')) return {'action': 'ability', 'id': 'jose'};
    if (abil.containsKey('chuck') && _hp >= 3 && _hand.length <= 3) return {'action': 'ability', 'id': 'chuck'};
    if (abil.containsKey('doc') && _hand.length >= 4) {
      final t = _best(abil['doc']);
      if (t != null) return {'action': 'ability', 'id': 'doc', 'target': t};
    }

    return {'action': 'end'};
  }

  /// Стоит ли бить по всем: врагов не меньше, чем союзников, и союзники не при смерти.
  bool _areaOk() {
    var enemies = 0, friends = 0;
    for (final p in _players) {
      final id = p['id'] as int;
      if (p['alive'] != true || id == me) continue;
      final sc = score(id);
      if (sc > 0.5) {
        enemies++;
      } else if (sc < 0) {
        friends++;
        if ((p['hp'] as int) <= 1) return false;
        // помощник и одиночка берегут шерифа: не задевают его площадной атакой,
        // пока он не в полном здравии и враги не в явном большинстве
        if ((_myRole == Role.deputy || _myRole == Role.renegade) &&
            _role(p) == Role.sheriff &&
            (p['hp'] as int) < 3) {
          return false;
        }
      }
    }
    return enemies > 0 && enemies >= friends;
  }

  // ------------------------------------------------------------------
  // Выборы
  // ------------------------------------------------------------------

  Json _choose() {
    final kind = req['kind'] as String? ?? 'other';
    final opts = (req['options'] as List).cast<Map>();
    final minN = req['min'] as int;
    final maxN = req['max'] as int;
    final ctx = (req['ctx'] as Map?) ?? const {};
    String id(Map o) => o['id'] as String;
    List<String> byValue({required bool high, required int n}) {
      final sorted = List.of(opts)
        ..sort((a, b) => _value(_optKey(high ? b : a)) - _value(_optKey(high ? a : b)));
      return sorted.take(n).map(id).toList();
    }

    List<String> ch;
    switch (kind) {
      case 'character':
        final sorted = List.of(opts)..shuffle(rng);
        sorted.sort((a, b) => (characterDefs[b['char']]?.hp ?? 0) - (characterDefs[a['char']]?.hp ?? 0));
        ch = [id(sorted.first)];
        break;
      case 'miss':
        // промахов не хватит (Слэйд требует 2) — не тратим карты зря
        if (opts.length < ((ctx['need'] as int?) ?? 1)) {
          ch = const [];
          break;
        }
        final green = opts.where((o) => id(o).startsWith('g')).toList();
        ch = green.isNotEmpty ? [id(green.first)] : byValue(high: false, n: 1);
        break;
      case 'indians':
      case 'duel':
        // союзник при последней жизни вызвал на дуэль — уступаем, чтобы его не убить
        final from = ctx['from'] as int?;
        if (kind == 'duel' && from != null && score(from) < 0 && _p(from)['hp'] == 1 && _hp > 1) {
          ch = const [];
          break;
        }
        ch = byValue(high: false, n: 1);
        break;
      case 'dying':
        ch = [id(opts.first)];
        break;
      case 'pick':
        ch = byValue(high: true, n: max(minN, 1));
        break;
      case 'discard':
        ch = byValue(high: false, n: minN);
        break;
      case 'take':
        ch = [_chooseTake(opts, ctx)];
        break;
      case 'check':
        ch = [_chooseCheck(opts, '${ctx['reason'] ?? ''}')];
        break;
      case 'firstSource':
        ch = [_chooseFirstSource(opts)];
        break;
      case 'takeInPlay':
        ch = [_chooseTakeInPlay(opts, (ctx['owners'] as Map?) ?? const {})];
        break;
      default:
        ch = opts.take(minN).map(id).toList();
    }
    if (ch.length < minN || ch.length > maxN) ch = opts.take(minN).map(id).toList();
    return {'choice': ch};
  }

  String _chooseTake(List<Map> opts, Map ctx) {
    final target = ctx['target'] as int?;
    final enemy = target == null || score(target) > 0;
    String? best;
    var bestVal = -1000;
    for (final o in opts) {
      final k = _optKey(o);
      int val;
      if (o['id'] == 'hand') {
        val = enemy ? 5 : 1;
      } else if (k == 'tyurma' || k == 'dinamit') {
        val = enemy ? -5 : 20; // союзника освобождаем от тюрьмы и динамита
      } else {
        val = enemy ? _value(k) + 1 : -_value(k);
      }
      if (val > bestVal) {
        bestVal = val;
        best = o['id'] as String;
      }
    }
    return best!;
  }

  String _chooseCheck(List<Map> opts, String reason) {
    bool good(Map o) {
      final c = o['card'] as Map;
      final suit = Suit.values[c['s'] as int];
      final rank = c['r'] as int;
      if (reason.contains('динамит')) return !(suit == Suit.spades && rank >= 2 && rank <= 9);
      return suit == Suit.hearts;
    }

    for (final o in opts) {
      if (good(o)) return o['id'] as String;
    }
    return opts.first['id'] as String;
  }

  String _chooseFirstSource(List<Map> opts) {
    for (final o in opts) {
      if ((o['id'] as String).startsWith('c') && _value(_optKey(o)) >= 7) return o['id'] as String;
    }
    String? best;
    var bestScore = 0.2;
    for (final o in opts) {
      final id = o['id'] as String;
      if (!id.startsWith('p')) continue;
      final sc = score(int.parse(id.substring(1)));
      if (sc > bestScore) {
        bestScore = sc;
        best = id;
      }
    }
    return best ?? 'deck';
  }

  String _chooseTakeInPlay(List<Map> opts, Map owners) {
    String best = 'deck';
    var bestVal = 5;
    for (final o in opts) {
      final id = o['id'] as String;
      final owner = owners[id] as int?;
      if (owner == null) continue;
      final k = _optKey(o);
      final enemy = score(owner) > 0;
      int val;
      if (k == 'tyurma' || k == 'dinamit') {
        val = enemy ? -5 : 7;
      } else {
        val = enemy ? _value(k) : -1;
      }
      if (val > bestVal) {
        bestVal = val;
        best = id;
      }
    }
    return best;
  }
}
