// Прогоняет сотни партий со случайными ответами игроков и проверяет,
// что движок не падает, не зависает и не теряет карты.
// Запуск: flutter test

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pylny_gorod/engine/bot.dart';
import 'package:pylny_gorod/engine/game.dart';

Json _randomAnswer(Random rng, Json req) {
  if (req['type'] == 'turn') {
    final options = <Json>[];
    for (final p in req['plays'] as List) {
      options.add({'action': 'play', 'card': p['card'], 'targets': p['targets']});
    }
    for (final p in req['acts'] as List) {
      options.add({'action': 'act', 'card': p['card'], 'targets': p['targets']});
    }
    for (final p in req['abilities'] as List) {
      options.add({'action': 'ability', 'id': p['id'], 'targets': p['targets']});
    }
    if (options.isEmpty || rng.nextDouble() < 0.15) return {'action': 'end'};
    final o = Map<String, dynamic>.from(options[rng.nextInt(options.length)]);
    final ts = o.remove('targets') as List?;
    if (ts != null && ts.isNotEmpty) o['target'] = ts[rng.nextInt(ts.length)];
    return o;
  }
  final opts = (req['options'] as List).map((o) => o['id']).toList()..shuffle(rng);
  final min = req['min'] as int, max = req['max'] as int;
  var n = min == max ? min : min + rng.nextInt(max - min + 1);
  if (min == 0 && opts.isNotEmpty && rng.nextDouble() < 0.7) n = 1;
  return {'choice': opts.take(n).toList()};
}

void main() {
  test('случайные партии завершаются без ошибок', () async {
    for (var seed = 0; seed < 400; seed++) {
      final rng = Random(seed);
      final expansion = seed.isOdd;
      final n = 4 + seed % (expansion ? 5 : 4);
      final players = [for (var i = 0; i < n; i++) Player(i, 'P$i')];
      late Game g;
      var changes = 0;
      g = Game(
        players: players,
        expansion: expansion,
        rng: Random(seed * 7 + 1),
        ask: (pid, req) async {
          await Future<void>.delayed(Duration.zero); // отдаём управление таймерам, чтобы сработал timeout
          return _randomAnswer(rng, req);
        },
        onChange: () {
          changes++;
          if (g.totalCards > 0) expect(g.countCards(), g.totalCards, reason: 'seed $seed');
          for (final p in g.players) {
            if (p.alive) {
              expect(p.hp <= p.maxHp, isTrue, reason: 'seed $seed');
            } else {
              expect(p.hand.isEmpty && p.table.isEmpty, isTrue, reason: 'seed $seed');
            }
          }
        },
      );
      final result = await g.run().timeout(const Duration(seconds: 20));
      expect(result.winners, isNotEmpty, reason: 'seed $seed');
      expect(changes, greaterThan(0));
    }
  }, timeout: const Timeout(Duration(minutes: 5))); // 400 партий могут не уложиться в 30 с по умолчанию

  test('партии одних ботов завершаются, и у каждой стороны есть победы', () async {
    final wins = <String, int>{};
    for (var seed = 0; seed < 200; seed++) {
      final expansion = seed.isOdd;
      final n = 4 + seed % (expansion ? 5 : 4);
      final players = [for (var i = 0; i < n; i++) Player(i, 'B$i')];
      final rng = Random(seed);
      late Game g;
      g = Game(
        players: players,
        expansion: expansion,
        rng: Random(seed * 13 + 5),
        ask: (pid, req) async {
          await Future<void>.delayed(Duration.zero);
          final r = BotBrain.decide(g.viewFor(pid), req, rng);
          expect(g.turnNo < 2000, isTrue, reason: 'слишком длинная партия, seed $seed');
          return r;
        },
        onChange: () {
          if (g.totalCards > 0) expect(g.countCards(), g.totalCards, reason: 'seed $seed');
        },
      );
      final result = await g.run().timeout(const Duration(seconds: 30));
      final key = result.text.contains('бандиты')
          ? 'бандиты'
          : result.text.contains('одиночка')
              ? 'одиночка'
              : 'закон';
      wins[key] = (wins[key] ?? 0) + 1;
    }
    // ignore: avoid_print
    print('Победы ботов: $wins');
    expect(wins['закон'] ?? 0, greaterThan(0));
    expect(wins['бандиты'] ?? 0, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
