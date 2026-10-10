import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prefs.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PylnyGorodApp());
}

class PylnyGorodApp extends StatelessWidget {
  const PylnyGorodApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Пыльный город',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomeScreen(),
    );
  }
}
