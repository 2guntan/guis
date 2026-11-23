import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guis/core/api.dart';
import 'package:guis/core/model/models.dart';
import 'package:guis/core/services.dart';

import 'fake_server.dart';

Producer awa({String? id, String lastName = 'Diop', List<Seed> seeds = const []}) => Producer(
  id: id ?? newId(),
  lastName: lastName,
  firstName: 'Awa',
  phone: '771234567',
  memberCard: 'CM-1',
  sex: 'F',
  village: 'Village A',
  consentAt: DateTime.utc(2026, 11, 23, 10),
  seeds: seeds,
);

void main() {
  late Directory dir;
  late FakeServer server;
  late AppServices app;

  Future<AppServices> open() async {
    final s = await AppServices.open(dir, Api('https://guis.test', client: server.client));
    s.syncAfterSave = false;
    return s;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('services');
    server = FakeServer();
    app = await open();
  });
  tearDown(() => dir.delete(recursive: true));

  test('connexion : la session et les listes sont gardées sur le téléphone', () async {
    await app.signIn('77 000 00 01', 'motdepasse');
    expect(app.account!.name, 'Agent Test');
    expect(app.lists.villages, ['Village A']);
    final reopened = await open();
    expect(reopened.signedIn, isTrue);
    expect(reopened.lists.varieties, ['Spunta']);
  });

  test('mauvais mot de passe : message du serveur, pas de session', () async {
    await expectLater(
      app.signIn('770000001', 'faux'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Numéro ou mot de passe incorrect.')),
    );
    expect(app.signedIn, isFalse);
  });

  test('saisie hors ligne puis synchronisation : le producteur et ses semences arrivent sur le serveur', () async {
    await app.signIn('770000001', 'motdepasse');
    server.offline = true;
    final p = awa(
      seeds: [Seed(id: newId(), variety: 'Spunta', quantityKg: 50, receivedOn: '2026-11-10')],
    );
    await app.saveProducer(p);
    expect(app.producers[p.id]!.fullName, 'Awa DIOP', reason: 'visible tout de suite sur le téléphone');
    expect(app.pendingCount, 1);

    final failed = await app.sync();
    expect(failed!.transientError, 'Pas de réseau');
    expect(app.pendingCount, 1);
    expect(server.producers, isEmpty);

    server.offline = false;
    final ok = await app.sync(force: true);
    expect(ok!.sent, 1);
    expect(app.pendingCount, 0);
    expect(server.producers[p.id]!['last_name'], 'Diop');
    expect(server.seeds.values.single['quantity_kg'], 50);
  });

  test('la file survit à la fermeture de l\'app', () async {
    await app.signIn('770000001', 'motdepasse');
    server.offline = true;
    final p = awa();
    await app.saveProducer(p);
    final reopened = await open();
    expect(reopened.producers[p.id]!.lastName, 'Diop');
    expect(reopened.pendingCount, 1);
    server.offline = false;
    await reopened.sync(force: true);
    expect(server.producers.containsKey(p.id), isTrue);
  });

  test('deux modifications hors ligne : une seule requête, avec le dernier état et les suppressions', () async {
    await app.signIn('770000001', 'motdepasse');
    final s1 = Seed(id: newId(), variety: 'Spunta', quantityKg: 50);
    final p = awa(seeds: [s1]);
    await app.saveProducer(p);
    await app.sync(force: true);
    server.log.clear();
    server.offline = true;
    await app.saveProducer(p.copyWith(seeds: []), deletedSeedIds: [s1.id]);
    await app.saveProducer(p.copyWith(seeds: [], firstName: 'Awa Marie'));
    server.offline = false;
    await app.sync(force: true);
    expect(server.log.where((l) => l.startsWith('PUT')).length, 1);
    expect(server.producers[p.id]!['first_name'], 'Awa Marie');
    expect(server.seeds, isEmpty, reason: 'la suppression de la semence n\'est pas perdue par le remplacement');
  });

  test('un refus du serveur reste sur le producteur concerné sans bloquer les autres', () async {
    await app.signIn('770000001', 'motdepasse');
    server.rejectLastNames.add('Refus');
    final bad = awa(lastName: 'Refus');
    final good = Producer(id: newId(), lastName: 'Ndiaye', firstName: 'Moussa', consentAt: DateTime.utc(2026, 11, 23));
    await app.saveProducer(bad);
    await app.saveProducer(good);
    final r = await app.sync(force: true);
    expect(r!.rejected, 1);
    expect(r.sent, 1);
    expect(server.producers.containsKey(good.id), isTrue);
    expect(app.rejectionFor(bad.id)!.lastError, 'Donnée refusée.');
    expect(app.rejectionFor(good.id), isNull);
    expect(app.producers.containsKey(bad.id), isTrue, reason: 'la saisie refusée reste visible pour être corrigée');

    // L'agent écarte le refus : la saisie quitte le téléphone au prochain chargement.
    await app.discard(app.rejectionFor(bad.id)!);
    await app.sync(force: true);
    expect(app.producers.containsKey(bad.id), isFalse);
  });

  test('chargement : les producteurs des autres agents arrivent, une saisie en attente n\'est pas écrasée', () async {
    await app.signIn('770000001', 'motdepasse');
    final mine = awa();
    await app.saveProducer(mine);
    await app.sync(force: true);

    // Un autre agent crée un producteur, et la version serveur de « mine » change.
    server.producers['autre'] = {
      'id': 'autre',
      'last_name': 'Fall',
      'first_name': 'Ibou',
      'consent_at': '2026-11-23T09:00:00Z',
      'source': 'import',
    };
    server.producers[mine.id]!['first_name'] = 'Version serveur';

    // Hors ligne, l'agent modifie « mine » : la synchronisation échoue avant le chargement.
    server.offline = true;
    await app.saveProducer(mine.copyWith(firstName: 'Version locale'));
    await app.sync();
    server.offline = false;
    await app.refresh();
    expect(app.producers['autre']!.lastName, 'Fall');
    expect(app.producers[mine.id]!.firstName, 'Version locale', reason: 'saisie en attente gardée');

    await app.sync(force: true);
    expect(server.producers[mine.id]!['first_name'], 'Version locale');
  });

  test('session expirée : signalée, la saisie reste en file', () async {
    await app.signIn('770000001', 'motdepasse');
    app.api.token = 'perime';
    await app.saveProducer(awa());
    final r = await app.sync(force: true);
    expect(r!.transientError, 'Session expirée : reconnectez-vous.');
    expect(app.sessionExpired, isTrue);
    expect(app.pendingCount, 1);
  });

  test('déconnexion : les saisies non envoyées partent à la reconnexion du même compte', () async {
    await app.signIn('770000001', 'motdepasse');
    server.offline = true;
    final p = awa();
    await app.saveProducer(p);
    server.offline = false;
    await app.signOut();
    expect(app.signedIn, isFalse);
    await app.signIn('770000001', 'motdepasse');
    expect(server.producers.containsKey(p.id), isTrue);
  });

  test('recherche sans accents ni casse', () {
    final p = awa().copyWith(village: 'Mboro Thiès');
    expect(p.matches('thies'), isTrue);
    expect(p.matches('awa diop'), isTrue);
    expect(p.matches('CM-1'), isTrue);
    expect(p.matches('fall'), isFalse);
  });
}
