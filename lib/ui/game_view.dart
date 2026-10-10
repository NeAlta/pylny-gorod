import 'package:flutter/material.dart';

import '../engine/characters.dart';
import '../engine/game.dart' show Json;
import '../net/session.dart';
import 'card_widget.dart';
import 'rules_screen.dart';
import 'theme.dart';

/// Выбранное действие, для которого нужно указать цель.
class _Sel {
  final String kind; // play | act | ability
  final Object id;
  final List<int> targets;
  final String label;
  _Sel(this.kind, this.id, this.targets, this.label);
}

class GameView extends StatefulWidget {
  final GameSession session;
  final VoidCallback onExit;
  const GameView({super.key, required this.session, required this.onExit});

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> {
  _Sel? _sel;
  final Set<String> _choice = {};
  Object? _choiceRid;
  bool _overlayHidden = false;

  GameSession get s => widget.session;

  // ------------------------------------------------------------------
  // разбор состояния
  // ------------------------------------------------------------------

  Json get st => s.state!;
  int get me => st['me'] as int;
  List<Json> get players => (st['players'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Json _player(int id) => players.firstWhere((p) => p['id'] == id);

  Map<int, List<int>?> _parseTargets(List? l) {
    final m = <int, List<int>?>{};
    for (final e in l ?? const []) {
      final t = e['targets'];
      m[e['card'] as int] = t == null ? null : (t as List).cast<int>();
    }
    return m;
  }

  void _respond(Json data) {
    setState(() => _sel = null);
    s.respond(data);
  }

  void _act(String kind, Object id, List<int>? targets, String label) {
    if (_sel != null && _sel!.kind == kind && _sel!.id == id) {
      setState(() => _sel = null);
      return;
    }
    if (targets == null || targets.isEmpty) {
      _respond({'action': kind, if (kind == 'ability') 'id': id else 'card': id});
    } else {
      setState(() => _sel = _Sel(kind, id, targets, label));
    }
  }

  void _tapPlayer(Json p) {
    final sel = _sel;
    final pid = p['id'] as int;
    if (sel != null && sel.targets.contains(pid)) {
      _respond({
        'action': sel.kind,
        if (sel.kind == 'ability') 'id': sel.id else 'card': sel.id,
        'target': pid,
      });
      return;
    }
    final ch = characterDefs[p['ch']];
    if (ch != null) showCharacterDetails(context, ch, playerName: p['name'] as String);
  }

  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final req = s.request;
    final turnReq = req?['type'] == 'turn' ? req : null;
    final chooseReq = req?['type'] == 'choose' ? req : null;
    if (chooseReq?['rid'] != _choiceRid) {
      _choice.clear();
      _choiceRid = chooseReq?['rid'];
      _overlayHidden = false;
    }
    if (turnReq == null) _sel = null;

    final plays = _parseTargets(turnReq?['plays'] as List?);
    final acts = _parseTargets(turnReq?['acts'] as List?);
    final abilities = (turnReq?['abilities'] as List?)?.cast<Map>() ?? const <Map>[];
    final cur = _player(st['cur'] as int);
    final result = st['result'] as Map?;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(cur['id'] == me ? 'Ваш ход' : 'Ходит ${cur['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text('Колода: ${st['deck']} · ход ${st['turnNo']}',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12, color: Pal.sand)),
            ],
          ),
          actions: [
            IconButton(
                tooltip: 'Журнал', icon: const Icon(Icons.receipt_long), onPressed: () => _showLog(context)),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'rules') {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesScreen()));
                } else if (v == 'skip') {
                  final h = s;
                  if (h is HostSession) h.forceSkip();
                } else if (v == 'exit') {
                  _confirmExit();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rules', child: Text('Правила и карты')),
                if (s is HostSession && (s as HostSession).canForceSkip)
                  const PopupMenuItem(value: 'skip', child: Text('Пропустить за тех, кто молчит')),
                const PopupMenuItem(value: 'exit', child: Text('Выйти из партии')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (s.status != null) _banner(s.status!, Pal.blood),
                  if (_sel != null)
                    _banner('Выберите цель: «${_sel!.label}»', Pal.brass,
                        dark: true, action: TextButton(
                            onPressed: () => setState(() => _sel = null),
                            child: const Text('Отмена', style: TextStyle(color: Pal.ink)))),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        children: [
                          _opponents(),
                          const SizedBox(height: 10),
                          _centerStrip(),
                        ],
                      ),
                    ),
                  ),
                  _myPanel(acts),
                  _hand(plays, turnReq != null),
                  _actionBar(turnReq, abilities),
                ],
              ),
              if (chooseReq != null && result == null)
                _overlayHidden
                    ? Positioned(
                        left: 12, // без left ширина не ограничена: длинный заголовок уезжает за экран
                        right: 12,
                        bottom: 12,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: () => setState(() => _overlayHidden = false),
                            icon: const Icon(Icons.help_outline),
                            label: Text('${chooseReq['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      )
                    : Positioned.fill(child: _chooseOverlay(chooseReq)),
              if (result != null) Positioned.fill(child: _gameOver(result)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, Color color, {bool dark = false, Widget? action}) => Container(
        width: double.infinity,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: Text(text,
                    style: TextStyle(color: dark ? Pal.ink : Colors.white, fontWeight: FontWeight.w700))),
            if (action != null) action,
          ],
        ),
      );

  // ------------------------------------------------------------------
  // соперники
  // ------------------------------------------------------------------

  Widget _opponents() {
    final all = players;
    final myIdx = all.indexWhere((p) => p['id'] == me);
    final others = [for (var k = 1; k < all.length; k++) all[(myIdx + k) % all.length]];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 700 ? 4 : (c.maxWidth > 480 ? 3 : 2);
      final w = (c.maxWidth - 8 * (cols - 1)) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final p in others) _playerTile(p, w)],
      );
    });
  }

  Widget _hearts(int hp, int max, {double size = 14}) => Wrap(
        spacing: 1,
        children: [
          for (var i = 0; i < max; i++)
            Icon(i < hp ? Icons.favorite : Icons.favorite_border,
                size: size, color: i < hp ? Pal.blood : Pal.sand.withValues(alpha: 0.6)),
        ],
      );

  Widget _playerTile(Json p, double width) {
    final id = p['id'] as int;
    final alive = p['alive'] as bool;
    final roleIdx = p['role'] as int?;
    final role = roleIdx == null ? null : Role.values[roleIdx];
    final ch = characterDefs[p['ch']];
    final isCur = st['cur'] == id;
    final isTarget = _sel?.targets.contains(id) ?? false;
    final waiting = (st['waiting'] as List).contains(id);
    final offline = ((st['offline'] as List?) ?? const []).contains(id);
    final isBot = ((st['bots'] as List?) ?? const []).contains(id);
    final dist = p['dist'] as int?;
    final inRange = dist != null && dist <= (st['myRange'] as int);
    final table = (p['table'] as List).map((c) => CardInfo.fromJson(c as Map)).toList();

    final border = isTarget
        ? Pal.ok
        : isCur
            ? Pal.brass
            : Pal.surface2;

    return GestureDetector(
      onTap: () => _tapPlayer(p),
      child: Opacity(
        opacity: alive ? 1 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: width,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isTarget ? Pal.ok.withValues(alpha: 0.15) : Pal.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: isTarget || isCur ? 2.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (role != null) ...[
                    Icon(roleIcon(role), size: 16, color: roleColor(role)),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text('${p['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  if (isBot) const Icon(Icons.smart_toy, size: 15, color: Pal.sand),
                  if (offline) const Icon(Icons.wifi_off, size: 15, color: Pal.blood),
                  if (waiting) const Icon(Icons.hourglass_bottom, size: 15, color: Pal.brass),
                ],
              ),
              Text(ch?.name ?? 'выбирает персонажа…',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Pal.sand)),
              const SizedBox(height: 4),
              if (alive)
                _hearts(p['hp'] as int, p['maxHp'] as int)
              else
                Text('☠ выбыл${role != null ? ' — ${role.title}' : ''}',
                    style: const TextStyle(fontSize: 12, color: Pal.sand)),
              if (alive) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.style, size: 14, color: Pal.sand),
                    Text(' ${p['handCount']}', style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 10),
                    if (dist != null) ...[
                      Icon(inRange ? Icons.my_location : Icons.straighten,
                          size: 14, color: inRange ? Pal.brass : Pal.sand),
                      Text(' дист. $dist',
                          style: TextStyle(fontSize: 13, color: inRange ? Pal.brass : Pal.parchment)),
                    ],
                  ],
                ),
              ],
              if (table.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: [for (final c in table) TableChip(card: c)]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // центр стола
  // ------------------------------------------------------------------

  Widget _centerStrip() {
    final top = st['discardTop'];
    final log = (st['log'] as List).cast<String>();
    final store = (st['store'] as List).map((c) => CardInfo.fromJson(c as Map)).toList();
    final last = log.length > 4 ? log.sublist(log.length - 4) : log;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardBack(width: 44, label: '${st['deck']}'),
              const SizedBox(width: 6),
              top == null
                  ? Container(
                      width: 44,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: Pal.surface2, width: 2),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    )
                  : CardFace(card: CardInfo.fromJson(top as Map), width: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < last.length; i++)
                      Text(
                        last[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: i == last.length - 1 ? Pal.parchment : Pal.sand.withValues(alpha: 0.8),
                          fontWeight: i == last.length - 1 ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (store.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Ярмарка', style: TextStyle(fontWeight: FontWeight.w700, color: Pal.brass)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final c in store) CardFace(card: c, width: 52)]),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // мой игрок
  // ------------------------------------------------------------------

  Widget _myPanel(Map<int, List<int>?> acts) {
    final p = _player(me);
    final role = p['role'] == null ? null : Role.values[p['role'] as int];
    final ch = characterDefs[p['ch']];
    final table = (p['table'] as List).map((c) => CardInfo.fromJson(c as Map)).toList();
    final isTarget = _sel?.targets.contains(me) ?? false;
    final alive = p['alive'] as bool;
    return GestureDetector(
      onTap: () => _tapPlayer(p),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: isTarget ? Pal.ok.withValues(alpha: 0.2) : Pal.surface2,
          border: Border(top: BorderSide(color: isTarget ? Pal.ok : Pal.brass.withValues(alpha: 0.5), width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (role != null) ...[
                  Icon(roleIcon(role), size: 18, color: roleColor(role)),
                  const SizedBox(width: 4),
                  Text(role.title, style: TextStyle(fontWeight: FontWeight.w800, color: roleColor(role))),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(ch?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (alive) _hearts(p['hp'] as int, p['maxHp'] as int, size: 17) else const Text('☠ вы выбыли'),
              ],
            ),
            if (alive)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Дальность оружия: ${st['myRange']}${ch != null ? ' · ${ch.text}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Pal.sand),
                ),
              ),
            if (table.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final c in table)
                    TableChip(
                      card: c,
                      highlight: acts.containsKey(c.id),
                      onTap: acts.containsKey(c.id) ? () => _act('act', c.id, acts[c.id], c.def.name) : null,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hand(Map<int, List<int>?> plays, bool myTurn) {
    final hand = (st['hand'] as List).map((c) => CardInfo.fromJson(c as Map)).toList();
    const w = 74.0;
    return Container(
      color: Pal.surface2,
      height: w * 1.45 + 22,
      child: hand.isEmpty
          ? const Center(child: Text('Нет карт на руке', style: TextStyle(color: Pal.sand)))
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
              itemCount: hand.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final c = hand[i];
                final playable = plays.containsKey(c.id);
                return CardFace(
                  card: c,
                  width: w,
                  highlight: playable,
                  selected: _sel?.kind == 'play' && _sel?.id == c.id,
                  dim: myTurn && !playable,
                  onTap: playable
                      ? () => _act('play', c.id, plays[c.id], c.def.name)
                      : () => showCardDetails(context, c),
                );
              },
            ),
    );
  }

  Widget _actionBar(Json? turnReq, List<Map> abilities) {
    if (turnReq == null) {
      final waiting = (st['waiting'] as List).cast<int>().where((id) => id != me).toList();
      final names = waiting.map((id) => _player(id)['name']).join(', ');
      return Container(
        width: double.infinity,
        color: Pal.bg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Text(waiting.isEmpty ? '…' : 'Ждём: $names',
            textAlign: TextAlign.center, style: const TextStyle(color: Pal.sand)),
      );
    }
    return Container(
      color: Pal.bg,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final a in abilities)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: OutlinedButton(
                        onPressed: () => _act('ability', a['id'] as String,
                            (a['targets'] as List?)?.cast<int>(), a['label'] as String),
                        child: Text('${a['label']}', style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          FilledButton(
            onPressed: () => _respond({'action': 'end'}),
            child: const Text('Закончить ход'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // выбор
  // ------------------------------------------------------------------

  Widget _chooseOverlay(Json req) {
    final options = (req['options'] as List).cast<Map>();
    final min = req['min'] as int;
    final max = req['max'] as int;
    final cardOpts = options.where((o) => o['card'] != null).toList();
    final otherOpts = options.where((o) => o['card'] == null).toList();
    final valid = _choice.length >= min && _choice.length <= max;

    void toggle(String id) {
      setState(() {
        if (_choice.contains(id)) {
          _choice.remove(id);
        } else if (max == 1) {
          _choice
            ..clear()
            ..add(id);
        } else if (_choice.length < max) {
          _choice.add(id);
        }
      });
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      alignment: Alignment.bottomCenter,
      child: LayoutBuilder(builder: (context, c) {
        return Container(
          constraints: BoxConstraints(maxHeight: c.maxHeight * 0.72),
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Pal.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(top: BorderSide(color: Pal.brass, width: 2)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${req['title']}',
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Pal.brass)),
                  ),
                  IconButton(
                    tooltip: 'Посмотреть стол',
                    icon: const Icon(Icons.expand_more),
                    onPressed: () => setState(() => _overlayHidden = true),
                  ),
                ],
              ),
              if (req['text'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${req['text']}', style: const TextStyle(color: Pal.sand, fontSize: 14)),
                ),
              if (max > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(min == max ? 'Выберите: $min' : 'Выберите от $min до $max',
                      style: const TextStyle(fontSize: 13)),
                ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (cardOpts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 14,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final o in cardOpts)
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CardFace(
                                      card: CardInfo.fromJson(o['card'] as Map),
                                      width: 78,
                                      selected: _choice.contains(o['id']),
                                      onTap: () => toggle(o['id'] as String),
                                    ),
                                    if ('${o['label']}'.contains('—') || '${o['label']}'.contains('('))
                                      SizedBox(
                                        width: 84,
                                        child: Text(_suffix('${o['label']}'),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            style: const TextStyle(fontSize: 11, color: Pal.sand)),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      for (final o in otherOpts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _optionTile(o, _choice.contains(o['id']), () => toggle(o['id'] as String)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (min == 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _respond({'choice': <String>[]}),
                        child: const Text('Пропустить'),
                      ),
                    ),
                  if (min == 0) const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: valid && _choice.isNotEmpty ? () => _respond({'choice': _choice.toList()}) : null,
                      child: const Text('Готово'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  String _suffix(String label) {
    final i = label.indexOf('—');
    if (i >= 0) return label.substring(i + 1).trim();
    final j = label.indexOf('(');
    return j >= 0 ? label.substring(j) : '';
  }

  Widget _optionTile(Map o, bool selected, VoidCallback onTap) {
    final ch = o['char'] == null ? null : characterDefs[o['char']];
    return Material(
      color: selected ? Pal.brass.withValues(alpha: 0.25) : Pal.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? Pal.brass : Colors.transparent, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(ch != null ? Icons.person : Icons.radio_button_checked,
                  color: selected ? Pal.brass : Pal.sand, size: ch != null ? 30 : 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${o['label']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (o['sub'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('${o['sub']}', style: const TextStyle(fontSize: 13, color: Pal.sand)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // конец партии, журнал, выход
  // ------------------------------------------------------------------

  Widget _gameOver(Map result) {
    final winners = (result['winners'] as List).cast<int>();
    final iWon = winners.contains(me);
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Pal.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Pal.brass, width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(iWon ? Icons.emoji_events : Icons.sentiment_dissatisfied, color: Pal.brass, size: 56),
              const SizedBox(height: 8),
              Text(iWon ? 'Победа!' : 'Поражение',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Pal.brass)),
              const SizedBox(height: 6),
              Text('${result['text']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              for (final p in players)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(roleIcon(Role.values[p['role'] as int]), color: roleColor(Role.values[p['role'] as int]), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            '${p['name']} — ${Role.values[p['role'] as int].title}'
                            '${characterDefs[p['ch']] != null ? ', ${characterDefs[p['ch']]!.name}' : ''}',
                            style: TextStyle(
                                decoration: (p['alive'] as bool) ? null : TextDecoration.lineThrough)),
                      ),
                      if (winners.contains(p['id'])) const Icon(Icons.emoji_events, color: Pal.brass, size: 18),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              if (s is HostSession)
                FilledButton(
                  onPressed: () => (s as HostSession).newRound(),
                  child: const Text('Новая партия'),
                )
              else
                const Text('Хост может начать новую партию.', style: TextStyle(color: Pal.sand)),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: widget.onExit, child: const Text('Выйти в меню')),
            ],
          ),
        ),
      ),
    );
  }

  void _showLog(BuildContext context) {
    final log = (st['log'] as List).cast<String>().reversed.toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Pal.surface,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (_, ctrl) => ListView.builder(
          controller: ctrl,
          padding: const EdgeInsets.all(16),
          itemCount: log.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(log[i], style: TextStyle(fontWeight: log[i].startsWith('—') ? FontWeight.w800 : null)),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из партии?'),
        content: Text(s.isHost
            ? 'Вы хост: партия закончится для всех игроков.'
            : 'Пока вас нет, за вас будет играть бот. Вернуться можно, снова подключившись к столу.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok == true) widget.onExit();
  }
}
