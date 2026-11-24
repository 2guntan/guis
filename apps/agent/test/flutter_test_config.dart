import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les tests d'écran chargent les vraies polices de l'app (Fraunces, Geist) et les icônes Material :
/// les débordements se jugent sur le rendu réel, pas sur la police de test de Flutter.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Fraunces', ['assets/fonts/Fraunces-SemiBold.ttf']);
  await load('Geist', ['assets/fonts/Geist-Regular.ttf', 'assets/fonts/Geist-Medium.ttf', 'assets/fonts/Geist-SemiBold.ttf']);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
  await testMain();
}
