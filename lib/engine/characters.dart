// Персонажи «Пыльного города». Имена и описания — собственные.

enum Ab {
  drawOnDamage,
  redBonus,
  swapShotMissed,
  takeFromAttacker,
  firstFromPlayer,
  builtinBarrel,
  pickTwoOfThree,
  luckyCheck,
  builtinHorse,
  firstFromDiscard,
  builtinScope,
  discardTwoHeal,
  doubleMissed,
  drawWhenEmpty,
  takeDeadCards,
  unlimitedShots,
  // дополнение
  immuneDiamonds,
  disableOthersCards,
  drawPerWound,
  lifeForCards,
  discardTwoShot,
  anyAsMissed,
  healOnDeath,
  drawOnDeath,
  blueForTwo,
  drawOutOfTurn,
  takeInPlay,
  drawThree,
  bigHand,
  strongHeal,
}

class CharDef {
  final String key;
  final String name;
  final int hp;
  final Ab ab;
  final String text;
  final bool expansion;
  const CharDef(this.key, this.name, this.hp, this.ab, this.text, {this.expansion = false});

  Map<String, dynamic> toJson() => {'k': key};
}

const List<CharDef> allCharacters = [
  CharDef('bobby', 'Бобби Рэй', 4, Ab.drawOnDamage, 'За каждую потерянную жизнь берёт карту из колоды.'),
  CharDef('jack', 'Джек Ривер', 4, Ab.redBonus,
      'Показывает вторую карту добора: если она ♥ или ♦, берёт ещё одну.'),
  CharDef('maggie', 'Мэгги Фокс', 4, Ab.swapShotMissed,
      'Может использовать «Выстрел» как «Промах» и наоборот.'),
  CharDef('coyote', 'Эль Койот', 3, Ab.takeFromAttacker,
      'За каждую потерянную жизнь забирает случайную карту с руки обидчика.'),
  CharDef('tanner', 'Джесс Таннер', 4, Ab.firstFromPlayer,
      'Первую карту добора может взять из руки любого игрока.'),
  CharDef('jacques', 'Жак Бурже', 4, Ab.builtinBarrel, 'Всегда будто стоит за «Укрытием».'),
  CharDef('larson', 'Карл Ларсон', 4, Ab.pickTwoOfThree,
      'На доборе смотрит 3 верхние карты, берёт 2, третью возвращает.'),
  CharDef('fortuna', 'Фортуна Ли', 4, Ab.luckyCheck, 'При проверке открывает 2 карты и выбирает нужную.'),
  CharDef('morgan', 'Тень Морган', 3, Ab.builtinHorse, 'Другие всегда видят его на 1 дальше.'),
  CharDef('miguel', 'Мигель Лора', 4, Ab.firstFromDiscard, 'Первую карту добора может взять из сброса.'),
  CharDef('rosa', 'Роза Даль', 4, Ab.builtinScope, 'Всегда видит других на 1 ближе.'),
  CharDef('silas', 'Старый Сайлас', 4, Ab.discardTwoHeal,
      'В любой момент может сбросить 2 карты, чтобы восстановить 1 жизнь.'),
  CharDef('slade', 'Мясник Слэйд', 4, Ab.doubleMissed, 'Чтобы увернуться от его «Выстрела», нужно 2 промаха.'),
  CharDef('nelly', 'Нелли Блюм', 4, Ab.drawWhenEmpty, 'Как только рука пустеет, берёт карту.'),
  CharDef('grey', 'Гробовщик Грей', 4, Ab.takeDeadCards, 'Забирает себе все карты выбывших игроков.'),
  CharDef('teddy', 'Малыш Тедди', 4, Ab.unlimitedShots, 'Может стрелять сколько угодно раз за ход.'),
  // ---------- дополнение «Новые рубежи» ----------
  CharDef('sokol', 'Сокол', 3, Ab.immuneDiamonds, 'Карты ♦ других игроков на него не действуют (кроме дуэли).',
      expansion: true),
  CharDef('bella', 'Белла Стоун', 4, Ab.disableOthersCards,
      'В её ход синие и зелёные карты других игроков не действуют.',
      expansion: true),
  CharDef('bill', 'Безликий Билл', 4, Ab.drawPerWound, 'На доборе берёт 1 карту и ещё по одной за каждую рану.',
      expansion: true),
  CharDef('chuck', 'Чак Уэйд', 4, Ab.lifeForCards,
      'В свой ход может потерять 1 жизнь, чтобы взять 2 карты (не последнюю жизнь).',
      expansion: true),
  CharDef('holloway', 'Док Холлоуэй', 4, Ab.discardTwoShot,
      'Раз за ход может сбросить 2 карты как выстрел в пределах оружия (не тратит лимит).',
      expansion: true),
  CharDef('elena', 'Елена Фуэго', 3, Ab.anyAsMissed, 'Любую карту с руки может сыграть как «Промах».',
      expansion: true),
  CharDef('digger', 'Грег Копатель', 4, Ab.healOnDeath, 'Когда выбывает другой игрок, восстанавливает 2 жизни.',
      expansion: true),
  CharDef('hunter', 'Херб Охотник', 4, Ab.drawOnDeath, 'Когда выбывает другой игрок, берёт 2 карты.',
      expansion: true),
  CharDef('jose', 'Хосе Дельмар', 4, Ab.blueForTwo,
      'В свой ход может сбросить синюю карту с руки, чтобы взять 2 (до двух раз).',
      expansion: true),
  CharDef('molly', 'Молли Крейн', 4, Ab.drawOutOfTurn,
      'Каждый раз, когда тратит карту с руки не в свой ход, берёт карту.',
      expansion: true),
  CharDef('gordon', 'Пэт Гордон', 4, Ab.takeInPlay,
      'Вместо добора может забрать одну выложенную карту любого игрока.',
      expansion: true),
  CharDef('pete', 'Шустрый Пит', 3, Ab.drawThree, 'На доборе берёт 3 карты.', expansion: true),
  CharDef('douglas', 'Шон Дуглас', 3, Ab.bigHand, 'Может держать до 10 карт в руке.', expansion: true),
  CharDef('mezcal', 'Хуан Мескаль', 4, Ab.strongHeal, '«Настойка» лечит его на 2 жизни.', expansion: true),
];

final Map<String, CharDef> characterDefs = {for (final c in allCharacters) c.key: c};

enum Role { sheriff, deputy, outlaw, renegade }

extension RoleX on Role {
  String get title => const ['Шериф', 'Помощник', 'Бандит', 'Одиночка'][index];
  String get goal => const [
        'Уничтожить всех бандитов и одиночку.',
        'Защитить шерифа и уничтожить его врагов.',
        'Убить шерифа.',
        'Остаться последним в живых.',
      ][index];
}

List<Role> rolesFor(int n) {
  const s = Role.sheriff, d = Role.deputy, o = Role.outlaw, r = Role.renegade;
  switch (n) {
    case 4:
      return [s, r, o, o];
    case 5:
      return [s, r, o, o, d];
    case 6:
      return [s, r, o, o, o, d];
    case 7:
      return [s, r, o, o, o, d, d];
    case 8:
      return [s, r, r, o, o, o, d, d];
    default:
      throw ArgumentError('Нужно от 4 до 8 игроков');
  }
}
