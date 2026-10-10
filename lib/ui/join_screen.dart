import 'package:flutter/material.dart';

import '../net/discovery.dart';
import '../net/session.dart';
import '../prefs.dart';
import 'session_screen.dart';
import 'theme.dart';

class JoinScreen extends StatefulWidget {
  final String name;
  const JoinScreen({super.key, required this.name});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _finder = TableFinder();
  final _ip = TextEditingController(text: Prefs.lastIp);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _finder.addListener(_onFound);
    _finder.start();
  }

  void _onFound() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _finder.removeListener(_onFound);
    _finder.dispose();
    super.dispose();
  }

  Future<void> _connect(String address) async {
    // цифровая клавиатура iOS в русской локали ставит запятую вместо точки
    address = address.trim().replaceAll(',', '.');
    if (address.isEmpty) return;
    setState(() => _busy = true);
    final s = ClientSession(address: address, myName: widget.name, token: Prefs.token);
    try {
      await s.connect();
      Prefs.lastIp = address;
      await _finder.stop();
      if (!mounted) {
        await s.close(); // экран закрыли, пока шло подключение
        return;
      }
      await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SessionScreen(session: s)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Не удалось подключиться к $address. Проверьте, что вы в одной Wi-Fi сети.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tables = _finder.tables;
    return Scaffold(
      appBar: AppBar(title: const Text('Присоединиться')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Столы рядом', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (tables.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Pal.surface, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _finder.error ?? 'Ищем столы в вашей сети…',
                        style: const TextStyle(color: Pal.sand),
                      ),
                    ),
                  ],
                ),
              ),
            for (final t in tables)
              Card(
                color: Pal.surface,
                child: ListTile(
                  leading: const Icon(Icons.table_restaurant, color: Pal.brass),
                  title: Text(t.name),
                  subtitle: Text(t.address, style: const TextStyle(color: Pal.sand)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _connect(t.address),
                ),
              ),
            const SizedBox(height: 28),
            const Text('По адресу', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Адрес показан у хоста на экране стола.', style: TextStyle(color: Pal.sand)),
            const SizedBox(height: 10),
            TextField(
              controller: _ip,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'IP-адрес хоста, например 192.168.1.5'),
              onSubmitted: _connect,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : () => _connect(_ip.text),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Подключиться'),
            ),
          ],
        ),
      ),
    );
  }
}
