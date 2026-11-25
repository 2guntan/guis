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

  Future<void> setUpServices(WidgetTester tester, {bool signIn = true, String role = 'agent'}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    server = FakeServer();
    server.user = {...server.user, 'role': role};
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('screens');
      services = await AppServices.open(dir, Api('https://guis.test', client: server.client));
      services.syncAfterSave = false;
      services.autoSyncEnabled = false;
      if (signIn) await services.signIn('770000001', 'motdepasse');
    });
  }

  Future<void> signInWith(WidgetTester tester, String secret, {Key field = const Key('code')}) async {
    await tester.enterText(find.byKey(const Key('phone')), '77 000 00 01');
    await tester.enterText(find.byKey(field), secret);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('sign-in')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  testWidgets('connexion : champ « Code » au clavier numérique, code faux', (tester) async {
    await setUpServices(tester, signIn: false);
    await tester.pumpWidget(app(SignInPage(services: services)));
    expect(find.text('Numéro de téléphone'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('code'))).keyboardType, TextInputType.number);
    await signInWith(tester, '1357');
    expect(find.text('Numéro ou code incorrect.'), findsOneWidget);
  });

  testWidgets('connexion : l\'admin passe au mot de passe (clavier texte)', (tester) async {
    await setUpServices(tester, signIn: false);
    await tester.pumpWidget(app(SignInPage(services: services)));
    await tester.tap(find.byKey(const Key('password-mode')));
    await tester.pump();
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('password'))).keyboardType, TextInputType.visiblePassword);
    await signInWith(tester, 'faux', field: const Key('password'));
    expect(find.text('Numéro ou mot de passe incorrect.'), findsOneWidget);
    await signInWith(tester, 'motdepasse', field: const Key('password'));
    expect(services.signedIn, isTrue);
  });

  testWidgets('connexion : blocage après trop d\'essais, message du serveur', (tester) async {
    await setUpServices(tester, signIn: false);
    server.loginRefusal = (429, {'error': 'Trop d’essais. Réessayez dans 15 minutes ou appelez votre coordinateur.', 'code': 'blocked'});
    await tester.pumpWidget(app(SignInPage(services: services)));
    await signInWith(tester, '4827');
    expect(find.text('Trop d’essais. Réessayez dans 15 minutes ou appelez votre coordinateur.'), findsOneWidget);
    expect(services.signedIn, isFalse);
  });

  testWidgets('connexion : un compte coordinateur est renvoyé vers le tableau de bord', (tester) async {
    await setUpServices(tester, signIn: false);
    server.loginRefusal = (403, {'error': 'Ce compte s’utilise sur le tableau de bord.', 'code': 'dashboard_only'});
    await tester.pumpWidget(app(SignInPage(services: services)));
    await signInWith(tester, 'motdepasse');
    expect(find.text('Ce compte s’utilise sur le tableau de bord.'), findsOneWidget);
    expect(services.signedIn, isFalse);
  });

  testWidgets('session fermée par le serveur : « Session expirée », saisies gardées', (tester) async {
    await setUpServices(tester);
    await tester.runAsync(() async {
      server.offline = true;
      await services.saveProducer(Producer(id: 'p-off', lastName: 'Kane', firstName: 'Ali', consentAt: DateTime.utc(2026, 11, 25)));
      server.offline = false;
      server.sessionRevoked = true;
      await services.sync(force: true);
    });
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    expect(find.text('Session expirée'), findsOneWidget);
    expect(find.text('Vos saisies sont gardées sur le téléphone. Reconnectez-vous pour les envoyer.'), findsOneWidget);
    expect(services.pendingCount, 1);
  });

  testWidgets('commune retirée : message dédié, « Renvoyer » et « Écarter » sur la fiche', (tester) async {
    await setUpServices(tester);
    server.outOfScope.add('p-out');
    await tester.runAsync(() async {
      await services.saveProducer(Producer(id: 'p-out', lastName: 'Kane', firstName: 'Ali', consentAt: DateTime.utc(2026, 11, 25)));
      await services.sync(force: true);
    });
    await tester.pumpWidget(app(ProducerPage(services: services, producer: services.producers['p-out'])));
    await tester.pumpAndSettle();
    expect(find.text('Refusé par le serveur'), findsOneWidget);
    expect(find.textContaining('Ce producteur ne vous est plus attribué : contactez votre coordinateur.'), findsOneWidget);
    expect(find.text('Écarter'), findsOneWidget);
    server.outOfScope.clear();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('retry')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(server.producers.containsKey('p-out'), isTrue);
    expect(services.rejectionFor('p-out'), isNull);
  });

  testWidgets('nouveau producteur : consentement obligatoire, semence, puis file d\'envoi', (tester) async {
    await setUpServices(tester, role: 'admin');
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
    await tester.pumpAndSettle();
    expect(find.textContaining('Cochez le consentement'), findsOneWidget);
    expect(find.textContaining('cochez son accord pour enregistrer'), findsOneWidget, reason: 'le bloc consentement passe en erreur');
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
    expect(find.text('Spunta, 50 kg'), findsOneWidget, reason: 'variété unique proposée par défaut');

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
    await setUpServices(tester, role: 'admin');
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
    expect(find.text('4 sommets · 438 m de tour'), findsOneWidget);
    expect(find.text('1,19 ha'), findsOneWidget);
    expect(find.textContaining('Écart avec la surface mesurée : −21 %', findRichText: true), findsOneWidget);
    expect(find.text('Champ du puits · Awa DIOP'), findsOneWidget);
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
    expect(find.textContaining('Nouveau champ ·'), findsOneWidget);
    expect(find.text('Pas encore de contour'), findsOneWidget);

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

  testWidgets('ajouter un champ à un producteur déjà enregistré ne le renvoie pas', (tester) async {
    await setUpServices(tester);
    final p = Producer(id: 'p1', lastName: 'Diop', firstName: 'Awa', consentAt: DateTime.utc(2026, 11, 23));
    services.producers['p1'] = p;
    await tester.pumpWidget(app(ProducerPage(services: services, producer: p)));
    await tester.pumpAndSettle();
    await reveal(tester, const Key('add-field'));
    await tester.tap(find.byKey(const Key('add-field')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nouveau champ ·'), findsOneWidget);
    expect(services.pending, isEmpty);
  });

  // --- Agent : liste de ses producteurs attribués (ADR-0002, ticket #26) ---------------------------

  void seedAgentData() {
    services.producers['a1'] = const Producer(
      id: 'a1',
      lastName: 'Diop',
      firstName: 'Awa',
      phone: '221771234567',
      village: 'VILLAGE UN',
      commune: 'COMMUNE A',
      areaDeclaredHa: 2,
      areaValidatedHa: 1.5,
      source: 'import',
    );
    services.producers['a2'] = const Producer(id: 'a2', lastName: 'Fall', firstName: 'Ibou', memberCard: 'CM-7', source: 'import');
    services.producers['a3'] = const Producer(
      id: 'a3',
      lastName: 'Sow',
      firstName: 'Élimane',
      phone: '221785551122',
      village: 'ALLA NDIAYE',
      commune: 'COMMUNE B',
      source: 'import',
    );
    services.producers['a4'] = const Producer(
      id: 'a4',
      lastName: 'Ba',
      firstName: 'Mariama',
      phone: '221766667788',
      village: 'VILLAGE UN',
      commune: 'COMMUNE A',
      source: 'import',
    );
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('search')), text);
    await tester.pumpAndSettle();
  }

  /// Écran haut : les quatre cartes tiennent sans défiler (la liste est construite à la demande).
  void tall(WidgetTester tester) => tester.view.physicalSize = const Size(360, 1600);

  List<String> shownNames(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(Card), matching: find.byType(Text))))
      if (['Awa DIOP', 'Ibou FALL', 'Élimane SOW', 'Mariama BA'].contains(t.data)) t.data!,
  ];

  testWidgets('agent : liste de tous ses producteurs dès la connexion, triée par village puis par nom', (tester) async {
    await setUpServices(tester);
    seedAgentData();
    tall(tester);
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    expect(find.text('Producteurs'), findsOneWidget);
    expect(find.text('Mes producteurs'), findsNothing);
    expect(shownNames(tester), [
      'Élimane SOW',
      'Mariama BA',
      'Awa DIOP',
      'Ibou FALL',
    ], reason: 'ALLA NDIAYE, puis VILLAGE UN (Ba, Diop), puis sans village');
    expect(find.byKey(const Key('new-producer')), findsOneWidget, reason: 'bouton toujours visible');
    expect(tester.takeException(), isNull);
  });

  testWidgets('agent : filtre partiel sur le nom, le téléphone ou le village, sans accents ni casse', (tester) async {
    await setUpServices(tester);
    seedAgentData();
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    await search(tester, 'elim');
    expect(shownNames(tester), ['Élimane SOW']);
    await search(tester, 'dio');
    expect(shownNames(tester), ['Awa DIOP']);
    await search(tester, '77 123');
    expect(shownNames(tester), ['Awa DIOP']);
    await search(tester, '+221 78 555');
    expect(shownNames(tester), ['Élimane SOW']);
    await search(tester, 'village un');
    expect(shownNames(tester), ['Mariama BA', 'Awa DIOP']);
    await search(tester, 'cm-7');
    expect(shownNames(tester), ['Ibou FALL']);
    await search(tester, 'personne');
    expect(find.text('Aucun producteur ne correspond'), findsOneWidget);
    expect(find.byKey(const Key('new-producer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agent : filtre par commune quand il en a plusieurs', (tester) async {
    await setUpServices(tester);
    seedAgentData();
    tall(tester);
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('communes')), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'COMMUNE B'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), ['Élimane SOW']);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Toutes'));
    await tester.pumpAndSettle();
    expect(shownNames(tester).length, 4);
  });

  testWidgets('agent : une seule commune, pas de filtre par commune', (tester) async {
    await setUpServices(tester);
    seedAgentData();
    services.producers.remove('a3');
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('communes')), findsNothing);
  });

  testWidgets('agent : fiche avec commune et surfaces depuis la liste', (tester) async {
    await setUpServices(tester);
    seedAgentData();
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Awa DIOP'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('commune')), findsOneWidget);
    expect(find.text('VILLAGE UN, commune de COMMUNE A'), findsOneWidget);
    expect(find.text('Fiche : 2 ha déclarés, 1,5 ha validés'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agent : « Nouveau producteur » reprend le numéro complet saisi dans le filtre', (tester) async {
    await setUpServices(tester);
    seedAgentData();
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    await search(tester, '78 000 11 22');
    expect(find.text('Aucun producteur ne correspond'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-producer')));
    await tester.pumpAndSettle();
    final phone = tester.widget<TextFormField>(find.byKey(const Key('phone')));
    expect(phone.controller!.text, '78 000 11 22');
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin : liste complète, recherche libre par commune', (tester) async {
    await setUpServices(tester, role: 'admin');
    seedAgentData();
    tall(tester);
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    expect(find.text('Producteurs'), findsOneWidget);
    expect(find.text('Awa DIOP'), findsOneWidget);
    expect(find.text('Ibou FALL'), findsOneWidget);
    expect(find.byKey(const Key('new-producer')), findsOneWidget);
    await search(tester, 'commune a');
    expect(find.text('Awa DIOP'), findsOneWidget);
    expect(find.text('Ibou FALL'), findsNothing);
  });
}
