import 'package:flutter/material.dart';

import '../engine/cards.dart';
import '../engine/characters.dart';

class Pal {
  static const bg = Color(0xFF21160F);
  static const surface = Color(0xFF33231A);
  static const surface2 = Color(0xFF452F21);
  static const parchment = Color(0xFFF3E4C3);
  static const parchmentDark = Color(0xFFE3CC9C);
  static const ink = Color(0xFF2B1B10);
  static const brass = Color(0xFFD9A84E);
  static const blood = Color(0xFFB8402E);
  static const sand = Color(0xFFCDB894);
  static const brownCard = Color(0xFF8A5A2B);
  static const blueCard = Color(0xFF2F5D8A);
  static const greenCard = Color(0xFF3E7A3A);
  static const ok = Color(0xFF7BB661);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Pal.brass,
      brightness: Brightness.dark,
      surface: Pal.surface,
      primary: Pal.brass,
      onPrimary: Pal.ink,
      error: Pal.blood,
    ),
    scaffoldBackgroundColor: Pal.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Pal.bg,
      foregroundColor: Pal.parchment,
      elevation: 0,
      centerTitle: false,
    ),
    textTheme: base.textTheme.apply(bodyColor: Pal.parchment, displayColor: Pal.parchment),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.brass,
        foregroundColor: Pal.ink,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pal.parchment,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: Pal.sand),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Pal.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide.none),
    ),
  );
}

Color cardColor(CardColor c) => switch (c) {
      CardColor.brown => Pal.brownCard,
      CardColor.blue => Pal.blueCard,
      CardColor.green => Pal.greenCard,
    };

String cardColorTitle(CardColor c) => switch (c) {
      CardColor.brown => 'разовая',
      CardColor.blue => 'снаряжение',
      CardColor.green => 'запас',
    };

IconData cardIcon(CardDef d) {
  switch (d.eff) {
    case Eff.shot:
      return Icons.my_location;
    case Eff.missed:
      return Icons.shield_outlined;
    case Eff.dodge:
      return Icons.directions_run;
    case Eff.heal:
    case Eff.healAny:
      return Icons.local_drink;
    case Eff.healAll:
      return Icons.local_bar;
    case Eff.draw:
      return d.value >= 3 ? Icons.savings : Icons.airport_shuttle;
    case Eff.store:
      return Icons.storefront;
    case Eff.steal:
      return Icons.back_hand;
    case Eff.discardTarget:
      return Icons.delete_sweep;
    case Eff.duel:
      return Icons.compare_arrows;
    case Eff.gatling:
      return Icons.grain;
    case Eff.indians:
      return Icons.whatshot;
    case Eff.brawl:
      return Icons.sports_mma;
    case Eff.weapon:
      return Icons.gps_fixed;
    case Eff.horse:
      return Icons.pets;
    case Eff.scope:
      return Icons.visibility;
    case Eff.barrel:
      return Icons.inventory_2;
    case Eff.dynamite:
      return Icons.local_fire_department;
    case Eff.jail:
      return Icons.grid_on;
  }
}

IconData roleIcon(Role r) => switch (r) {
      Role.sheriff => Icons.star,
      Role.deputy => Icons.local_police,
      Role.outlaw => Icons.masks,
      Role.renegade => Icons.person_outline,
    };

Color roleColor(Role r) => switch (r) {
      Role.sheriff => Pal.brass,
      Role.deputy => const Color(0xFF6FA8DC),
      Role.outlaw => Pal.blood,
      Role.renegade => const Color(0xFF9C7BC4),
    };
