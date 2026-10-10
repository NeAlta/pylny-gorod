// Создаёт папки android/ и ios/ и прописывает нужные разрешения.
// Запуск из корня проекта:  dart run tool/setup_platforms.dart

import 'dart:io';

Future<void> main() async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Запустите скрипт из корня проекта (там, где pubspec.yaml).');
    exit(1);
  }
  final hadWidgetTest = File('test/widget_test.dart').existsSync();

  stdout.writeln('1/4 flutter create…');
  final r = await Process.run(
    'flutter',
    ['create', '--platforms=android,ios', '--org', 'com.pylnygorod', '--project-name', 'pylny_gorod', '.'],
    runInShell: true,
  );
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) exit(r.exitCode);
  if (!hadWidgetTest && File('test/widget_test.dart').existsSync()) {
    File('test/widget_test.dart').deleteSync(); // шаблонный тест ссылается на несуществующий MyApp
  }

  stdout.writeln('2/4 AndroidManifest.xml…');
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  var m = manifest.readAsStringSync();
  const perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_NETWORK_STATE',
    'android.permission.ACCESS_WIFI_STATE',
    'android.permission.CHANGE_WIFI_MULTICAST_STATE',
  ];
  final add = StringBuffer();
  for (final p in perms) {
    if (!m.contains(p)) add.writeln('    <uses-permission android:name="$p" />');
  }
  if (add.isNotEmpty) m = m.replaceFirst('<application', '$add    <application');
  m = m.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Пыльный город"');
  manifest.writeAsStringSync(m);

  stdout.writeln('3/4 Info.plist…');
  final plist = File('ios/Runner/Info.plist');
  var p = plist.readAsStringSync();
  if (!p.contains('NSLocalNetworkUsageDescription')) {
    const keys = '''
	<key>NSLocalNetworkUsageDescription</key>
	<string>Нужно, чтобы найти стол и играть с друзьями в одной Wi-Fi сети.</string>
	<key>NSBonjourServices</key>
	<array>
		<string>_pylgorod._tcp</string>
	</array>
''';
    final i = p.lastIndexOf('</dict>');
    p = p.substring(0, i) + keys + p.substring(i);
  }
  p = p.replaceFirst(
    RegExp(r'<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>'),
    '<key>CFBundleDisplayName</key>\n\t<string>Пыльный город</string>',
  );
  plist.writeAsStringSync(p);

  stdout.writeln('4/4 flutter pub get и Podfile…');
  final g = await Process.run('flutter', ['pub', 'get'], runInShell: true);
  stdout.write(g.stdout);
  stderr.write(g.stderr);
  final podfile = File('ios/Podfile');
  if (podfile.existsSync()) {
    var pf = podfile.readAsStringSync();
    // Раскомментируем строку, сохраняя версию шаблона (новые Flutter ставят 15.0 — понижать нельзя).
    final re = RegExp(r"^#\s*platform :ios, '([\d.]+)'", multiLine: true);
    final m2 = re.firstMatch(pf);
    if (m2 != null) {
      final v = double.tryParse(m2.group(1)!) ?? 13.0;
      pf = pf.replaceFirst(re, "platform :ios, '${v < 13 ? '13.0' : m2.group(1)}'");
    } else if (!RegExp(r"^platform :ios", multiLine: true).hasMatch(pf)) {
      pf = "platform :ios, '13.0'\n$pf";
    }
    podfile.writeAsStringSync(pf);
  } else {
    stdout.writeln('   ios/Podfile ещё не создан — Flutter создаст его при первой сборке под iOS '
        '(минимальная версия iOS 13 уже стоит по умолчанию).');
  }

  stdout.writeln('\nГотово. Дальше: flutter pub get, затем flutter run (или flutter build apk / flutter build ipa).');
}
