import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guis/core/api.dart';
import 'package:guis/core/model/models.dart';
import 'package:guis/core/services.dart';
import 'package:guis/features/auth/sign_in_page.dart';
import 'package:guis/features/fields/field_page.dart';
import 'package:guis/features/producers/producer_page.dart';
import 'package:guis/features/producers/producers_page.dart';
import 'package:guis/ui/theme.dart';

import 'fake_server.dart';

/// Les écrans s'affichent sans débordement sur un petit téléphone Android (360 × 640), et le
/// parcours de saisie d'un producteur fonctionne de bout en bout jusqu'à la file d'envoi.
/// (Démarche reprise de Fieldproof, apps/agent/test/screens_test.dart.)
void main() {
  late FakeServer server;
  late AppServices services;

  Widget app(Widget home) => MaterialApp(
    theme: guisTheme(),
    locale: const Locale('fr'),
    supportedLocales: const [Locale('fr')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: home,
  );

  /// Fait défiler la fiche jusqu'à l'élément (la liste ne construit que ce qui est proche de l'écran).
  Future<void> reveal(WidgetTester tester, Key key) => tester.scrollUntilVisible(
    find.byKey(key),
    200,
    scrollable: find.descendant(of: find.byKey(const Key('producer-form')), matching: find.byType(Scrollable)).first,
  );

  Future<void> setUpServices(WidgetTester tester, {bool signIn = true}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    server = FakeServer();
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('screens');
      services = await AppServices.open(dir, Api('https://guis.test', client: server.client));
      services.syncAfterSave = false;
      services.autoSyncEnabled = false;
      if (signIn) await services.signIn('770000001', 'motdepasse');
    });
  }

  testWidgets('connexion', (tester) async {
    await setUpServices(tester, signIn: false);
    await tester.pumpWidget(app(SignInPage(services: services)));
    expect(find.text('Numéro de téléphone'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('phone')), '77 000 00 01');
    await tester.enterText(find.byKey(const Key('password')), 'faux');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('sign-in')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('Numéro ou mot de passe incorrect.'), findsOneWidget);
  });

  testWidgets('nouveau producteur : consentement obligatoire, semence, puis file d\'envoi', (tester) async {
    await setUpServices(tester);
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun producteur'), findsOneWidget);

    await tester.tap(find.byKey(const Key('new-producer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('last-name')), 'Diop');
    await tester.enterText(find.byKey(const Key('first-name')), 'Awa');
    await tester.enterText(find.byKey(const Key('phone')), '77 123 45 67');
    await tester.enterText(find.byKey(const Key('village')), 'vill');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Village A')); // choix proposé par la liste du serveur
    await tester.pumpAndSettle();

    // Sans consentement : refus.
    await reveal(tester, const Key('save-producer'));
    await tester.tap(find.byKey(const Key('save-producer')));
    await tester.pump();
    expect(find.textContaining('Cochez le consentement'), findsOneWidget);
    expect(services.producers, isEmpty);
    // L'agent ferme le message, qui libère le bas de l'écran.
    ScaffoldMessenger.of(tester.element(find.byKey(const Key('save-producer')))).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await reveal(tester, const Key('consent'));
    await tester.tap(find.byKey(const Key('consent')));
    await tester.pump();

    await reveal(tester, const Key('add-seed'));
    await tester.tap(find.byKey(const Key('add-seed')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quantity')), '50');
    await tester.tap(find.byKey(const Key('save-seed')));
    await tester.pumpAndSettle();
    expect(find.text('Spunta — 50 kg'), findsOneWidget, reason: 'variété unique proposée par défaut');

    await reveal(tester, const Key('save-producer'));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('save-producer')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final p = services.producers.values.single;
    expect((p.fullName, p.village, p.seeds.single.quantityKg), ('Awa DIOP', 'Village A', 50));
    expect(p.consentAt, isNotNull);
    expect(services.pendingCount, 1);
    expect(find.text('Awa DIOP'), findsOneWidget);
    expect(find.text('À envoyer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('producteur importé : consentement à recueillir, fiche sans débordement', (tester) async {
    await setUpServices(tester);
    services.producers['imp'] = const Producer(
      id: 'imp',
      lastName: 'Fall',
      firstName: 'Ibou',
      village: 'Village A',
      memberCard: 'CM-9',
      source: 'import',
    );
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    expect(find.text('Consentement à recueillir'), findsOneWidget);
    await tester.tap(find.text('Ibou FALL'));
    await tester.pumpAndSettle();
    expect(find.text(consentText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fiche champ : surface mesurée, écart avec la surface déclarée, sans débordement', (tester) async {
    await setUpServices(tester);
    final p = const Producer(id: 'p1', lastName: 'Diop', firstName: 'Awa');
    services.producers['p1'] = p;
    final contour = [
      for (final (lat, lng) in [(15.0500, -16.9500), (15.0500, -16.9490), (15.0490, -16.9490), (15.0490, -16.9500)])
        GpsPoint(lat: lat, lng: lng, accuracyM: 4, capturedAt: DateTime.utc(2026, 11, 23)),
    ];
    final f = Field(id: 'f1', producerId: 'p1', name: 'Champ du puits', contour: contour, areaDeclaredHa: 1.5, sownOn: '2026-11-15');
    await tester.pumpWidget(app(FieldPage(services: services, producer: p, field: f)));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 sommets · surface mesurée 1,19 ha'), findsOneWidget);
    expect(find.textContaining('Écart avec la surface mesurée : -21 %'), findsOneWidget);
    expect(find.text('15/11/2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nouveau champ sans contour depuis un nouveau producteur : le producteur est enregistré d\'abord', (tester) async {
    await setUpServices(tester);
    await tester.pumpWidget(app(ProducerPage(services: services)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('last-name')), 'Ndiaye');
    await tester.enterText(find.byKey(const Key('first-name')), 'Moussa');
    await reveal(tester, const Key('consent'));
    await tester.tap(find.byKey(const Key('consent')));
    await tester.pump();
    await reveal(tester, const Key('add-field'));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('add-field')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(services.producers.values.single.fullName, 'Moussa NDIAYE');
    expect(find.text('Nouveau champ'), findsOneWidget);
    expect(find.text('Pas encore de contour.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-field')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('save-field')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final field = services.fields.values.single;
    expect((field.name, field.contour.length, field.sownOn != null), ('Champ 1', 0, true));
    expect(services.pending.map((e) => e.path.split('/')[3]), ['producers', 'fields']);
    expect(find.text('Champ 1'), findsOneWidget, reason: 'le champ apparaît dans la fiche du producteur');
    expect(tester.takeException(), isNull);
  });
}
