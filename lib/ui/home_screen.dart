import 'package:flutter/material.dart';

import '../net/session.dart';
import '../prefs.dart';
import 'join_screen.dart';
import 'rules_screen.dart';
import 'session_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController(text: Prefs.name);
  bool _busy = false;

  String? _checkName() {
    final n = _name.text.trim();
    if (n.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите имя')));
      return null;
    }
    Prefs.name = n;
    return n;
  }

  /// [bots] — сколько ботов сразу посадить за стол (для игры в одиночку).
  Future<void> _host({int bots = 0}) async {
    final n = _checkName();
    if (n == null) return;
    setState(() => _busy = true);
    final s = HostSession(n);
    try {
      await s.start();
      for (var i = 0; i < bots; i++) {
        s.addBot();
      }
      if (!mounted) {
        await s.close(); // иначе порт и объявление стола остаются занятыми
        return;
      }
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SessionScreen(session: s)));
    } catch (e) {
      await s.close();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не удалось создать стол: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _join() {
    final n = _checkName();
    if (n == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => JoinScreen(name: n)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.star, size: 72, color: Pal.brass),
                  const SizedBox(height: 8),
                  const Text(
                    'Пыльный город',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w900, color: Pal.parchment, fontFamily: 'serif'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Шериф, помощники, бандиты и одиночка.\nИгра для 4–8 человек в одной Wi-Fi сети или с ботами.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Pal.sand),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _name,
                    maxLength: 16,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Ваше имя', counterText: ''),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _host,
                    icon: const Icon(Icons.table_restaurant),
                    label: const Text('Создать стол'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _join,
                    icon: const Icon(Icons.wifi_find),
                    label: const Text('Присоединиться'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _host(bots: 4),
                    icon: const Icon(Icons.smart_toy),
                    label: const Text('Играть с ботами'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const RulesScreen())),
                    icon: const Icon(Icons.menu_book, color: Pal.sand),
                    label: const Text('Правила', style: TextStyle(color: Pal.sand)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
