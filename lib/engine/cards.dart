// Карты игры «Пыльный город».
// Механики вдохновлены классическими вестерн-дуэлями: названия, тексты и
// оформление — собственные.

import 'dart:math';

enum Suit { spades, hearts, diamonds, clubs }

extension SuitX on Suit {
  String get symbol => const ['♠', '♥', '♦', '♣'][index];
  bool get isRed => this == Suit.hearts || this == Suit.diamonds;
}

String rankLabel(int r) {
  switch (r) {
    case 1:
      return 'A';
    case 11:
      return 'J';
    case 12:
      return 'Q';
    case 13:
      return 'K';
    default:
      return '$r';
  }
}

/// brown — разыгрывается и сразу уходит в сброс;
/// blue — выкладывается перед собой и действует постоянно;
/// green — выкладывается перед собой, со следующего хода её можно сбросить ради эффекта.
enum CardColor { brown, blue, green }

enum Eff {
  shot, // выстрел
  missed, // промах
  dodge, // промах + взять карту
  heal, // лечит себя
  healAny, // лечит любого игрока
  healAll, // лечит всех
  draw, // взять N карт
  store, // ярмарка
  steal, // забрать карту
  discardTarget, // сбросить карту игрока
  duel,
  gatling,
  indians,
  brawl,
  weapon,
  horse,
  scope,
  barrel,
  dynamite,
  jail,
}

/// Дистанция действия карты.
enum Reach { none, weapon, one, any }

class CardDef {
  final String key;
  final String name;
  final String text;
  final CardColor color;
  final Eff eff;
  final int value; // дальность оружия / сила лечения / сколько карт взять
  final Reach reach;
  final bool countsBang; // тратит лимит выстрелов за ход
  final bool extraCost; // нужно сбросить ещё одну карту с руки
  final bool expansion;

  const CardDef(
    this.key,
    this.name,
    this.text,
    this.color,
    this.eff, {
    this.value = 0,
    this.reach = Reach.none,
    this.countsBang = false,
    this.extraCost = false,
    this.expansion = false,
  });

  bool get isMissedLike => eff == Eff.missed || eff == Eff.dodge;
  bool get isShotCard => key == 'vystrel';
}

const List<CardDef> allCardDefs = [
  // ---------- базовый набор: коричневые ----------
  CardDef('vystrel', 'Выстрел', 'Выстрелите в игрока в пределах дальности оружия. Один выстрел за ход.',
      CardColor.brown, Eff.shot, reach: Reach.weapon, countsBang: true),
  CardDef('promah', 'Промах', 'Отменяет попадание по вам.', CardColor.brown, Eff.missed),
  CardDef('nastoyka', 'Настойка', 'Восстановите 1 жизнь. Не действует, когда в живых двое.',
      CardColor.brown, Eff.heal, value: 1),
  CardDef('kabak', 'Кабак', 'Все живые игроки восстанавливают по 1 жизни.', CardColor.brown, Eff.healAll,
      value: 1),
  CardDef('dilizhans', 'Дилижанс', 'Возьмите 2 карты.', CardColor.brown, Eff.draw, value: 2),
  CardDef('seyf', 'Сейф', 'Возьмите 3 карты.', CardColor.brown, Eff.draw, value: 3),
  CardDef('yarmarka', 'Ярмарка', 'Откройте по карте на каждого живого игрока. По кругу каждый берёт одну.',
      CardColor.brown, Eff.store),
  CardDef('karmannik', 'Карманник', 'Заберите карту у игрока на расстоянии 1.', CardColor.brown, Eff.steal,
      reach: Reach.one),
  CardDef('pogrom', 'Погром', 'Сбросьте любую карту любого игрока.', CardColor.brown, Eff.discardTarget,
      reach: Reach.any),
  CardDef('duel', 'Дуэль', 'Соперник и вы по очереди сбрасываете «Выстрел». Кто не смог — теряет 1 жизнь.',
      CardColor.brown, Eff.duel, reach: Reach.any),
  CardDef('pulemet', 'Пулемёт', 'Выстрел по всем остальным игрокам.', CardColor.brown, Eff.gatling),
  CardDef('nabeg', 'Набег', 'Каждый другой игрок сбрасывает «Выстрел» или теряет 1 жизнь.', CardColor.brown,
      Eff.indians),
  // ---------- базовый набор: синие ----------
  CardDef('ukrytie', 'Укрытие', 'Когда в вас стреляют, проверьте карту: ♥ — промах.', CardColor.blue, Eff.barrel),
  CardDef('dinamit', 'Динамит', 'В начале хода проверьте: ♠2–9 — взрыв, −3 жизни. Иначе передайте дальше.',
      CardColor.blue, Eff.dynamite),
  CardDef('tyurma', 'Тюрьма', 'Положите на другого игрока (не шерифа). В начале хода: ♥ — освобождён, иначе пропуск.',
      CardColor.blue, Eff.jail, reach: Reach.any),
  CardDef('skakun', 'Скакун', 'Другие видят вас на 1 дальше.', CardColor.blue, Eff.horse, value: 1),
  CardDef('truba', 'Подзорная труба', 'Вы видите других на 1 ближе.', CardColor.blue, Eff.scope, value: 1),
  CardDef('skorostrel', 'Скорострел', 'Оружие, дальность 1. Сколько угодно выстрелов за ход.', CardColor.blue,
      Eff.weapon, value: 1),
  CardDef('revolver', 'Револьвер', 'Оружие, дальность 2.', CardColor.blue, Eff.weapon, value: 2),
  CardDef('karabin', 'Карабин', 'Оружие, дальность 3.', CardColor.blue, Eff.weapon, value: 3),
  CardDef('dlinnostvol', 'Длинноствол', 'Оружие, дальность 4.', CardColor.blue, Eff.weapon, value: 4),
  CardDef('dalnoboy', 'Дальнобой', 'Оружие, дальность 5.', CardColor.blue, Eff.weapon, value: 5),

  // ---------- дополнение «Новые рубежи»: коричневые ----------
  CardDef('draka', 'Драка', 'Сбросьте ещё карту: каждый другой игрок теряет карту на ваш выбор.',
      CardColor.brown, Eff.brawl, extraCost: true, expansion: true),
  CardDef('nyrok', 'Нырок', 'Промах, после которого вы берёте карту.', CardColor.brown, Eff.dodge,
      expansion: true),
  CardDef('udar', 'Удар', 'Выстрел на расстоянии 1. Не тратит лимит.', CardColor.brown, Eff.shot,
      reach: Reach.one, expansion: true),
  CardDef('regtaym', 'Рэгтайм', 'Сбросьте ещё карту: заберите карту у любого игрока.', CardColor.brown,
      Eff.steal, reach: Reach.any, extraCost: true, expansion: true),
  CardDef('ruzhyo', 'Охотничье ружьё', 'Сбросьте ещё карту: выстрел на любое расстояние. Не тратит лимит.',
      CardColor.brown, Eff.shot, reach: Reach.any, extraCost: true, expansion: true),
  CardDef('tekila', 'Текила', 'Сбросьте ещё карту: любой игрок восстанавливает 1 жизнь.', CardColor.brown,
      Eff.healAny, value: 1, extraCost: true, expansion: true),
  CardDef('viski', 'Виски', 'Сбросьте ещё карту: восстановите 2 жизни.', CardColor.brown, Eff.heal,
      value: 2, extraCost: true, expansion: true),
  // ---------- дополнение: синие ----------
  CardDef('binokl', 'Бинокль', 'Вы видите других на 1 ближе.', CardColor.blue, Eff.scope, value: 1,
      expansion: true),
  CardDef('taynik', 'Тайник', 'Другие видят вас на 1 дальше.', CardColor.blue, Eff.horse, value: 1,
      expansion: true),
  // ---------- дополнение: зелёные ----------
  CardDef('derrindzher', 'Дерринджер', 'Сбросьте: выстрел на расстоянии 1 и возьмите карту.', CardColor.green,
      Eff.shot, reach: Reach.one, value: 1, expansion: true),
  CardDef('gaubitsa', 'Гаубица', 'Сбросьте: выстрел по всем остальным.', CardColor.green, Eff.gatling,
      expansion: true),
  CardDef('perechnitsa', 'Перечница', 'Сбросьте: выстрел в пределах дальности оружия.', CardColor.green,
      Eff.shot, reach: Reach.weapon, expansion: true),
  CardDef('bizonya', 'Бизонья винтовка', 'Сбросьте: выстрел на любое расстояние.', CardColor.green, Eff.shot,
      reach: Reach.any, expansion: true),
  CardDef('nozh', 'Нож', 'Сбросьте: выстрел на расстоянии 1.', CardColor.green, Eff.shot, reach: Reach.one,
      expansion: true),
  CardDef('plastina', 'Железная пластина', 'Сбросьте, когда в вас стреляют: промах.', CardColor.green,
      Eff.missed, expansion: true),
  CardDef('bibliya', 'Библия', 'Сбросьте, когда в вас стреляют: промах и возьмите карту.', CardColor.green,
      Eff.dodge, expansion: true),
  CardDef('shlyapa', 'Широкополая шляпа', 'Сбросьте, когда в вас стреляют: промах.', CardColor.green,
      Eff.missed, expansion: true),
  CardDef('sombrero', 'Сомбреро', 'Сбросьте, когда в вас стреляют: промах.', CardColor.green, Eff.missed,
      expansion: true),
  CardDef('flyazhka', 'Фляжка', 'Сбросьте: восстановите 1 жизнь.', CardColor.green, Eff.heal, value: 1,
      expansion: true),
  CardDef('furgon', 'Фургон', 'Сбросьте: заберите карту у любого игрока.', CardColor.green, Eff.steal,
      reach: Reach.any, expansion: true),
  CardDef('kankan', 'Канкан', 'Сбросьте: сбросьте любую карту любого игрока.', CardColor.green,
      Eff.discardTarget, reach: Reach.any, expansion: true),
  CardDef('poni', 'Пони-экспресс', 'Сбросьте: возьмите 3 карты.', CardColor.green, Eff.draw, value: 3,
      expansion: true),
];

final Map<String, CardDef> cardDefs = {for (final d in allCardDefs) d.key: d};

/// Сколько копий каждой карты в колоде.
const Map<String, int> baseCounts = {
  'vystrel': 25,
  'promah': 12,
  'nastoyka': 6,
  'kabak': 1,
  'dilizhans': 2,
  'seyf': 1,
  'yarmarka': 2,
  'karmannik': 4,
  'pogrom': 4,
  'duel': 3,
  'pulemet': 1,
  'nabeg': 2,
  'ukrytie': 2,
  'dinamit': 1,
  'tyurma': 3,
  'skakun': 2,
  'truba': 1,
  'skorostrel': 2,
  'revolver': 3,
  'karabin': 1,
  'dlinnostvol': 1,
  'dalnoboy': 1,
};

const Map<String, int> expansionCounts = {
  'vystrel': 3,
  'promah': 2,
  'nastoyka': 1,
  'duel': 1,
  'pogrom': 1,
  'draka': 1,
  'nyrok': 2,
  'udar': 1,
  'regtaym': 1,
  'ruzhyo': 1,
  'tekila': 1,
  'viski': 1,
  'binokl': 1,
  'taynik': 1,
  'derrindzher': 1,
  'gaubitsa': 1,
  'perechnitsa': 1,
  'bizonya': 1,
  'nozh': 1,
  'plastina': 2,
  'bibliya': 1,
  'shlyapa': 1,
  'sombrero': 1,
  'flyazhka': 1,
  'furgon': 1,
  'kankan': 1,
  'poni': 1,
};

class GameCard {
  final int id;
  final String key;
  final Suit suit;
  final int rank;

  /// Номер хода, в который зелёная карта была выложена.
  int playedTurn = -1;

  GameCard(this.id, this.key, this.suit, this.rank);

  CardDef get def => cardDefs[key]!;
  String get name => def.name;
  String get label => '${def.name} ${rankLabel(rank)}${suit.symbol}';

  Map<String, dynamic> toJson() => {'id': id, 'k': key, 's': suit.index, 'r': rank};
}

/// Собирает колоду. Масти и номиналы раздаются детерминированно, так что у
/// каждой копии карты свой номинал, и вероятности проверок близки к 1/4 на масть.
List<GameCard> buildDeck({required bool expansion}) {
  final entries = <String>[];
  baseCounts.forEach((k, n) => entries.addAll(List.filled(n, k)));
  if (expansion) expansionCounts.forEach((k, n) => entries.addAll(List.filled(n, k)));
  final faces = <List<int>>[];
  for (var s = 0; s < 4; s++) {
    for (var r = 1; r <= 13; r++) {
      faces.add([s, r]);
    }
  }
  final rng = Random(1849); // фиксированное зерно: колода всегда одинаковая
  final pool = <List<int>>[];
  final cards = <GameCard>[];
  for (var i = 0; i < entries.length; i++) {
    if (pool.isEmpty) {
      pool.addAll(faces);
      pool.shuffle(rng);
    }
    final f = pool.removeLast();
    cards.add(GameCard(i, entries[i], Suit.values[f[0]], f[1]));
  }
  return cards;
}
