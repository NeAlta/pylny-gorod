// Игровой движок «Пыльного города».
//
// Движок работает только на телефоне хоста. Всё, что требует решения игрока,
// идёт через [AskFn]: движок отправляет запрос и ждёт ответа. Благодаря async/await
// логика партии читается сверху вниз, как правила.

import 'dart:math';

import 'cards.dart';
import 'characters.dart';

typedef Json = Map<String, dynamic>;
typedef AskFn = Future<Json> Function(int playerId, Json request);

class GameOver implements Exception {
  final String text;
  final List<int> winners;
  GameOver(this.text, this.winners);
  Json toJson() => {'text': text, 'winners': winners};
}

/// Текущий игрок выбыл — ход заканчивается.
class _TurnEnded implements Exception {}

class Player {
  final int id;
  final String name;
  Role role = Role.outlaw;
  CharDef? ch;
  List<CharDef> charOptions = [];
  int hp = 0;
  int maxHp = 0;
  bool alive = true;
  final List<GameCard> hand = [];
  final List<GameCard> table = [];

  Player(this.id, this.name);

  bool has(Ab a) => ch?.ab == a;
}

class Game {
  final List<Player> players;
  final bool expansion;
  final AskFn ask;
  final Random rng;
  void Function()? onChange;

  List<GameCard> deck = [];
  final List<GameCard> discard = [];
  final List<GameCard> storeCards = [];
  final List<GameCard> _held = []; // временно отложенные карты (не видны другим)
  final List<String> log = [];
  final Set<int> waitingOn = {};
  int cur = 0;
  int turnNo = 0;
  GameOver? result;
  int totalCards = 0;

  // счётчики текущего хода
  int shotsThisTurn = 0;
  bool docUsed = false;
  int joseUses = 0;

  bool _dealt = false;
  int _reqSeq = 0;

  Game({required this.players, required this.expansion, required this.ask, Random? rng, this.onChange})
      : rng = rng ?? Random() {
    if (players.length < 4 || players.length > (expansion ? 8 : 7)) {
      throw ArgumentError('Неверное число игроков: ${players.length}');
    }
  }

  // ======================================================================
  // Запуск
  // ======================================================================

  Future<GameOver> run() async {
    try {
      _setup();
      await _chooseCharacters();
      for (final p in players) {
        p.maxHp = p.ch!.hp + (p.role == Role.sheriff ? 1 : 0);
        p.hp = p.maxHp;
        _draw(p, p.hp);
      }
      _dealt = true;
      _log('Партия началась. Шериф — ${_sheriff.name}.');
      _changed();
      while (true) {
        final p = players[cur];
        if (p.alive) await _runTurn(p);
        cur = _nextAliveIndex(cur);
      }
    } on GameOver catch (g) {
      result = g;
      waitingOn.clear();
      _log('🏁 ${g.text}');
      _changed();
      return g;
    }
  }

  void _setup() {
    final roles = rolesFor(players.length)..shuffle(rng);
    for (var i = 0; i < players.length; i++) {
      players[i].role = roles[i];
    }
    cur = players.indexWhere((p) => p.role == Role.sheriff);
    final pool = allCharacters.where((c) => expansion || !c.expansion).toList()..shuffle(rng);
    for (var i = 0; i < players.length; i++) {
      players[i].charOptions = [pool[2 * i], pool[2 * i + 1]];
    }
    deck = buildDeck(expansion: expansion)..shuffle(rng);
    totalCards = deck.length;
  }

  Future<void> _chooseCharacters() async {
    await Future.wait(players.map((p) async {
      final opts = p.charOptions
          .map((c) => {
                'id': c.key,
                'label': c.name,
                'sub': '${'❤' * c.hp}  ${c.text}',
                'char': c.key,
              })
          .toList();
      final ch = await _choose(p, 'Выберите персонажа', opts,
          text: 'Ваша роль: ${p.role.title}. ${p.role.goal}', alwaysAsk: true);
      p.ch = characterDefs[ch.first];
    }));
    for (final p in players) {
      _log('${p.name} играет за ${p.ch!.name}.');
    }
  }

  // ======================================================================
  // Ход
  // ======================================================================

  Future<void> _runTurn(Player p) async {
    turnNo++;
    shotsThisTurn = 0;
    docUsed = false;
    joseUses = 0;
    _log('— Ход: ${p.name} —');
    _changed();
    try {
      final dyn = _inPlay(p, 'dinamit');
      if (dyn != null) {
        final c = await _check(p, 'динамит');
        p.table.remove(dyn);
        if (c != null && c.suit == Suit.spades && c.rank >= 2 && c.rank <= 9) {
          discard.add(dyn);
          _log('💥 Динамит взрывается у ${p.name}!');
          await _damage(p, 3, null);
        } else {
          final nx = players[_nextAliveIndex(cur)];
          nx.table.add(dyn);
          _log('Динамит переходит к ${nx.name}.');
        }
        _changed();
      }
      final jail = _inPlay(p, 'tyurma');
      if (jail != null) {
        final c = await _check(p, 'тюрьма');
        p.table.remove(jail);
        discard.add(jail);
        if (c != null && c.suit != Suit.hearts) {
          _log('${p.name} остаётся в тюрьме и пропускает ход.');
          _changed();
          return;
        }
        _log('${p.name} выходит из тюрьмы.');
      }
      await _drawPhase(p);
      await _playPhase(p);
      await _discardPhase(p);
    } on _TurnEnded {
      // текущий игрок выбыл
    }
  }

  Future<void> _drawPhase(Player p) async {
    if (p.has(Ab.takeInPlay)) {
      final opts = <Json>[
        {'id': 'deck', 'label': 'Обычный добор: 2 карты из колоды'}
      ];
      for (final o in _alive()) {
        if (o == p) continue;
        for (final c in o.table) {
          opts.add(_cardOpt(c, label: '${c.label} — у ${o.name}'));
        }
      }
      if (opts.length > 1) {
        final ch = await _choose(p, 'Добор', opts, text: 'Можно забрать выложенную карту вместо добора.');
        if (ch.first != 'deck') {
          final id = _cid(ch.first);
          for (final o in players) {
            final c = _findById(o.table, id);
            if (c != null) {
              o.table.remove(c);
              c.playedTurn = -1;
              p.hand.add(c);
              _log('${p.name} забирает «${c.name}» у ${o.name}.');
              _changed();
              return;
            }
          }
        }
      }
    }

    if (p.has(Ab.pickTwoOfThree)) {
      final top = <GameCard>[];
      for (var i = 0; i < 3; i++) {
        final c = _pop();
        if (c != null) top.add(c);
      }
      if (top.length <= 2) {
        p.hand.addAll(top);
      } else {
        _held.addAll(top); // карты видит только выбирающий
        final ch = await _choose(p, 'Возьмите 2 карты из 3', top.map((c) => _cardOpt(c)).toList(), min: 2, max: 2);
        _held.removeWhere(top.contains);
        for (final c in top) {
          if (ch.contains('c${c.id}')) {
            p.hand.add(c);
          } else {
            deck.add(c); // обратно наверх колоды
          }
        }
      }
      _log('${p.name} берёт 2 карты.');
    } else if (p.has(Ab.drawPerWound)) {
      final n = 1 + (p.maxHp - p.hp);
      _draw(p, n);
      _log('${p.name} берёт $n карт(ы).');
    } else if (p.has(Ab.drawThree)) {
      _draw(p, 3);
      _log('${p.name} берёт 3 карты.');
    } else {
      var firstDone = false;
      if (p.has(Ab.firstFromPlayer)) {
        final opts = <Json>[
          {'id': 'deck', 'label': 'Из колоды'}
        ];
        for (final o in _alive()) {
          if (o != p && o.hand.isNotEmpty) {
            opts.add({'id': 'p${o.id}', 'label': 'Из руки: ${o.name} (${o.hand.length})'});
          }
        }
        if (opts.length > 1) {
          final ch = await _choose(p, 'Откуда взять первую карту?', opts);
          if (ch.first != 'deck') {
            final o = _byId(int.parse(ch.first.substring(1)));
            final c = o.hand.removeAt(rng.nextInt(o.hand.length));
            p.hand.add(c);
            _log('${p.name} берёт карту из руки ${o.name}.');
            firstDone = true;
          }
        }
      } else if (p.has(Ab.firstFromDiscard) && discard.isNotEmpty) {
        final top = discard.last;
        final ch = await _choose(p, 'Откуда взять первую карту?', [
          {'id': 'deck', 'label': 'Из колоды'},
          _cardOpt(top, label: 'Из сброса: ${top.label}'),
        ]);
        if (ch.first != 'deck') {
          discard.removeLast();
          p.hand.add(top);
          _log('${p.name} берёт «${top.name}» из сброса.');
          firstDone = true;
        }
      }
      if (!firstDone) _draw(p, 1);
      final second = _pop();
      if (second != null) {
        p.hand.add(second);
        if (p.has(Ab.redBonus)) {
          _log('${p.name} показывает вторую карту: ${second.label}.');
          if (second.suit.isRed) {
            _draw(p, 1);
            _log('${p.name} берёт ещё одну карту.');
          }
        }
      }
    }
    _changed();
  }

  Future<void> _playPhase(Player p) async {
    var invalid = 0;
    while (true) {
      final plays = <int, List<int>?>{};
      for (final c in p.hand) {
        final t = _handPlay(p, c);
        if (t != null) plays[c.id] = t;
      }
      final acts = <int, List<int>?>{};
      for (final c in p.table) {
        final t = _greenPlay(p, c);
        if (t != null) acts[c.id] = t;
      }
      final abilities = _abilities(p);

      final resp = await _ask(p, {
        'type': 'turn',
        'plays': [
          for (final e in plays.entries) {'card': e.key, 'targets': e.value}
        ],
        'acts': [
          for (final e in acts.entries) {'card': e.key, 'targets': e.value}
        ],
        'abilities': [
          for (final e in abilities.entries) {'id': e.key, 'label': _abilityLabel(e.key), 'targets': e.value}
        ],
      });

      final action = resp['action'];
      if (action == 'end') return;

      final rawTarget = resp['target'];
      final target = rawTarget is int ? rawTarget : int.tryParse('${rawTarget ?? ''}');
      // null или [] — цель не нужна; иначе цель должна быть из списка
      bool okTarget(List<int>? ts) => ts == null || ts.isEmpty || (target != null && ts.contains(target));
      Player? tgt(List<int>? ts) => (ts == null || ts.isEmpty) ? null : _byId(target!);

      if (action == 'play') {
        final id = _asInt(resp['card']);
        if (id != null && plays.containsKey(id) && okTarget(plays[id])) {
          final c = _findById(p.hand, id)!;
          await _playFromHand(p, c, tgt(plays[id]));
          invalid = 0;
          _changed();
          continue;
        }
      } else if (action == 'act') {
        final id = _asInt(resp['card']);
        if (id != null && acts.containsKey(id) && okTarget(acts[id])) {
          final c = _findById(p.table, id)!;
          await _activateGreen(p, c, tgt(acts[id]));
          invalid = 0;
          _changed();
          continue;
        }
      } else if (action == 'ability') {
        final id = '${resp['id']}';
        if (abilities.containsKey(id) && okTarget(abilities[id])) {
          await _useAbility(p, id, tgt(abilities[id]));
          invalid = 0;
          _changed();
          continue;
        }
      }
      // неверный ответ: спрашиваем снова, но не бесконечно
      if (++invalid >= 5) return;
    }
  }

  Future<void> _discardPhase(Player p) async {
    final limit = p.has(Ab.bigHand) ? 10 : max(0, p.hp);
    final excess = p.hand.length - limit;
    if (excess <= 0) return;
    final ch = await _choose(p, 'Сбросьте лишние карты: $excess', p.hand.map((c) => _cardOpt(c)).toList(),
        min: excess, max: excess);
    for (final id in ch) {
      final c = _findById(p.hand, _cid(id))!;
      p.hand.remove(c);
      discard.add(c);
    }
    _log('${p.name} сбрасывает $excess карт(ы).');
    _changed();
  }

  // ======================================================================
  // Что можно сыграть
  // ======================================================================

  bool _canShootMore(Player p) =>
      p.has(Ab.unlimitedShots) || _weapon(p)?.key == 'skorostrel' || shotsThisTurn < 1;

  List<int>? _nz(Iterable<Player> ps) {
    final l = ps.map((p) => p.id).toList();
    return l.isEmpty ? null : l;
  }

  Iterable<Player> _others(Player p) => _alive().where((o) => o != p);

  bool _inReach(Player a, Player b, Reach r) {
    switch (r) {
      case Reach.weapon:
        return dist(a, b) <= range(a);
      case Reach.one:
        return dist(a, b) <= 1;
      case Reach.any:
      case Reach.none:
        return true;
    }
  }

  List<int>? _shotTargets(Player p, GameCard? c, Reach r) =>
      _nz(_others(p).where((o) => _inReach(p, o, r) && !_immune(p, o, c)));

  List<int>? _cardTargets(Player p, GameCard c, Reach r) => _nz(_others(p)
      .where((o) => _inReach(p, o, r) && !_immune(p, o, c) && (o.hand.isNotEmpty || o.table.isNotEmpty)));

  /// null — сыграть нельзя; [] — можно, цель не нужна; список — допустимые цели.
  List<int>? _handPlay(Player p, GameCard c) {
    final d = c.def;
    if (d.extraCost && p.hand.length < 2) return null;
    if (d.color == CardColor.brown && d.isMissedLike) {
      if (p.has(Ab.swapShotMissed) && _canShootMore(p)) return _shotTargets(p, c, Reach.weapon);
      return null;
    }
    if (d.color == CardColor.blue) {
      switch (d.eff) {
        case Eff.jail:
          return _nz(_others(p).where((o) => o.role != Role.sheriff && !_hasInPlay(o, 'tyurma') && !_immune(p, o, c)));
        default:
          return _hasInPlay(p, c.key) ? null : const [];
      }
    }
    if (d.color == CardColor.green) return _hasInPlay(p, c.key) ? null : const [];
    switch (d.eff) {
      case Eff.shot:
        if (d.countsBang && !_canShootMore(p)) return null;
        return _shotTargets(p, c, d.reach);
      case Eff.heal:
        if (p.hp >= p.maxHp) return null;
        if (c.key == 'nastoyka' && _alive().length <= 2) return null;
        return const [];
      case Eff.healAny:
        return _nz(_alive().where((o) => o.hp < o.maxHp));
      case Eff.healAll:
      case Eff.draw:
      case Eff.store:
      case Eff.gatling:
      case Eff.indians:
        return const [];
      case Eff.steal:
      case Eff.discardTarget:
        return _cardTargets(p, c, d.reach);
      case Eff.duel:
        return _nz(_others(p));
      case Eff.brawl:
        return _others(p).any((o) => o.hand.isNotEmpty || o.table.isNotEmpty) ? const [] : null;
      default:
        return null;
    }
  }

  List<int>? _greenPlay(Player p, GameCard c) {
    final d = c.def;
    if (d.color != CardColor.green || turnNo <= c.playedTurn) return null;
    switch (d.eff) {
      case Eff.shot:
        return _shotTargets(p, c, d.reach);
      case Eff.gatling:
      case Eff.draw:
        return const [];
      case Eff.heal:
        return p.hp < p.maxHp ? const [] : null;
      case Eff.steal:
      case Eff.discardTarget:
        return _cardTargets(p, c, d.reach);
      default:
        return null;
    }
  }

  Map<String, List<int>?> _abilities(Player p) {
    final m = <String, List<int>?>{};
    if (p.has(Ab.discardTwoHeal) && p.hand.length >= 2 && p.hp < p.maxHp) m['silas'] = null;
    if (p.has(Ab.lifeForCards) && p.hp > 1) m['chuck'] = null;
    if (p.has(Ab.discardTwoShot) && !docUsed && p.hand.length >= 2) {
      final t = _shotTargets(p, null, Reach.weapon);
      if (t != null) m['doc'] = t;
    }
    if (p.has(Ab.blueForTwo) && joseUses < 2 && p.hand.any((c) => c.def.color == CardColor.blue)) {
      m['jose'] = null;
    }
    return m;
  }

  String _abilityLabel(String id) => const {
        'silas': 'Сбросить 2 карты: +1 жизнь',
        'chuck': '−1 жизнь: взять 2 карты',
        'doc': 'Сбросить 2 карты: выстрел',
        'jose': 'Сбросить синюю карту: взять 2',
      }[id]!;

  // ======================================================================
  // Розыгрыш
  // ======================================================================

  Future<void> _playFromHand(Player p, GameCard c, Player? t) async {
    final d = c.def;
    if (d.extraCost && p.hand.length > 1) {
      final ch = await _choose(p, 'Сбросьте ещё одну карту за «${d.name}»',
          p.hand.where((x) => x != c).map((x) => _cardOpt(x)).toList());
      final x = _findById(p.hand, _cid(ch.first))!;
      p.hand.remove(x);
      discard.add(x);
    }
    p.hand.remove(c);
    final on = t == null ? '' : ' → ${t.name}';

    if (d.color == CardColor.blue) {
      if (d.eff == Eff.jail) {
        t!.table.add(c);
        _log('${p.name} сажает ${t.name} в тюрьму.');
      } else {
        if (d.eff == Eff.weapon) {
          final old = _weapon(p);
          if (old != null) {
            p.table.remove(old);
            discard.add(old);
          }
        }
        p.table.add(c);
        _log('${p.name} выкладывает «${d.name}».');
      }
      return;
    }
    if (d.color == CardColor.green) {
      c.playedTurn = turnNo;
      p.table.add(c);
      _log('${p.name} выкладывает «${d.name}».');
      return;
    }

    discard.add(c);
    if (d.isMissedLike) {
      // Мэгги стреляет «Промахом»
      _log('${p.name} стреляет картой «${d.name}»$on.');
      shotsThisTurn++;
      await _shoot(p, t!, shotCard: true);
      return;
    }
    _log('${p.name} играет «${d.name}»$on.');
    await _resolve(p, c, t, fromHand: true);
  }

  Future<void> _activateGreen(Player p, GameCard c, Player? t) async {
    p.table.remove(c);
    discard.add(c);
    final on = t == null ? '' : ' → ${t.name}';
    _log('${p.name} использует «${c.name}»$on.');
    await _resolve(p, c, t, fromHand: false);
  }

  Future<void> _resolve(Player p, GameCard c, Player? t, {required bool fromHand}) async {
    final d = c.def;
    switch (d.eff) {
      case Eff.shot:
        if (fromHand && d.countsBang) shotsThisTurn++;
        await _shoot(p, t!, shotCard: fromHand && d.isShotCard);
        if (!fromHand && d.value > 0 && p.alive) _draw(p, d.value); // Дерринджер
        break;
      case Eff.heal:
        final amount = (c.key == 'nastoyka' && p.has(Ab.strongHeal)) ? 2 : d.value;
        _heal(p, amount);
        break;
      case Eff.healAny:
        _heal(t!, d.value);
        break;
      case Eff.healAll:
        for (final o in _alive()) {
          _heal(o, 1);
        }
        break;
      case Eff.draw:
        _draw(p, d.value);
        break;
      case Eff.store:
        await _store(p);
        break;
      case Eff.steal:
        await _takeCard(p, t!, steal: true);
        break;
      case Eff.discardTarget:
        await _takeCard(p, t!, steal: false);
        break;
      case Eff.duel:
        await _duel(p, t!);
        break;
      case Eff.gatling:
        for (final o in _clockwiseFrom(p)) {
          if (o.alive && !_immune(p, o, c)) await _shoot(p, o);
        }
        break;
      case Eff.indians:
        for (final o in _clockwiseFrom(p)) {
          if (o.alive && !_immune(p, o, c)) await _indians(p, o);
        }
        break;
      case Eff.brawl:
        for (final o in _clockwiseFrom(p)) {
          if (o.alive && !_immune(p, o, c) && (o.hand.isNotEmpty || o.table.isNotEmpty)) {
            await _takeCard(p, o, steal: false);
          }
        }
        break;
      default:
        break;
    }
  }

  Future<void> _useAbility(Player p, String id, Player? t) async {
    switch (id) {
      case 'silas':
        await _discardN(p, 2, 'Сбросьте 2 карты, чтобы восстановить жизнь');
        _heal(p, 1);
        _log('${p.name} сбрасывает 2 карты и восстанавливает жизнь.');
        break;
      case 'chuck':
        p.hp -= 1;
        _draw(p, 2);
        _log('${p.name} теряет жизнь и берёт 2 карты.');
        break;
      case 'doc':
        docUsed = true;
        await _discardN(p, 2, 'Сбросьте 2 карты для выстрела');
        _log('${p.name} сбрасывает 2 карты и стреляет в ${t!.name}.');
        await _shoot(p, t);
        break;
      case 'jose':
        joseUses++;
        final blues = p.hand.where((c) => c.def.color == CardColor.blue).map((c) => _cardOpt(c)).toList();
        final ch = await _choose(p, 'Какую синюю карту сбросить?', blues);
        final c = _findById(p.hand, _cid(ch.first))!;
        p.hand.remove(c);
        discard.add(c);
        _draw(p, 2);
        _log('${p.name} сбрасывает «${c.name}» и берёт 2 карты.');
        break;
    }
  }

  Future<void> _discardN(Player p, int n, String title) async {
    final ch = await _choose(p, title, p.hand.map((c) => _cardOpt(c)).toList(), min: n, max: n);
    for (final id in ch) {
      final c = _findById(p.hand, _cid(id))!;
      p.hand.remove(c);
      discard.add(c);
    }
  }

  // ======================================================================
  // Эффекты
  // ======================================================================

  /// [shotCard] — выстрел картой «Выстрел» (против Слэйда нужно 2 промаха).
  Future<void> _shoot(Player a, Player t, {bool shotCard = false}) async {
    if (!t.alive) return;
    var need = (shotCard && a.has(Ab.doubleMissed)) ? 2 : 1;
    final barrels = <String>[];
    if (_tableActive(t) && _hasInPlay(t, 'ukrytie')) barrels.add('укрытие');
    if (t.has(Ab.builtinBarrel)) barrels.add('укрытие (способность)');
    for (final b in barrels) {
      if (need == 0) break;
      final c = await _check(t, b);
      if (c != null && c.suit == Suit.hearts) {
        need--;
        _log('${t.name} уходит от пули: ${c.label}.');
      }
    }
    while (need > 0) {
      final opts = _missOptions(t);
      if (opts.isEmpty) break;
      final ch = await _choose(t, '${a.name} стреляет в вас!', opts,
          min: 0, max: 1, text: 'Нужно промахов: $need. Без промаха вы потеряете 1 жизнь.');
      if (ch.isEmpty) break;
      _useMiss(t, ch.first);
      need--;
      _changed();
    }
    if (need > 0) await _damage(t, 1, a);
  }

  List<Json> _missOptions(Player t) {
    final opts = <Json>[];
    for (final c in t.hand) {
      final d = c.def;
      final ok = (d.color == CardColor.brown && d.isMissedLike) ||
          (t.has(Ab.swapShotMissed) && c.key == 'vystrel') ||
          t.has(Ab.anyAsMissed);
      if (ok) opts.add(_cardOpt(c));
    }
    if (_tableActive(t)) {
      for (final c in t.table) {
        if (c.def.color == CardColor.green && c.def.isMissedLike && turnNo > c.playedTurn) {
          opts.add(_cardOpt(c, id: 'g${c.id}', label: '${c.label} (выложена)'));
        }
      }
    }
    return opts;
  }

  void _useMiss(Player t, String id) {
    final GameCard c;
    if (id.startsWith('g')) {
      c = _findById(t.table, int.parse(id.substring(1)))!;
      t.table.remove(c);
    } else {
      c = _findById(t.hand, _cid(id))!;
      t.hand.remove(c);
      _mollyDraw(t);
    }
    discard.add(c);
    _log('${t.name} уворачивается: «${c.name}».');
    if (c.def.eff == Eff.dodge) _draw(t, 1);
  }

  bool _isShotLike(Player p, GameCard c) =>
      c.key == 'vystrel' || (p.has(Ab.swapShotMissed) && c.def.color == CardColor.brown && c.def.isMissedLike);

  Future<void> _indians(Player a, Player o) async {
    final opts = o.hand.where((c) => _isShotLike(o, c)).map((c) => _cardOpt(c)).toList();
    if (opts.isNotEmpty) {
      final ch = await _choose(o, 'Набег!', opts,
          min: 0, max: 1, text: 'Сбросьте «Выстрел» или потеряйте 1 жизнь.');
      if (ch.isNotEmpty) {
        final c = _findById(o.hand, _cid(ch.first))!;
        o.hand.remove(c);
        discard.add(c);
        _mollyDraw(o);
        _log('${o.name} отбивается: «${c.name}».');
        _changed();
        return;
      }
    }
    await _damage(o, 1, a);
  }

  Future<void> _duel(Player a, Player t) async {
    var turnP = t;
    var other = a;
    var mollyOwn = 0; // Молли в свой ход добирает карты после дуэли
    while (true) {
      final opts = turnP.hand.where((c) => _isShotLike(turnP, c)).map((c) => _cardOpt(c)).toList();
      List<String> ch = const [];
      if (opts.isNotEmpty) {
        ch = await _choose(turnP, 'Дуэль с ${other.name}', opts,
            min: 0, max: 1, text: 'Сбросьте «Выстрел» или потеряйте 1 жизнь.');
      }
      if (ch.isEmpty) {
        _log('${turnP.name} проигрывает дуэль.');
        await _damage(turnP, 1, other);
        if (mollyOwn > 0 && a.alive) _draw(a, mollyOwn);
        return;
      }
      final c = _findById(turnP.hand, _cid(ch.first))!;
      turnP.hand.remove(c);
      discard.add(c);
      _mollyDraw(turnP);
      if (turnP == a && a == players[cur] && a.has(Ab.drawOutOfTurn)) mollyOwn++;
      _log('${turnP.name} стреляет в дуэли.');
      _changed();
      final tmp = turnP;
      turnP = other;
      other = tmp;
    }
  }

  Future<void> _store(Player p) async {
    final n = _alive().length;
    for (var i = 0; i < n; i++) {
      final c = _pop();
      if (c != null) storeCards.add(c);
    }
    _changed();
    for (final o in [p, ..._clockwiseFrom(p)]) {
      if (storeCards.isEmpty) break;
      if (!o.alive) continue;
      final ch = await _choose(o, 'Ярмарка: выберите карту', storeCards.map((c) => _cardOpt(c)).toList());
      final c = _findById(storeCards, _cid(ch.first))!;
      storeCards.remove(c);
      o.hand.add(c);
      _log('${o.name} берёт с ярмарки «${c.name}».');
      _changed();
    }
    discard.addAll(storeCards);
    storeCards.clear();
  }

  Future<void> _takeCard(Player a, Player t, {required bool steal}) async {
    final opts = <Json>[];
    if (t.hand.isNotEmpty) opts.add({'id': 'hand', 'label': 'Случайная карта с руки (${t.hand.length})'});
    for (final c in t.table) {
      opts.add(_cardOpt(c));
    }
    if (opts.isEmpty) return;
    final ch = await _choose(a, steal ? 'Что забрать у ${t.name}?' : 'Что сбросить у ${t.name}?', opts);
    final GameCard c;
    final fromHand = ch.first == 'hand';
    if (fromHand) {
      c = t.hand.removeAt(rng.nextInt(t.hand.length));
    } else {
      c = _findById(t.table, _cid(ch.first))!;
      t.table.remove(c);
    }
    c.playedTurn = -1;
    if (steal) {
      a.hand.add(c);
      _log(fromHand
          ? '${a.name} забирает карту с руки ${t.name}.'
          : '${a.name} забирает «${c.name}» у ${t.name}.');
    } else {
      discard.add(c);
      _log('${a.name} сбрасывает «${c.name}» у ${t.name}.');
    }
    _changed();
  }

  void _heal(Player p, int n) {
    if (!p.alive) return;
    final before = p.hp;
    p.hp = min(p.maxHp, p.hp + n);
    if (p.hp > before) _log('${p.name} восстанавливает ${p.hp - before} жизн(и).');
  }

  Future<void> _damage(Player v, int n, Player? src) async {
    if (!v.alive) return;
    v.hp -= n;
    _log('${v.name} теряет $n жизн${n == 1 ? 'ь' : 'и'}.');
    _changed();
    if (v.hp <= 0) {
      await _dying(v, src);
      if (!v.alive) return;
    }
    if (v.has(Ab.drawOnDamage)) _draw(v, n);
    if (v.has(Ab.takeFromAttacker) && src != null && src != v) {
      for (var i = 0; i < n && src.hand.isNotEmpty; i++) {
        v.hand.add(src.hand.removeAt(rng.nextInt(src.hand.length)));
        _log('${v.name} забирает карту у ${src.name}.');
      }
    }
    _changed();
  }

  Future<void> _dying(Player v, Player? src) async {
    while (v.hp <= 0) {
      final opts = <Json>[];
      if (_alive().length > 2) {
        for (final c in v.hand) {
          if (c.key == 'nastoyka') opts.add(_cardOpt(c));
        }
      }
      if (v.has(Ab.discardTwoHeal) && v.hand.length >= 2) {
        opts.add({'id': 'silas', 'label': 'Сбросить 2 карты: +1 жизнь'});
      }
      if (_tableActive(v)) {
        for (final c in v.table) {
          if (c.key == 'flyazhka' && turnNo > c.playedTurn) {
            opts.add(_cardOpt(c, id: 'g${c.id}', label: '${c.label} (выложена)'));
          }
        }
      }
      if (opts.isEmpty) break;
      final ch = await _choose(v, 'Вы при смерти!', opts,
          min: 0, max: 1, text: 'Жизни: ${v.hp}. Спасите себя или выбудьте из игры.');
      if (ch.isEmpty) break;
      final id = ch.first;
      if (id == 'silas') {
        await _discardN(v, 2, 'Сбросьте 2 карты');
        v.hp += 1;
      } else if (id.startsWith('g')) {
        final c = _findById(v.table, int.parse(id.substring(1)))!;
        v.table.remove(c);
        discard.add(c);
        v.hp += 1;
      } else {
        final c = _findById(v.hand, _cid(id))!;
        v.hand.remove(c);
        discard.add(c);
        v.hp += v.has(Ab.strongHeal) ? 2 : 1;
        _mollyDraw(v);
      }
      _log('${v.name} спасается! Жизни: ${v.hp}.');
      _changed();
    }
    if (v.hp <= 0) await _eliminate(v, src);
  }

  Future<void> _eliminate(Player v, Player? killer) async {
    v.alive = false;
    v.hp = 0;
    _log('☠ ${v.name} выбывает. Роль: ${v.role.title}.');
    final cards = [...v.hand, ...v.table];
    v.hand.clear();
    v.table.clear();
    for (final c in cards) {
      c.playedTurn = -1;
    }
    final grey = _find(_alive(), (o) => o.has(Ab.takeDeadCards));
    if (grey != null && cards.isNotEmpty) {
      grey.hand.addAll(cards);
      _log('${grey.name} забирает карты выбывшего.');
    } else {
      discard.addAll(cards);
    }
    for (final o in _alive()) {
      if (o.has(Ab.healOnDeath)) _heal(o, 2);
      if (o.has(Ab.drawOnDeath)) {
        _draw(o, 2);
        _log('${o.name} берёт 2 карты.');
      }
    }
    if (killer != null && killer.alive && killer != v) {
      if (v.role == Role.outlaw) {
        _draw(killer, 3);
        _log('${killer.name} получает награду: 3 карты.');
      } else if (v.role == Role.deputy && killer.role == Role.sheriff) {
        discard.addAll(killer.hand);
        discard.addAll(killer.table);
        killer.hand.clear();
        killer.table.clear();
        _log('Шериф убил своего помощника и теряет все карты!');
      }
    }
    _checkWin();
    _changed();
    if (v == players[cur]) throw _TurnEnded();
  }

  void _checkWin() {
    final alive = _alive();
    if (!_sheriff.alive) {
      if (alive.length == 1 && alive.first.role == Role.renegade) {
        throw GameOver('Победил одиночка ${alive.first.name}!', [alive.first.id]);
      }
      throw GameOver('Шериф убит — бандиты победили!',
          players.where((p) => p.role == Role.outlaw).map((p) => p.id).toList());
    }
    if (alive.every((p) => p.role == Role.sheriff || p.role == Role.deputy)) {
      throw GameOver('Закон восторжествовал — победили шериф и помощники!',
          players.where((p) => p.role == Role.sheriff || p.role == Role.deputy).map((p) => p.id).toList());
    }
  }

  // ======================================================================
  // Колода и проверки
  // ======================================================================

  GameCard? _pop() {
    if (deck.isEmpty) {
      if (discard.isEmpty) return null;
      deck.addAll(discard);
      discard.clear();
      deck.shuffle(rng);
      _log('Сброс перемешан в новую колоду.');
    }
    return deck.removeLast();
  }

  void _draw(Player p, int n) {
    for (var i = 0; i < n; i++) {
      final c = _pop();
      if (c == null) return;
      c.playedTurn = -1;
      p.hand.add(c);
    }
  }

  /// «Проверка»: открыть верхнюю карту колоды.
  Future<GameCard?> _check(Player p, String reason) async {
    if (p.has(Ab.luckyCheck)) {
      final pair = <GameCard>[];
      for (var i = 0; i < 2; i++) {
        final c = _pop();
        if (c != null) pair.add(c);
      }
      if (pair.isEmpty) return null;
      discard.addAll(pair);
      final ch = await _choose(p, 'Проверка ($reason): выберите карту', pair.map((c) => _cardOpt(c)).toList());
      final c = _findById(pair, _cid(ch.first))!;
      _log('${p.name} проверяет ($reason): ${c.label}.');
      return c;
    }
    final c = _pop();
    if (c == null) return null;
    discard.add(c);
    _log('${p.name} проверяет ($reason): ${c.label}.');
    return c;
  }

  void _mollyDraw(Player p) {
    if (p.has(Ab.drawOutOfTurn) && p != players[cur]) {
      _draw(p, 1);
      _log('${p.name} берёт карту.');
    }
  }

  // ======================================================================
  // Расстояния
  // ======================================================================

  /// Карты на столе [owner] действуют (их отключает Белла Стоун в свой ход).
  bool _tableActive(Player owner) {
    final c = players[cur];
    return !(c.alive && c != owner && c.has(Ab.disableOthersCards));
  }

  bool _immune(Player src, Player target, GameCard? card) =>
      card != null && src != target && target.has(Ab.immuneDiamonds) && card.suit == Suit.diamonds;

  int dist(Player a, Player b) {
    final alive = _alive();
    final ia = alive.indexOf(a), ib = alive.indexOf(b);
    if (ia < 0 || ib < 0) return 99;
    final raw = (ia - ib).abs();
    var d = min(raw, alive.length - raw);
    if (_tableActive(b)) d += b.table.where((c) => c.def.eff == Eff.horse).length;
    if (b.has(Ab.builtinHorse)) d += 1;
    if (_tableActive(a)) d -= a.table.where((c) => c.def.eff == Eff.scope).length;
    if (a.has(Ab.builtinScope)) d -= 1;
    return max(1, d);
  }

  int range(Player p) => _tableActive(p) ? (_weapon(p)?.def.value ?? 1) : 1;

  GameCard? _weapon(Player p) => _find(p.table, (c) => c.def.eff == Eff.weapon);

  // ======================================================================
  // Вспомогательное
  // ======================================================================

  Player get _sheriff => players.firstWhere((p) => p.role == Role.sheriff);
  List<Player> _alive() => players.where((p) => p.alive).toList();
  Player _byId(int id) => players.firstWhere((p) => p.id == id);

  int _nextAliveIndex(int i) {
    for (var k = 1; k <= players.length; k++) {
      final j = (i + k) % players.length;
      if (players[j].alive) return j;
    }
    return i;
  }

  /// Остальные живые игроки по часовой стрелке, начиная со следующего за [p].
  List<Player> _clockwiseFrom(Player p) {
    final i = players.indexOf(p);
    final out = <Player>[];
    for (var k = 1; k < players.length; k++) {
      final o = players[(i + k) % players.length];
      if (o.alive) out.add(o);
    }
    return out;
  }

  bool _hasInPlay(Player p, String key) => p.table.any((c) => c.key == key);
  GameCard? _inPlay(Player p, String key) => _find(p.table, (c) => c.key == key);

  static T? _find<T>(Iterable<T> it, bool Function(T) f) {
    for (final x in it) {
      if (f(x)) return x;
    }
    return null;
  }

  static GameCard? _findById(List<GameCard> l, int id) => _find(l, (c) => c.id == id);
  static int _cid(String optId) => int.parse(optId.substring(1));
  static int? _asInt(dynamic v) => v is int ? v : int.tryParse('$v');

  Json _cardOpt(GameCard c, {String? id, String? label}) =>
      {'id': id ?? 'c${c.id}', 'label': label ?? c.label, 'card': c.toJson()};

  void _log(String s) {
    log.add(s);
    if (log.length > 300) log.removeRange(0, log.length - 300);
  }

  void _changed() {
    if (_dealt && result == null) {
      for (final p in players) {
        if (p.alive && p.has(Ab.drawWhenEmpty) && p.hand.isEmpty) {
          final c = _pop();
          if (c != null) {
            p.hand.add(c);
            _log('${p.name} берёт карту (пустая рука).');
          }
        }
      }
    }
    onChange?.call();
  }

  Future<Json> _ask(Player p, Json req) async {
    req['rid'] = ++_reqSeq;
    waitingOn.add(p.id);
    _changed();
    try {
      return await ask(p.id, req);
    } finally {
      waitingOn.remove(p.id);
    }
  }

  /// Спросить выбор из списка. Возвращает id выбранных вариантов.
  Future<List<String>> _choose(Player p, String title, List<Json> options,
      {int min = 1, int max = 1, String? text, bool alwaysAsk = false}) async {
    if (options.isEmpty) return const [];
    final ids = options.map((o) => o['id'] as String).toList();
    if (!alwaysAsk && min == ids.length) return ids; // выбора нет
    for (var attempt = 0; attempt < 3; attempt++) {
      final resp = await _ask(p, {
        'type': 'choose',
        'title': title,
        if (text != null) 'text': text,
        'options': options,
        'min': min,
        'max': max,
      });
      final raw = resp['choice'];
      final ch = raw is List ? raw.map((e) => '$e').toList() : <String>[];
      if (ch.length >= min && ch.length <= max && ch.toSet().length == ch.length && ch.every(ids.contains)) {
        return ch;
      }
    }
    return ids.take(min).toList();
  }

  /// Ответ по умолчанию — для игрока, который отключился и не вернулся.
  static Json defaultResponse(Json req) {
    if (req['type'] == 'turn') return {'action': 'end'};
    final opts = (req['options'] as List).cast<Map>();
    final m = req['min'] as int;
    return {'choice': opts.take(m).map((o) => o['id']).toList()};
  }

  /// Сколько всего карт в игре (для проверки целостности).
  int countCards() =>
      deck.length +
      discard.length +
      storeCards.length +
      _held.length +
      players.fold<int>(0, (s, p) => s + p.hand.length + p.table.length);

  // ======================================================================
  // Что видит конкретный игрок
  // ======================================================================

  Json viewFor(int viewerId) {
    final over = result != null;
    final me = _byId(viewerId);
    final current = players[cur];
    return {
      'me': viewerId,
      'cur': current.id,
      'turnNo': turnNo,
      'expansion': expansion,
      'deck': deck.length,
      'discardTop': discard.isEmpty ? null : discard.last.toJson(),
      'store': storeCards.map((c) => c.toJson()).toList(),
      'hand': me.hand.map((c) => c.toJson()).toList(),
      'myRange': me.alive ? range(me) : 0,
      'shots': current == me ? shotsThisTurn : 0,
      'waiting': waitingOn.toList(),
      'log': log.length > 60 ? log.sublist(log.length - 60) : log,
      'result': result?.toJson(),
      'players': [
        for (final p in players)
          {
            'id': p.id,
            'name': p.name,
            'alive': p.alive,
            'hp': p.hp,
            'maxHp': p.maxHp,
            'ch': p.ch?.key,
            'role': (p == me || p.role == Role.sheriff || !p.alive || over) ? p.role.index : null,
            'handCount': p.hand.length,
            'table': [
              for (final c in p.table) {...c.toJson(), 'ready': turnNo > c.playedTurn}
            ],
            'dist': (p != me && p.alive && me.alive) ? dist(me, p) : null,
          }
      ],
    };
  }
}
