import 'package:flutter/material.dart';

import '../engine/cards.dart';
import '../engine/characters.dart';
import 'theme.dart';

/// Карта, как она приходит по сети: {id, k, s, r, ready?}
class CardInfo {
  final int id;
  final CardDef def;
  final Suit suit;
  final int rank;
  final bool ready;
  CardInfo(this.id, this.def, this.suit, this.rank, this.ready);

  static CardInfo fromJson(Map j) => CardInfo(
        j['id'] as int,
        cardDefs[j['k']]!,
        Suit.values[j['s'] as int],
        j['r'] as int,
        j['ready'] as bool? ?? true,
      );

  String get face => '${rankLabel(rank)}${suit.symbol}';
}

class CardFace extends StatelessWidget {
  final CardInfo card;
  final double width;
  final bool highlight;
  final bool selected;
  final bool dim;
  final VoidCallback? onTap;

  const CardFace({
    super.key,
    required this.card,
    this.width = 76,
    this.highlight = false,
    this.selected = false,
    this.dim = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = card.def;
    final h = width * 1.45;
    final border = cardColor(d.color);
    final suitColor = card.suit.isRed ? Pal.blood : Pal.ink;
    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -10 : 0, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Pal.parchment, Pal.parchmentDark],
        ),
        borderRadius: BorderRadius.circular(width * 0.1),
        border: Border.all(color: selected ? Pal.brass : border, width: selected ? 3 : 2.5),
        boxShadow: [
          if (highlight || selected)
            BoxShadow(color: Pal.brass.withValues(alpha: 0.7), blurRadius: 10, spreadRadius: 1)
          else
            const BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      padding: EdgeInsets.all(width * 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(card.face,
                  style: TextStyle(
                      color: suitColor, fontWeight: FontWeight.w800, fontSize: width * 0.15, height: 1)),
              const Spacer(),
              Container(
                width: width * 0.12,
                height: width * 0.12,
                decoration: BoxDecoration(color: border, shape: BoxShape.circle),
              ),
            ],
          ),
          Expanded(
            child: Center(child: Icon(cardIcon(d), color: border, size: width * 0.42)),
          ),
          Text(
            d.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Pal.ink,
              fontWeight: FontWeight.w800,
              fontSize: width * 0.125,
              height: 1.1,
              fontFamily: 'serif',
            ),
          ),
          SizedBox(height: width * 0.02),
          Text(
            d.color == CardColor.green && !card.ready ? 'со след. хода' : cardColorTitle(d.color),
            textAlign: TextAlign.center,
            style: TextStyle(color: border, fontSize: width * 0.095, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: () => showCardDetails(context, card),
        child: face,
      ),
    );
  }
}

/// Небольшая плашка выложенной карты.
class TableChip extends StatelessWidget {
  final CardInfo card;
  final bool highlight;
  final VoidCallback? onTap;
  const TableChip({super.key, required this.card, this.highlight = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = cardColor(card.def.color);
    return GestureDetector(
      onTap: onTap ?? () => showCardDetails(context, card),
      onLongPress: () => showCardDetails(context, card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: card.ready ? 0.9 : 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: highlight ? Pal.brass : Colors.transparent, width: 2),
          boxShadow: highlight ? [BoxShadow(color: Pal.brass.withValues(alpha: 0.6), blurRadius: 8)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(cardIcon(card.def), size: 13, color: Colors.white),
            const SizedBox(width: 3),
            Flexible(
              child: Text(card.def.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Рубашка карты (для руки соперника, колоды).
class CardBack extends StatelessWidget {
  final double width;
  final String? label;
  const CardBack({super.key, this.width = 46, this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 1.45,
      decoration: BoxDecoration(
        color: Pal.surface2,
        borderRadius: BorderRadius.circular(width * 0.1),
        border: Border.all(color: Pal.brass, width: 2),
      ),
      alignment: Alignment.center,
      child: label == null
          ? Icon(Icons.star, color: Pal.brass, size: width * 0.45)
          : Text(label!, style: const TextStyle(color: Pal.brass, fontWeight: FontWeight.w800)),
    );
  }
}

void showCardDetails(BuildContext context, CardInfo card) {
  final d = card.def;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true,
      backgroundColor: Pal.surface,
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CardFace(card: card, width: 130),
          const SizedBox(height: 16),
          Text(d.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${card.face} · ${cardColorTitle(d.color)}', style: const TextStyle(color: Pal.sand)),
          const SizedBox(height: 10),
          Text(d.text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          if (d.color == CardColor.green) ...[
            const SizedBox(height: 8),
            const Text('Зелёную карту выкладывают перед собой; использовать её можно со следующего хода.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Pal.sand)),
          ],
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
    ),
  );
}

void showCharacterDetails(BuildContext context, CharDef ch, {String? playerName}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Pal.surface,
      title: Text(ch.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (playerName != null) Text('Игрок: $playerName', style: const TextStyle(color: Pal.sand)),
          const SizedBox(height: 6),
          Text('Жизни: ${'❤' * ch.hp}', style: const TextStyle(color: Pal.blood)),
          const SizedBox(height: 10),
          Text(ch.text, style: const TextStyle(fontSize: 15)),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
    ),
  );
}
