// Captures des écrans pour les comparer aux maquettes (docs/design/android) :
//   flutter test --tags captures test/captures_test.dart
// Les PNG sont écrits dans build/captures/ (hors du dépôt). Ignoré par `flutter test` sans --tags.
@Tags(['captures'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guis/core/api.dart';
import 'package:guis/core/model/models.dart';
import 'package:guis/core/services.dart';
import 'package:guis/features/auth/sign_in_page.dart';
import 'package:guis/features/fields/field_page.dart';
import 'package:guis/features/fields/field_walk_page.dart';
import 'package:guis/features/producers/producer_page.dart';
import 'package:guis/features/producers/producers_page.dart';
import 'package:guis/ui/theme.dart';

import 'fake_server.dart';

final _boundary = GlobalKey();

Widget _app(Widget home) => RepaintBoundary(
  key: _boundary,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: guisTheme(),
    locale: const Locale('fr'),
    supportedLocales: const [Locale('fr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  ),
);

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/captures/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

List<GpsPoint> _square(double lat, double lng, double side) {
  final d = side / 111320 / 2;
  return [
    for (final (a, b) in [(lat + d, lng - d), (lat + d * 1.1, lng + d), (lat - d, lng + d * 0.9), (lat - d * 0.9, lng - d)])
      GpsPoint(lat: a, lng: b, accuracyM: 4, capturedAt: DateTime.utc(2026, 11, 23)),
  ];
}

void main() {
  late AppServices s;
  late FakeServer server;

  setUp(() {});

  Future<void> seed(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    server = FakeServer()
      ..villages = ['Village A', 'Village B', 'Village C', 'Village D']
      ..rejectLastNames.add('FALL');
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('captures');
      s = await AppServices.open(dir, Api('https://guis.test', client: server.client));
      s.syncAfterSave = false;
      s.autoSyncEnabled = false;
      await s.signIn('770000001', 'motdepasse');
      final ibou = Producer(
        id: newId(),
        lastName: 'FALL',
        firstName: 'Ibou',
        phone: '221708123319',
        memberCard: '0127',
        village: 'Village A',
        sex: 'H',
        consentAt: DateTime(2026, 11, 20),
      );
      await s.saveProducer(ibou);
      await s.sync(force: true);
      final awa = Producer(
        id: 'awa',
        lastName: 'DIOP',
        firstName: 'Awa',
        phone: '221771234567',
        memberCard: '0412',
        village: 'Village A',
        sex: 'F',
        consentAt: DateTime(2026, 11, 24, 9, 15),
        seeds: const [
          Seed(id: 's1', variety: 'Spunta', quantityKg: 50, receivedOn: '2026-11-10'),
          Seed(id: 's2', variety: 'Sahel', quantityKg: 25, receivedOn: '2026-11-18'),
        ],
      );
      await s.saveProducer(awa);
      await s.saveField(
        Field(
          id: 'f1',
          producerId: 'awa',
          name: 'Champ 1',
          contour: _square(14.9123, -17.1764, 108),
          areaDeclaredHa: 1.5,
          sownOn: '2026-11-15',
          irrigation: 'Goutte-à-goutte',
          waterSource: 'Forage',
        ),
      );
      await s.saveField(const Field(id: 'f2', producerId: 'awa', name: 'Champ 2', areaDeclaredHa: 0.8));
      s.producers['mg'] = const Producer(
        id: 'mg',
        lastName: 'GUEYE',
        firstName: 'Mariama',
        phone: '221768774326',
        memberCard: '0702',
        village: 'Village D',
        sex: 'F',
        source: 'import',
      );
      s.producers['mb'] = Producer(
        id: 'mb',
        lastName: 'BA',
        firstName: 'Mariama',
        phone: '221782306745',
        memberCard: '0291',
        village: 'Village B',
        sex: 'F',
        consentAt: DateTime(2026, 11, 2),
      );
    });
  }

  testWidgets('01 connexion', (tester) async {
    await seed(tester);
    await tester.pumpWidget(_app(SignInPage(services: s)));
    await tester.enterText(find.byKey(const Key('phone')), '77 123 45 67');
    await tester.enterText(find.byKey(const Key('password')), 'motdepasse');
    await _shot(tester, '01-connexion');
  });

  testWidgets('02 producteurs', (tester) async {
    await seed(tester);
    await tester.pumpWidget(_app(ProducersPage(services: s)));
    await _shot(tester, '02-producteurs');
  });

  testWidgets('03 fiche producteur, consultation et saisie', (tester) async {
    await seed(tester);
    await tester.pumpWidget(_app(ProducerPage(services: s, producer: s.producers['awa'])));
    await _shot(tester, '03-fiche-producteur-consultation');
    await tester.ensureVisible(find.byKey(const Key('edit-identity')));
    await tester.tap(find.byKey(const Key('edit-identity')));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('producer-form')), const Offset(0, 3000));
    await _shot(tester, '03a-fiche-producteur-saisie');
  });

  testWidgets('03b refus du serveur', (tester) async {
    await seed(tester);
    final ibou = s.producers.values.firstWhere((p) => p.lastName == 'FALL');
    await tester.pumpWidget(_app(ProducerPage(services: s, producer: ibou)));
    await _shot(tester, '03b-fiche-refus-serveur');
  });

  testWidgets('04 semence reçue', (tester) async {
    await seed(tester);
    await tester.pumpWidget(_app(ProducerPage(services: s, producer: s.producers['awa'])));
    await tester.tap(find.text('Spunta, 50 kg'));
    await _shot(tester, '04-fenetre-semence-recue');
  });

  testWidgets('05 fiche champ', (tester) async {
    await seed(tester);
    await tester.pumpWidget(_app(FieldPage(services: s, producer: s.producers['awa']!, field: s.fields['f1'])));
    await _shot(tester, '05-fiche-champ');
  });

  testWidgets('06 tour du champ', (tester) async {
    await seed(tester);
    await tester.pumpWidget(_app(FieldWalkPage(name: 'Champ 2', initial: _square(14.9123, -17.1764, 100))));
    await _shot(tester, '06-tour-du-champ');
  });
}
