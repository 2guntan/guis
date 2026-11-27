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

  test('session fermée par le serveur (code réinitialisé) : la saisie reste en file et part après la reconnexion', () async {
    await app.signIn('770000001', 'motdepasse');
    server.offline = true;
    final p = awa();
    await app.saveProducer(p);
    server.offline = false;
    server.sessionRevoked = true;
    final r = await app.sync(force: true);
    expect(r!.transientError, 'Session expirée : reconnectez-vous.');
    expect(app.sessionExpired, isTrue);
    expect(app.pendingCount, 1, reason: 'rien n\'est perdu');
    await app.signOut();
    await app.signIn('770000001', 'motdepasse');
    expect(server.producers.containsKey(p.id), isTrue);
    expect(app.pendingCount, 0);
  });

  test('commune retirée : envoi refusé (403) gardé sur le téléphone, puis renvoyé quand la commune est rendue', () async {
    await app.signIn('770000001', 'motdepasse');
    final p = awa();
    server.outOfScope.add(p.id);
    await app.saveProducer(p);
    final r = await app.sync(force: true);
    expect(r!.rejected, 1);
    expect(app.rejectionFor(p.id)!.lastError, 'Ce producteur ne vous est plus attribué : contactez votre coordinateur.');
    expect(app.producers.containsKey(p.id), isTrue);
    server.outOfScope.remove(p.id);
    await app.retry(app.rejectionFor(p.id)!);
    expect(server.producers.containsKey(p.id), isTrue);
    expect(app.rejectionFor(p.id), isNull);
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
    expect(flaky.producers.containsKey('p9'), isFalse, reason: 'jamais les producteurs du compte précédent');
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

  // --- Démarrage sûr (audit H7) et saisie interrompue (audit H4, H5) ------------------------------

  test('démarrage : session et données illisibles ne bloquent pas l\'app', () async {
    await app.signIn('770000001', 'motdepasse');
    File('${dir.path}/session.json').writeAsStringSync('{"token": "abc", "acc');
    File('${dir.path}/data.json').writeAsStringSync('[1, 2');
    final again = await open();
    expect(again.signedIn, isFalse, reason: 'session illisible : l\'agent se reconnecte');
    expect(again.producers, isEmpty);
    expect(again.recoveryNotice, isNull);
    expect(await again.errorLog.tail(), contains('FormatException'));
  });

  test('démarrage : une file d\'envoi illisible est mise de côté, jamais effacée', () async {
    await app.signIn('770000001', 'motdepasse');
    const broken = '[{"id": "e1", "method": "PUT", "pa';
    File('${dir.path}/outbox.json').writeAsStringSync(broken);
    final again = await open();
    expect(again.recoveryNotice, contains('mise de côté'));
    final aside = dir.listSync().whereType<File>().where((f) => f.path.contains('outbox.json.illisible-')).toList();
    expect(aside, hasLength(1));
    expect(aside.single.readAsStringSync(), broken);
    // La file repart vide et fonctionne.
    server.offline = true;
    await again.saveProducer(awa());
    expect(again.pendingCount, 1);
  });

  test('saisie interrompue : gardée pour le même compte, effacée à la déconnexion', () async {
    await app.signIn('770000001', 'motdepasse');
    await app.saveDraft('producer', {'id': 'p-brouillon', 'last_name': 'Ndiaye'});
    await app.saveDraft('field', {'id': 'f1', 'producer_id': 'p-brouillon'});
    await app.saveDraft('field', null);

    final again = await open();
    expect(again.draft?['producer']?['last_name'], 'Ndiaye', reason: 'relue au lancement suivant');
    expect(again.draft?.containsKey('field'), isFalse);

    // Un autre compte ne la voit pas.
    server.user = {'id': 'u-2', 'name': 'Autre Agent', 'phone': '221770000002', 'role': 'agent'};
    await again.signIn('770000002', 'motdepasse');
    expect(again.draft, isNull);

    await again.signOut();
    expect(File('${dir.path}/draft.json').readAsStringSync(), isNot(contains('Ndiaye')));
  });

  test('journal des erreurs : plafonné, garde les plus récentes', () async {
    final big = 'x' * 1000;
    for (var i = 0; i < 300; i++) {
      await app.errorLog.write(StateError('$i $big'));
    }
    final file = File('${dir.path}/erreurs.log');
    expect(file.lengthSync(), lessThan(300 * 1000));
    expect(await app.errorLog.tail(), contains('299 '));
  });

  test('photo perdue pendant l\'appareil photo : retrouvée dans le dossier de l\'app', () async {
    await app.photosDir.create(recursive: true);
    File('${app.photosDir.path}/ph-1.jpg').writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
    final p = await recoverPhoto(app.photosDir, 'ph-1');
    expect(p?.id, 'ph-1');
    expect(LocalPhoto.fromJson(p!.toJson()).path, p.path);
    expect(await recoverPhoto(app.photosDir, 'ph-absente'), isNull, reason: 'appareil photo annulé');
  });

  // --- Conflits (ADR-0004), mise à jour (M10), photos abandonnées (M6) ----------------------------

  test('fiche modifiée ailleurs : refusée avec le message du serveur, « Renvoyer » remplace sans la date', () async {
    server.producers['p1'] = {
      'id': 'p1',
      'last_name': 'Diop',
      'first_name': 'Awa',
      'consent_at': '2026-11-23T10:00:00.000Z',
      'edited_at': '2026-11-24T08:00:00.000Z',
    };
    await app.signIn('770000001', 'motdepasse');
    expect(app.producers['p1']!.editedAt, '2026-11-24T08:00:00.000Z');

    server.editedElsewhere.add('p1');
    await app.saveProducer(app.producers['p1']!.copyWith(firstName: 'Awa Marie'));
    await app.sync(force: true);
    expect(server.producerBodies['p1']!.last['base_edited_at'], '2026-11-24T08:00:00.000Z', reason: 'date reçue renvoyée');
    final refused = app.rejectionFor('p1')!;
    expect(refused.lastError, contains('modifié par quelqu’un d’autre'));

    await app.retry(refused);
    expect(server.producerBodies['p1']!.last.containsKey('base_edited_at'), isFalse);
    expect(server.producers['p1']!['first_name'], 'Awa Marie');
    expect(app.pending, isEmpty);
    // La date n'est pas gardée en double dans les données locales.
    expect(File('${dir.path}/data.json').readAsStringSync(), isNot(contains('base_edited_at')));
  });

  test('mise à jour : bloquante sous le minimum, bandeau sous la dernière version, gardée hors ligne', () async {
    Future<AppServices> openBuild(int build) async =>
        await AppServices.open(dir, Api('https://guis.test', client: server.client), appBuild: build)
          ..syncAfterSave = false;
    server.app = {'min_build': 5, 'latest_build': 9, 'apk_url': 'https://example.test/guis.apk'};
    final old = await openBuild(3);
    await old.signIn('770000001', 'motdepasse');
    expect((old.updateRequired, old.updateAvailable, old.apkUrl), (true, true, 'https://example.test/guis.apk'));

    server.offline = true;
    final again = await openBuild(7);
    expect((again.updateRequired, again.updateAvailable), (false, true), reason: 'relu sur le téléphone, sans réseau');
    expect((await openBuild(9)).updateAvailable, isFalse);
    expect(app.updateRequired, isFalse, reason: 'sans numéro de build (tests) : jamais bloquée');
  });

  test('démarrage : les photos prises puis abandonnées sont effacées, les autres gardées', () async {
    await app.signIn('770000001', 'motdepasse');
    await app.photosDir.create(recursive: true);
    File photo(String id) => File('${app.photosDir.path}/$id.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
    final abandoned = photo('abandonnee');
    final shown = photo('ph-producteur');
    final pendingPhoto = photo('ph-attente');
    final drafted = photo('ph-brouillon');
    server.offline = true;
    await app.saveProducer(awa().copyWith(photoId: 'ph-producteur'));
    await app.saveProducer(
      awa(),
      photo: LocalPhoto(id: 'ph-attente', path: pendingPhoto.path, takenAt: DateTime.utc(2026, 11, 27)),
    );
    await app.saveDraft('producer', {'id': 'x', 'camera': 'ph-brouillon'});

    await open();
    expect(abandoned.existsSync(), isFalse);
    expect([shown, pendingPhoto, drafted].every((f) => f.existsSync()), isTrue);
  });
}

/// Client HTTP de test qui délègue chaque requête à une fonction.
class MockClientProxy extends http.BaseClient {
  MockClientProxy(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest req) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _send(request);
}
