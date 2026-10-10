import 'package:flutter/material.dart';

import '../engine/cards.dart';
import '../engine/characters.dart';
import 'card_widget.dart';
import 'theme.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Правила'),
          bottom: const TabBar(
            indicatorColor: Pal.brass,
            labelColor: Pal.brass,
            unselectedLabelColor: Pal.sand,
            tabs: [Tab(text: 'Как играть'), Tab(text: 'Карты'), Tab(text: 'Персонажи')],
          ),
        ),
        body: const TabBarView(children: [_HowTo(), _Cards(), _Characters()]),
      ),
    );
  }
}

class _HowTo extends StatelessWidget {
  const _HowTo();

  Widget _h(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Pal.brass)),
      );
  Widget _p(String t) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(fontSize: 15, height: 1.35)));

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _h('Роли'),
        for (final r in Role.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(roleIcon(r), color: roleColor(r)),
            title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(r.goal, style: const TextStyle(color: Pal.sand)),
          ),
        _p('Роль шерифа открыта, остальные скрыты до выбывания. '
            '4 игрока: шериф, одиночка, 2 бандита. 5: + помощник. 6: + ещё бандит. 7: + ещё помощник. '
            '8 (с дополнением): + второй одиночка.'),
        _p('Если шериф погиб и последним выжил одиночка — побеждает он. Если шериф погиб иначе — побеждают бандиты.'),
        _h('Начало'),
        _p('Каждый выбирает одного из двух персонажей. Жизней столько, сколько у персонажа, у шерифа на одну больше. '
            'Карт на руке в начале — по числу жизней. Первым ходит шериф, дальше по кругу.'),
        _h('Ход'),
        _p('1. Добор: возьмите 2 карты.'),
        _p('2. Розыгрыш: играйте сколько угодно карт, но «Выстрел» — только один раз за ход '
            '(если нет «Скорострела» или особой способности). Синие и зелёные карты выкладываются перед собой; '
            'двух одинаковых выложить нельзя, оружие — только одно.'),
        _p('3. Сброс: в конце хода карт на руке должно быть не больше, чем жизней.'),
        _h('Расстояние'),
        _p('Расстояние — сколько мест между игроками по кругу в ближайшую сторону (выбывшие не считаются). '
            '«Скакун» и «Тайник» отодвигают вас от других, «Подзорная труба» и «Бинокль» приближают других к вам. '
            'Стрелять можно в того, до кого расстояние не больше дальности вашего оружия (без оружия — 1).'),
        _h('Проверка'),
        _p('Некоторые карты требуют «проверки»: открывается верхняя карта колоды, важна её масть. '
            '«Укрытие»: ♥ — промах. «Тюрьма»: ♥ — свобода. «Динамит»: ♠ от 2 до 9 — взрыв.'),
        _h('Смерть'),
        _p('При 0 жизней можно спастись «Настойкой» (если в живых больше двух). Иначе игрок выбывает и открывает роль. '
            'За убийство бандита — 3 карты. Шериф, убивший помощника, сбрасывает все свои карты.'),
        _h('Дополнение «Новые рубежи»'),
        _p('Добавляет 14 персонажей и 32 карты. Карты с пометкой «сбросьте ещё карту» требуют сбросить одну '
            'дополнительную карту с руки. Зелёные карты выкладываются перед собой и работают со следующего хода: '
            'атакующие — в ваш ход, защитные (пластина, шляпа, сомбреро, Библия) — когда в вас стреляют.'),
        _h('Боты'),
        _p('Хост может посадить ботов на свободные места кнопкой «Добавить бота» в лобби, '
            'а «Играть с ботами» сразу создаёт стол с четырьмя ботами — можно играть одному, без сети. '
            'Боты видят только то, что видел бы живой игрок, и играют за свою роль. '
            'Если игрок отключился и не вернулся за 40 секунд, за него тоже играет бот.'),
        _h('Игра по сети'),
        _p('Все телефоны должны быть в одной Wi-Fi сети, либо подключены к точке доступа одного из телефонов. '
            'Интернет не нужен. Хост нажимает «Создать стол», остальные — «Присоединиться». '
            'Если связь пропала, приложение само переподключится. Пока игрока нет, за него через 40 секунд '
            'играет бот. Хосту не стоит сворачивать приложение: телефон хоста ведёт партию.'),
        const SizedBox(height: 30),
      ],
    );
  }
}

class _Cards extends StatelessWidget {
  const _Cards();

  @override
  Widget build(BuildContext context) {
    Widget section(String title, bool exp) {
      final counts = exp ? expansionCounts : baseCounts;
      final defs = allCardDefs.where((d) => counts.containsKey(d.key)).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Pal.brass)),
          ),
          for (final d in defs)
            ListTile(
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: cardColor(d.color), borderRadius: BorderRadius.circular(8)),
                child: Icon(cardIcon(d), color: Colors.white),
              ),
              title: Text('${d.name}  ×${counts[d.key]}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${cardColorTitle(d.color)} · ${d.text}', style: const TextStyle(color: Pal.sand)),
              onTap: () => showCardDetails(context, CardInfo(-1, d, Suit.spades, 1, true)),
            ),
        ],
      );
    }

    return ListView(children: [
      section('Базовая колода (80 карт)', false),
      section('Дополнение «Новые рубежи» (+32 карты)', true),
      const SizedBox(height: 30),
    ]);
  }
}

class _Characters extends StatelessWidget {
  const _Characters();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final c in allCharacters)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: c.expansion ? Pal.greenCard : Pal.brownCard,
              child: Text('${c.hp}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            title: Text(c.name + (c.expansion ? '  · дополнение' : ''),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(c.text, style: const TextStyle(color: Pal.sand)),
          ),
      ],
    );
  }
}
