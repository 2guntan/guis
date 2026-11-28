import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:guis/core/api.dart';
import 'package:guis/core/model/models.dart';
import 'package:guis/core/services.dart';
import 'package:guis/features/auth/sign_in_page.dart';
import 'package:guis/features/fields/field_page.dart';
import 'package:guis/features/fields/field_walk_page.dart';
import 'package:guis/features/producers/producer_page.dart';
import 'package:guis/features/producers/producers_page.dart';
import 'package:guis/features/update_page.dart';
import 'package:guis/main.dart';
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
    // Lien discret, en bas de l'écran : les agents ne le voient pas d'emblée.
    await tester.scrollUntilVisible(find.byKey(const Key('password-mode')), 100, scrollable: find.byType(Scrollable).first);
    expect(find.text('Accès administrateur'), findsOneWidget);
    await tester.tap(find.byKey(const Key('password-mode')));
    await tester.pump();
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.text('Revenir à la connexion par code'), findsOneWidget);
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

  testWidgets('photos du champ : cinq au plus, une photo retirée quitte la fiche', (tester) async {
    await setUpServices(tester);
    final p = const Producer(id: 'p1', lastName: 'Diop', firstName: 'Awa');
    services.producers['p1'] = p;
    final ids = ['ph1', 'ph2', 'ph3', 'ph4', 'ph5'];
    final f = Field(id: 'f1', producerId: 'p1', name: 'Champ 1', photoIds: ids);
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => FieldPage(services: services, producer: p, field: f),
              ),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('photos-full')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Photos du champ (5/5)'), findsOneWidget);
    expect(find.byKey(const Key('photo-field')), findsNothing, reason: 'cinq photos : plus de bouton');

    await tester.ensureVisible(find.byKey(const Key('remove-photo-2')));
    await tester.tap(find.byKey(const Key('remove-photo-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-photo')));
    await tester.pumpAndSettle();
    expect(find.text('Photos du champ (4/5)'), findsOneWidget);
    expect(find.byKey(const Key('photos-full')), findsNothing);
    expect(find.byKey(const Key('photo-field')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-field')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('save-field')));
      for (var i = 0; i < 50 && services.pending.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();
    expect(services.fields['f1']!.photoIds, ['ph1', 'ph3', 'ph4', 'ph5']);
    expect(services.pending.single.payload['photo_ids'], ['ph1', 'ph3', 'ph4', 'ph5']);
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
      for (var i = 0; i < 50 && services.pending.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();
    expect(services.producers.values.single.fullName, 'Moussa NDIAYE');
    expect(find.textContaining('Nouveau champ ·'), findsOneWidget);
    expect(find.text('Pas encore de contour'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-field')));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('save-field')));
      // Écritures réelles sur le disque : on attend leur fin (un délai fixe est trop court sur la CI).
      for (var i = 0; i < 50 && services.pending.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
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

  // --- Saisie protégée et semences (audit 2026-11-27, H2 et H3) ---------------------------------

  testWidgets('une semence retirée après un enregistrement intermédiaire est supprimée sur le serveur', (tester) async {
    await setUpServices(tester);
    await tester.pumpWidget(app(ProducerPage(services: services)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('last-name')), 'Ndiaye');
    await tester.enterText(find.byKey(const Key('first-name')), 'Moussa');
    await reveal(tester, const Key('consent'));
    await tester.tap(find.byKey(const Key('consent')));
    await tester.pump();
    await reveal(tester, const Key('add-seed'));
    await tester.tap(find.byKey(const Key('add-seed')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quantity')), '20');
    await tester.tap(find.byKey(const Key('save-seed')));
    await tester.pumpAndSettle();

    // « Ajouter un champ » enregistre le producteur (avec sa semence), puis l'agent revient sans rien saisir.
    await reveal(tester, const Key('add-field'));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('add-field')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FieldPage), findsNothing, reason: 'fiche champ intacte : retour sans question');

    // Il retire la semence et enregistre.
    await tester.ensureVisible(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();
    await reveal(tester, const Key('save-producer'));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('save-producer')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    await tester.runAsync(() => services.sync(force: true));
    expect(server.seeds, isEmpty, reason: 'la semence retirée ne revient pas');
    expect(services.producers.values.single.seeds, isEmpty);
  });

  testWidgets('quitter une fiche modifiée demande confirmation', (tester) async {
    await setUpServices(tester);
    final p = Producer(id: 'p1', lastName: 'Diop', firstName: 'Awa', consentAt: DateTime.utc(2026, 11, 23));
    services.producers['p1'] = p;
    await tester.pumpWidget(app(ProducersPage(services: services)));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ProducersPage))).push(
      MaterialPageRoute<void>(
        builder: (_) => ProducerPage(services: services, producer: p),
      ),
    );
    await tester.pumpAndSettle();

    // Fiche non modifiée : retour direct.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ProducerPage), findsNothing);

    Navigator.of(tester.element(find.byType(ProducersPage))).push(
      MaterialPageRoute<void>(
        builder: (_) => ProducerPage(services: services, producer: p),
      ),
    );
    await tester.pumpAndSettle();
    await reveal(tester, const Key('edit-identity'));
    await tester.tap(find.byKey(const Key('edit-identity')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('first-name')), 'Aminata');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('keep-editing')));
    await tester.pumpAndSettle();
    expect(find.byType(ProducerPage), findsOneWidget, reason: 'la saisie est gardée');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-loss')));
    await tester.pumpAndSettle();
    expect(find.byType(ProducerPage), findsNothing);
    expect(services.producers['p1']!.firstName, 'Awa');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tour du champ : « Annuler » et « Recommencer » demandent confirmation', (tester) async {
    await setUpServices(tester);
    final square = [
      for (final (lat, lng) in [(14.9, -17.1), (14.9, -17.099), (14.901, -17.099)])
        GpsPoint(lat: lat, lng: lng, accuracyM: 4, capturedAt: DateTime.utc(2026, 11, 27)),
    ];
    await tester.pumpWidget(app(const Scaffold(body: Text('accueil'))));
    // La carte et le GPS ne s'arrêtent jamais : pas de pumpAndSettle.
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<List<GpsPoint>?> open() {
      final f = Navigator.of(tester.element(find.text('accueil'))).push<List<GpsPoint>>(
        MaterialPageRoute(
          builder: (_) => FieldWalkPage(name: 'Champ 1', initial: square),
        ),
      );
      return f;
    }

    var walk = open();
    await settle();
    // Contour reçu sans changement : « Annuler » ferme sans question.
    await tester.tap(find.byKey(const Key('cancel-walk')));
    await settle();
    expect(find.byType(FieldWalkPage), findsNothing);
    expect(await walk, isNull, reason: 'aucun tracé rendu');

    walk = open();
    await settle();
    await tester.tap(find.byKey(const Key('restart-walk')));
    await settle();
    expect(find.text('Effacer tous les points ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('keep-editing')));
    await settle();
    expect(find.text('3 sommets · ${perimeterM(square).toStringAsFixed(0)} m de tour'), findsOneWidget, reason: 'points gardés');

    await tester.tap(find.byKey(const Key('restart-walk')));
    await settle();
    await tester.tap(find.byKey(const Key('confirm-loss')));
    await settle();
    expect(find.textContaining('0 sommet'), findsOneWidget);

    // Le tracé a changé : « Annuler » demande confirmation.
    await tester.tap(find.byKey(const Key('cancel-walk')));
    await settle();
    expect(find.text('Abandonner le tracé ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-loss')));
    await settle();
    expect(find.byType(FieldWalkPage), findsNothing);
  });

  testWidgets('tour du champ : un coin est mesuré quelques secondes et la moyenne est gardée', (tester) async {
    final gps = StreamController<Position>();
    addTearDown(gps.close);
    Position fix(double lat, double acc) => Position(
      latitude: lat,
      longitude: -17.1,
      timestamp: DateTime.utc(2026, 11, 28),
      accuracy: acc,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    final changes = <List<GpsPoint>>[];
    await tester.pumpWidget(
      app(FieldWalkPage(name: 'Champ 1', initial: const [], cornerSeconds: 3, positions: gps.stream, onChanged: changes.add)),
    );
    await tester.pump();
    expect(find.textContaining('Un point à chaque coin du champ'), findsOneWidget);
    expect(find.byType(Switch), findsNothing, reason: 'le relevé automatique est rangé dans le menu');

    gps.add(fix(14.9, 4));
    await tester.pump();
    await tester.pump(); // la position arrive, puis l'écran se redessine
    await tester.tap(find.byKey(const Key('add-point')));
    await tester.pump();
    expect(find.text('Restez immobile… 3'), findsOneWidget);
    gps.add(fix(14.9002, 4));
    gps.add(fix(15.5, 40)); // trop imprécise : écartée
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Restez immobile… 2'), findsOneWidget);
    expect(changes, isEmpty, reason: 'rien n\'est gardé avant la fin de la mesure');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Ajouter ce point'), findsOneWidget);
    expect(changes.single.single.lat, closeTo(14.9001, 1e-9));
    expect(find.textContaining('1 sommet'), findsOneWidget);

    // Le relevé automatique reste disponible dans le menu ⋮.
    await tester.tap(find.byKey(const Key('walk-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-walk')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Relevé automatique : un point tous les 5 m'), findsOneWidget);
  });

  // --- Saisie interrompue par Android (audit H4, H5) ------------------------------------------------

  testWidgets('app arrêtée en arrière-plan : la fiche en cours est reprise au lancement suivant', (tester) async {
    await setUpServices(tester);
    await tester.pumpWidget(app(ProducerPage(services: services)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('last-name')), 'Ndiaye');
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(services.draft?['producer']?['last_name'], 'Ndiaye', reason: 'gardée sur le disque en passant en arrière-plan');

    // Android arrête l'app (pas de fermeture normale de la fiche) ; au lancement suivant, l'accueil la rouvre.
    late AppServices again;
    await tester.runAsync(() async {
      again = await AppServices.open(services.photosDir.parent, Api('https://guis.test', client: server.client));
      again.syncAfterSave = false;
      again.autoSyncEnabled = false;
    });
    await tester.pumpWidget(app(ProducersPage(services: again)));
    await tester.pumpAndSettle();
    expect(find.byType(ProducerPage), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Ndiaye'), findsOneWidget);
    expect(find.textContaining('Saisie interrompue reprise'), findsOneWidget);
  });

  testWidgets('tour du champ interrompu : repris avec ses points, gardés si l\'agent annule', (tester) async {
    await setUpServices(tester);
    final p = Producer(id: 'p1', lastName: 'Diop', firstName: 'Awa', consentAt: DateTime.utc(2026, 11, 23));
    services.producers['p1'] = p;
    final square = [
      for (final (lat, lng) in [(14.9, -17.1), (14.9, -17.099), (14.901, -17.099)])
        GpsPoint(lat: lat, lng: lng, accuracyM: 4, capturedAt: DateTime.utc(2026, 11, 27)),
    ];
    await tester.runAsync(
      () => services.saveDraft('field', {
        'id': 'f-nouveau',
        'producer_id': 'p1',
        'name': 'Champ 1',
        'declared': '',
        'contour': const [],
        'walk': [for (final x in square) x.toJson()],
      }),
    );
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tester.pumpWidget(app(ProducersPage(services: services)));
    await settle();
    expect(find.byType(FieldWalkPage), findsOneWidget, reason: 'le tour reprend où il en était');
    expect(find.text('3 sommets · ${perimeterM(square).toStringAsFixed(0)} m de tour'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel-walk')));
    await settle();
    expect(find.byType(FieldPage), findsOneWidget);
    // Les points repris sont le contour du champ : le quitter sans enregistrer demande confirmation.
    await tester.binding.handlePopRoute();
    await settle();
    expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);
  });

  // --- Limites du serveur vérifiées sur la fiche (M12), mise à jour de l'app (M10) ------------------

  testWidgets('fiche : téléphone et surface vérifiés avec les règles du serveur', (tester) async {
    await setUpServices(tester);
    await tester.pumpWidget(app(ProducerPage(services: services)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('last-name')), 'Diop');
    await tester.enterText(find.byKey(const Key('first-name')), 'Awa');
    await tester.enterText(find.byKey(const Key('phone')), '12 34 56 78 90');
    await reveal(tester, const Key('save-producer'));
    await tester.tap(find.byKey(const Key('save-producer')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Numéro à 9 chiffres'), findsOneWidget);
    expect(services.producers, isEmpty);

    final p = Producer(id: 'p1', lastName: 'Diop', firstName: 'Awa', consentAt: DateTime.utc(2026, 11, 23));
    services.producers['p1'] = p;
    await tester.pumpWidget(app(FieldPage(services: services, producer: p)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('declared')), '1500');
    await tester.ensureVisible(find.byKey(const Key('save-field')));
    await tester.tap(find.byKey(const Key('save-field')));
    await tester.pumpAndSettle();
    expect(find.text('1000 ha au plus'), findsOneWidget);
    expect(services.fields, isEmpty);
  });

  testWidgets('app trop ancienne : écran de mise à jour avec le lien, rien d\'autre', (tester) async {
    await setUpServices(tester, signIn: false);
    server.app = {'min_build': 5, 'apk_url': 'https://example.test/guis.apk'};
    late AppServices old;
    await tester.runAsync(() async {
      old = await AppServices.open(services.photosDir.parent, Api('https://guis.test', client: server.client), appBuild: 3);
      old.autoSyncEnabled = false;
      await old.signIn('770000001', 'motdepasse');
    });
    await tester.pumpWidget(GuisApp(services: old));
    await tester.pumpAndSettle();
    expect(find.byType(UpdatePage), findsOneWidget);
    expect(find.text('https://example.test/guis.apk'), findsOneWidget);
    expect(find.byType(ProducersPage), findsNothing);
  });

  // --- Grande taille de texte du téléphone (audit L6) -------------------------------------------------

  for (final scale in [1.5, 2.0]) {
    testWidgets('texte agrandi ×$scale : accueil, fiche et champ sans débordement', (tester) async {
      await setUpServices(tester);
      seedAgentData();
      final p = services.producers['a1']!;
      Widget scaled(Widget home) => MaterialApp(
        theme: guisTheme(),
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      );
      for (final screen in <Widget>[
        ProducersPage(services: services),
        ProducerPage(services: services, producer: p),
        ProducerPage(services: services),
        FieldPage(services: services, producer: p),
      ]) {
        await tester.pumpWidget(scaled(screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${screen.runtimeType} à ×$scale');
      }
    });
  }
}
