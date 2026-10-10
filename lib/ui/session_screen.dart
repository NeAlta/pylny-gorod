import 'package:flutter/material.dart';

import '../net/session.dart';
import 'game_view.dart';
import 'theme.dart';

/// Экран стола: лобби до начала партии, игровой стол во время партии.
class SessionScreen extends StatefulWidget {
  final GameSession session;
  const SessionScreen({super.key, required this.session});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  GameSession get s => widget.session;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    s.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(_onChange);
    if (!_leaving) s.close();
    s.dispose();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await s.close();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (s.fatal != null) return _fatal(s.fatal!);
    if (s.state != null) return GameView(session: s, onExit: _leave);
    return _lobby();
  }

  Widget _fatal(String text) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_off, size: 56, color: Pal.blood),
                  const SizedBox(height: 12),
                  Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _leave, child: const Text('В меню')),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _lobby() {
    final lobby = s.lobby;
    final players = ((lobby?['players'] as List?) ?? const []).cast<Map>();
    final host = s is HostSession ? s as HostSession : null;
    final expansion = lobby?['expansion'] == true;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(host != null ? 'Ваш стол' : 'Стол: ${lobby?['host'] ?? '…'}'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _leave),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (s.status != null)
                Container(
                  width: double.infinity,
                  color: Pal.blood,
                  padding: const EdgeInsets.all(8),
                  child: Text(s.status!, style: const TextStyle(color: Colors.white)),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (host != null) _hostInfo(host),
                    Text('Игроки: ${players.length}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (final p in players)
                      Card(
                        color: Pal.surface,
                        child: ListTile(
                          leading: Icon(
                            p['id'] == 0
                                ? Icons.star
                                : p['bot'] == true
                                    ? Icons.smart_toy
                                    : Icons.person,
                            color: p['connected'] == true ? Pal.brass : Pal.sand,
                          ),
                          title: Text('${p['name']}${p['id'] == s.myId ? ' (вы)' : ''}'),
                          subtitle: p['id'] == 0
                              ? const Text('хост', style: TextStyle(color: Pal.sand))
                              : p['bot'] == true
                                  ? const Text('бот', style: TextStyle(color: Pal.sand))
                                  : null,
                          trailing: host != null && p['bot'] == true
                              ? IconButton(
                                  tooltip: 'Убрать бота',
                                  icon: const Icon(Icons.close, color: Pal.sand),
                                  onPressed: () => host.removeBot(p['id'] as int),
                                )
                              : null,
                        ),
                      ),
                    if (host != null && host.canAddBot)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: OutlinedButton.icon(
                          onPressed: host.addBot,
                          icon: const Icon(Icons.smart_toy),
                          label: const Text('Добавить бота'),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (host != null)
                      SwitchListTile(
                        value: expansion,
                        onChanged: host.setExpansion,
                        title: const Text('Дополнение «Новые рубежи»'),
                        subtitle: const Text('14 персонажей, зелёные карты, игра до 8 человек',
                            style: TextStyle(color: Pal.sand)),
                      )
                    else
                      ListTile(
                        leading: Icon(expansion ? Icons.check_circle : Icons.circle_outlined, color: Pal.brass),
                        title: Text(expansion ? 'С дополнением «Новые рубежи»' : 'Базовая игра'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: host != null
                    ? SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: host.canStart ? host.startGame : null,
                          child: Text(host.canStart
                              ? 'Начать партию'
                              : 'Нужно от 4 до ${host.maxPlayers} игроков'),
                        ),
                      )
                    : const Text('Ждём, пока хост начнёт партию…', style: TextStyle(color: Pal.sand)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hostInfo(HostSession host) {
    final addrs = host.addresses;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Pal.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pal.brass.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Как подключиться', style: TextStyle(fontWeight: FontWeight.w800, color: Pal.brass)),
          const SizedBox(height: 6),
          const Text('Друзья в той же Wi-Fi сети нажимают «Присоединиться» — стол появится в списке. '
              'Если не появился, пусть введут адрес:'),
          const SizedBox(height: 8),
          if (addrs.isEmpty)
            const Text('Адрес не найден. Подключитесь к Wi-Fi или включите точку доступа.',
                style: TextStyle(color: Pal.blood))
          else
            for (final a in addrs)
              SelectableText(a, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
