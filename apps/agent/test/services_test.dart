import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:guis/core/api.dart';
import 'package:guis/core/model/models.dart';
import 'package:guis/core/photos.dart';
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

  List<GpsPoint> square() => [
    for (final (lat, lng) in [(15.0500, -16.9500), (15.0500, -16.9490), (15.0490, -16.9490), (15.0490, -16.9500)])
      GpsPoint(lat: lat, lng: lng, accuracyM: 4, capturedAt: DateTime.utc(2026, 11, 23)),
  ];

  test('champ saisi hors ligne juste après son producteur : il part toujours derrière lui', () async {
    await app.signIn('770000001', 'motdepasse');
    server.offline = true;
    final p = awa();
    await app.saveProducer(p);
    final f = Field(
      id: newId(),
      producerId: p.id,
      name: 'Champ 1',
      contour: square(),
      areaDeclaredHa: 1,
      sownOn: '2026-11-15',
      irrigation: 'Goutte-à-goutte',
    );
    await app.saveField(f);
    // Une modification du producteur après le champ ne passe pas devant le champ.
    await app.saveProducer(p.copyWith(firstName: 'Awa Marie'));
    expect(app.fieldsOf(p.id).single.measuredHa, closeTo(1.19, 0.02));
    server.offline = false;
    final r = await app.sync(force: true);
    expect(r!.rejected, 0);
    expect(server.log.where((l) => l.startsWith('PUT')), [
      'PUT /api/app/producers/${p.id}',
      'PUT /api/app/fields/${f.id}',
      'PUT /api/app/producers/${p.id}',
    ]);
    expect(server.fields[f.id]!['sown_on'], '2026-11-15');
    expect((server.fields[f.id]!['contour'] as List).length, 4);
    expect(app.fieldsOf(p.id).single.contour.length, 4, reason: 'le champ revient du serveur au chargement');
  });

  test('un champ refusé ne bloque pas les champs des autres producteurs', () async {
    await app.signIn('770000001', 'motdepasse');
    // Producteur inconnu du serveur (jamais envoyé) : le champ est refusé (409).
    final orphan = Field(id: newId(), producerId: 'inconnu', name: 'Orphelin');
    await app.saveField(orphan);
    final p = awa();
    await app.saveProducer(p);
    await app.saveField(Field(id: newId(), producerId: p.id, name: 'Champ 1'));
    final r = await app.sync(force: true);
    expect(r!.rejected, 1);
    expect(server.fields.length, 1);
    expect(app.rejectionFor('inconnu')!.lastError, 'Le producteur de ce champ est inconnu du serveur.');
  });

  test('photos : déposées avant l\'enregistrement qui les cite, reprise sans doublon après une coupure', () async {
    await app.signIn('770000001', 'motdepasse');
    await app.photosDir.create(recursive: true);
    LocalPhoto photo(String id) {
      final f = File('${app.photosDir.path}/$id.jpg')..writeAsBytesSync([0xff, 0xd8, 1, 2, 0xff, 0xd9]);
      return LocalPhoto(id: id, path: f.path, takenAt: DateTime.utc(2026, 11, 23, 10), lat: 15.05, lng: -16.95);
    }

    final p = awa();
    await app.saveProducer(p, photo: photo('ph-producteur'));
    await app.saveField(
      Field(id: 'f1', producerId: p.id, name: 'Champ 1'),
      photo: photo('ph-champ'),
    );
    expect(app.producers[p.id]!.photoId, 'ph-producteur');
    expect(app.fields['f1']!.photoId, 'ph-champ');
    expect(app.localPhoto('ph-champ'), isNotNull, reason: 'aperçu hors ligne');

    // Coupure juste après le premier dépôt.
    var uploads = 0;
    server.offline = false;
    final real = server.client;
    final cut = FakeServer()..offline = true;
    final flaky = Api(
      'https://guis.test',
      client: MockClientProxy((req) async {
        if (req.url.path.startsWith('/api/photos/') && uploads++ == 0) return real.send(req);
        if (uploads > 1) return real.send(req);
        return cut.client.send(req);
      }),
      token: app.api.token,
    );
    final r1 = await app.outbox.flush(
      app.account!.id,
      (e) => flaky.sendJson(e.method, e.path, e.payload),
      upload: (a) => flaky.putBytes(a.uploadPath, File(a.localPath).readAsBytesSync(), contentType: a.contentType, headers: a.headers),
    );
    expect(r1.transientError, 'Pas de réseau');
    expect(server.photos.keys, ['ph-producteur']);
    expect(server.producers, isEmpty);

    final r2 = await app.sync(force: true);
    expect(r2!.sent, 2);
    expect(server.log.where((l) => l.startsWith('PUT')), [
      'PUT /api/photos/ph-producteur',
      'PUT /api/photos/ph-producteur',
      'PUT /api/app/producers/${p.id}',
      'PUT /api/photos/ph-champ',
      'PUT /api/app/fields/f1',
    ]);
    expect(server.photos.length, 2);
    expect(server.producers[p.id]!['photo_id'], 'ph-producteur');
    expect(server.fields['f1']!['photo_id'], 'ph-champ');
  });

  // --- Téléphone partagé entre agents (audit 2026-11-27, H1) -------------------------------------

  test('déconnexion : les producteurs reçus et les photos envoyées sont effacés du téléphone', () async {
    server.producers['p9'] = {'id': 'p9', 'last_name': 'Sow', 'first_name': 'Fatou', 'phone': '221779998877', 'source': 'import'};
    await app.signIn('770000001', 'motdepasse');
    expect(app.producers.containsKey('p9'), isTrue);
    await app.photosDir.create(recursive: true);
    final sentPhoto = File('${app.photosDir.path}/deja-envoyee.jpg')..writeAsBytesSync([1]);

    await app.signOut();
    expect(app.producers, isEmpty);
    expect(app.lists.villages, isEmpty);
    expect(app.hasData, isFalse);
    expect(File('${dir.path}/data.json').readAsStringSync(), isNot(contains('221779998877')));
    expect(sentPhoto.existsSync(), isFalse);

    // Un autre agent se connecte ; le premier chargement échoue (réseau instable).
    server.user = {'id': 'u-2', 'name': 'Autre Agent', 'phone': '221770000002', 'role': 'agent'};
    server.producers.clear();
    server.offline = false;
    final flaky = await AppServices.open(
      dir,
      Api(
        'https://guis.test',
        client: MockClientProxy((req) async {
          if (req.url.path == '/api/app/bootstrap') return http.StreamedResponse(Stream.value('{"error":"panne"}'.codeUnits), 503);
          return server.client.send(req);
        }),
      ),
    );
    await flaky.signIn('770000002', 'motdepasse');
    expect(flaky.searchExact('77 999 88 77'), isEmpty, reason: 'jamais les producteurs du compte précédent');
  });

  test('déconnexion avec des saisies en attente : gardées pour le même compte, cachées à un autre', () async {
    await app.signIn('770000001', 'motdepasse');
    server.offline = true;
    await app.photosDir.create(recursive: true);
    final f = File('${app.photosDir.path}/ph-attente.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
    final p = awa();
    await app.saveProducer(
      p,
      photo: LocalPhoto(id: 'ph-attente', path: f.path, takenAt: DateTime.utc(2026, 11, 27)),
    );
    await app.signOut();
    expect(app.producers.keys, [p.id], reason: 'la saisie non envoyée reste affichable pour son auteur');
    expect(f.existsSync(), isTrue, reason: 'la photo doit encore partir');

    // Un autre compte : il ne voit pas la saisie ; elle reste dans la file de son auteur.
    server.offline = false;
    server.user = {'id': 'u-2', 'name': 'Autre Agent', 'phone': '221770000002', 'role': 'agent'};
    await app.signIn('770000002', 'motdepasse');
    expect(app.producers.containsKey(p.id), isFalse);
    expect(server.producers.containsKey(p.id), isFalse, reason: 'ne part que sous le compte de son auteur');
    await app.signOut();

    // Son auteur revient : la saisie part.
    server.user = {'id': 'u-1', 'name': 'Agent Test', 'phone': '221770000001', 'role': 'agent'};
    await app.signIn('770000001', 'motdepasse');
    expect(server.producers[p.id]!['photo_id'], 'ph-attente');
    expect(server.photos.containsKey('ph-attente'), isTrue);
  });
}

/// Client HTTP de test qui délègue chaque requête à une fonction.
class MockClientProxy extends http.BaseClient {
  MockClientProxy(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest req) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _send(request);
}
