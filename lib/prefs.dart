import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Имя игрока и постоянный токен (по нему хост узнаёт вас при переподключении).
class Prefs {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    if ((_p.getString('token') ?? '').isEmpty) {
      final r = Random.secure();
      final t = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
      await _p.setString('token', t);
    }
  }

  static String get name => _p.getString('name') ?? '';
  static set name(String v) => _p.setString('name', v);
  static String get token => _p.getString('token')!;
  static String get lastIp => _p.getString('lastIp') ?? '';
  static set lastIp(String v) => _p.setString('lastIp', v);
}
