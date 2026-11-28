// Repris de Fieldproof (apps/agent/test/outbox_test.dart) et adapté : requêtes HTTP au lieu de RPC
// Supabase, sujet = producteur, remplacement par ressource (voir PROVENANCE.md).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:guis/core/api.dart';
import 'package:guis/core/json_store.dart';
import 'package:guis/core/sync/outbox.dart';

const me = 'a0000000-0000-4000-8000-000000000061';
const other = 'a0000000-0000-4000-8000-000000000062';

OutboxEntry entry(String id, {String profile = me, String subject = 'p1', String path = '/api/app/producers/p1', int second = 0}) =>
    OutboxEntry(
      id: id,
      method: 'PUT',
      path: path,
      payload: {'tag': id},
      profileId: profile,
      subjectId: subject,
      label: 'Commande $id',
      createdAt: DateTime.utc(2026, 11, 20, 8, 0, second),
    );

void main() {
  late Directory dir;
  late Outbox outbox;
  late List<String> calls;
  late DateTime now;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('outbox');
    now = DateTime.utc(2026, 11, 20, 9);
    outbox = Outbox(JsonFileStore(File('${dir.path}/outbox.json')), clock: () => now);
    calls = [];
  });
  tearDown(() => dir.delete(recursive: true));

  Future<Object?> record(OutboxEntry e) async {
    calls.add(e.payload['tag'] as String);
    return null;
  }

  test('un même identifiant n\'entre qu\'une fois dans la file', () async {
    await outbox.enqueue(entry('m1'));
    await outbox.enqueue(entry('m1'));
    expect((await outbox.entries()).length, 1);
  });

  test('envoie dans l\'ordre de saisie et vide la file', () async {
    await outbox.enqueue(entry('m2', subject: 'B', path: '/b', second: 2));
    await outbox.enqueue(entry('m1', subject: 'A', path: '/a', second: 1));
    final report = await outbox.flush(me, record);
    expect(calls, ['m1', 'm2']);
    expect(report.sent, 2);
    expect(await outbox.entries(), isEmpty);
  });

  test('ordre par producteur : un refus bloque la suite du même producteur, pas les autres', () async {
    await outbox.enqueue(entry('a-prod', subject: 'A', path: '/p/A', second: 1));
    await outbox.enqueue(entry('b-prod', subject: 'B', path: '/p/B', second: 2));
    await outbox.enqueue(entry('a-field', subject: 'A', path: '/f/A1', second: 3));
    await outbox.enqueue(entry('b-field', subject: 'B', path: '/f/B1', second: 4));
    final report = await outbox.flush(me, (e) async {
      calls.add(e.payload['tag'] as String);
      if (e.payload['tag'] == 'a-prod') {
        throw const ApiException(409, 'Ce numéro de carte de membre est déjà utilisé par un autre producteur.');
      }
      return null;
    });
    expect(calls, ['a-prod', 'b-prod', 'b-field'], reason: 'le champ de A ne part jamais après un producteur refusé');
    expect(report.rejected, 1);
    expect(report.sent, 2);
    final left = await outbox.entries();
    expect(left.map((e) => e.id), ['a-prod', 'a-field']);
    expect(left.first.rejected, isTrue);
    expect(left.first.lastError, 'Ce numéro de carte de membre est déjà utilisé par un autre producteur.');
    expect(left.last.rejected, isFalse);
    expect(report.rejectedEntries.single.id, 'a-prod');

    // L'agent écarte le refus : la suite du producteur A se débloque.
    await outbox.discard('a-prod');
    calls.clear();
    await outbox.flush(me, record);
    expect(calls, ['a-field']);
  });

  test('une erreur réseau arrête l\'envoi, garde l\'ordre et attend un délai croissant', () async {
    await outbox.enqueue(entry('m1', second: 1));
    await outbox.enqueue(entry('m2', path: '/autre', second: 2));
    final first = await outbox.flush(me, (e) async {
      calls.add(e.payload['tag'] as String);
      throw const SocketException('Failed host lookup');
    });
    expect(calls, ['m1'], reason: 'm2 ne doit pas passer devant m1');
    expect(first.transientError, 'Pas de réseau');
    expect(first.remaining, 2);
    final kept = await outbox.entries();
    expect(kept.first.attempts, 1);
    expect(kept.first.nextAttemptAt, now.add(const Duration(seconds: 10)));
    expect(kept.every((e) => !e.rejected), isTrue);

    final early = await outbox.flush(me, record);
    expect(early.sent, 0);
    expect(calls, ['m1']);

    now = now.add(const Duration(seconds: 11));
    final second = await outbox.flush(me, record);
    expect(calls, ['m1', 'm1', 'm2']);
    expect(second.remaining, 0);
  });

  test('« Synchroniser » ignore le délai', () async {
    await outbox.enqueue(entry('m1'));
    await outbox.flush(me, (e) async => throw const SocketException('x'));
    final forced = await outbox.flush(me, record, force: true);
    expect(forced.sent, 1);
  });

  test('le délai double à chaque échec, plafonné à 15 minutes', () {
    expect(backoff(1), const Duration(seconds: 10));
    expect(backoff(2), const Duration(seconds: 20));
    expect(backoff(4), const Duration(seconds: 80));
    expect(backoff(20), const Duration(minutes: 15));
  });

  test('la file survit à un redémarrage (relue sur le disque)', () async {
    await outbox.enqueue(entry('m1', second: 1));
    await outbox.flush(me, (e) async => throw const SocketException('x'));
    final reopened = Outbox(JsonFileStore(File('${dir.path}/outbox.json')), clock: () => now.add(const Duration(minutes: 1)));
    final e = (await reopened.entries()).single;
    expect((e.id, e.attempts, e.lastError), ('m1', 1, 'Pas de réseau'));
    final report = await reopened.flush(me, record);
    expect(report.sent, 1);
  });

  test('un nouvel instantané de la même ressource remplace le précédent s\'il est encore le dernier', () async {
    await outbox.enqueue(entry('d1', second: 1));
    await outbox.enqueue(entry('d2', second: 2));
    expect((await outbox.entries()).map((e) => e.id), ['d2']);
    await outbox.enqueue(entry('field', path: '/api/app/fields/f1', second: 3));
    await outbox.enqueue(entry('d3', second: 4));
    expect((await outbox.entries()).map((e) => e.id), ['d2', 'field', 'd3'], reason: 'jamais remplacé par-dessus une autre ressource');
    await outbox.flush(me, record);
    expect(calls, ['d2', 'field', 'd3']);
  });

  test('le remplacement garde les photos encore à déposer', () async {
    const a1 = OutboxAttachment(localPath: '/x/1.jpg', uploadPath: '/api/photos/1', contentType: 'image/jpeg');
    const a2 = OutboxAttachment(localPath: '/x/2.jpg', uploadPath: '/api/photos/2', contentType: 'image/jpeg');
    final e1 = entry('d1');
    await outbox.enqueue(
      OutboxEntry(
        id: e1.id,
        method: e1.method,
        path: e1.path,
        payload: e1.payload,
        profileId: me,
        subjectId: e1.subjectId,
        label: 'x',
        createdAt: e1.createdAt,
        attachments: [a1],
      ),
    );
    await outbox.enqueue(
      OutboxEntry(
        id: 'd2',
        method: 'PUT',
        path: e1.path,
        payload: {'tag': 'd2'},
        profileId: me,
        subjectId: e1.subjectId,
        label: 'x',
        createdAt: e1.createdAt,
        attachments: [a2],
      ),
    );
    final e = (await outbox.entries()).single;
    expect(e.attachments.map((a) => a.uploadPath), ['/api/photos/1', '/api/photos/2']);
  });

  test('une session expirée (401) n\'est pas un refus définitif', () async {
    await outbox.enqueue(entry('m1'));
    final report = await outbox.flush(me, (e) async => throw const ApiException(401, 'Session expirée : reconnectez-vous.'));
    expect(report.transientError, 'Session expirée : reconnectez-vous.');
    expect((await outbox.entries()).single.rejected, isFalse);
  });

  test('ne part que sous le compte qui a saisi la commande', () async {
    await outbox.enqueue(entry('m1', profile: other));
    await outbox.enqueue(entry('m2'));
    await outbox.flush(me, record);
    expect(calls, ['m2']);
    expect((await outbox.entries()).single.profileId, other);
  });

  test('une saisie faite pendant un envoi n\'est pas écrasée ni remplacée', () async {
    await outbox.enqueue(entry('m1', second: 1));
    final gate = Completer<void>();
    final flushing = outbox.flush(me, (e) async {
      calls.add(e.payload['tag'] as String);
      await gate.future;
      return null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await outbox.enqueue(entry('m2', second: 2));
    gate.complete();
    await flushing;
    expect((await outbox.entries()).map((e) => e.id), ['m2'], reason: 'm1 en cours d\'envoi n\'est pas remplacé : m2 part ensuite');
  });

  test('une commande refusée peut être renvoyée', () async {
    await outbox.enqueue(entry('m1'));
    await outbox.flush(me, (e) async => throw const ApiException(403, 'Accès refusé'));
    expect((await outbox.entries()).single.rejected, isTrue);
    await outbox.requeue('m1');
    final report = await outbox.flush(me, record);
    expect(calls, ['m1']);
    expect(report.sent, 1);
  });

  test('classe les erreurs : refus du serveur contre erreur transitoire', () {
    bool definitive(int status) => isDefinitiveRefusal(ApiException(status, 'x'));
    expect(definitive(400), isTrue);
    expect(definitive(403), isTrue);
    expect(definitive(409), isTrue);
    expect(definitive(422), isTrue);
    expect(definitive(401), isFalse, reason: 'session');
    expect(definitive(408), isFalse);
    expect(definitive(429), isFalse);
    expect(definitive(500), isFalse);
    expect(definitive(502), isFalse);
    expect(isDefinitiveRefusal(const SocketException('x')), isFalse);
    expect(isDefinitiveRefusal(TimeoutException('x')), isFalse);
  });

  test('les pièces jointes partent avant la commande ; une coupure après le dépôt les redépose sans perte', () async {
    final photo = File('${dir.path}/p1.jpg')..writeAsBytesSync([1, 2, 3]);
    await outbox.enqueue(
      OutboxEntry(
        id: 'prod-1',
        method: 'PUT',
        path: '/api/app/producers/p1',
        payload: {'tag': 'prod-1'},
        profileId: me,
        subjectId: 'p1',
        label: 'Producteur',
        createdAt: DateTime.utc(2026, 11, 20),
        attachments: [OutboxAttachment(localPath: photo.path, uploadPath: '/api/photos/ph1', contentType: 'image/jpeg')],
      ),
    );
    final cut = await outbox.flush(
      me,
      (e) async => throw const SocketException('réseau coupé'),
      upload: (a) async => calls.add('upload ${a.uploadPath}'),
    );
    expect((cut.sent, cut.remaining), (0, 1));
    final done = await outbox.flush(
      me,
      (e) async => calls.add('put ${e.path}'),
      upload: (a) async => calls.add('upload ${a.uploadPath}'),
      force: true,
    );
    expect(done.sent, 1);
    expect(calls, ['upload /api/photos/ph1', 'upload /api/photos/ph1', 'put /api/app/producers/p1']);
    expect(photo.existsSync(), isTrue, reason: 'la photo reste affichable sur le téléphone');
  });

  // --- Commandes qui ne passent jamais (audit 2026-11-27, C1) -----------------------------------

  test('une erreur serveur répétée sur un producteur ne bloque pas les autres', () async {
    await outbox.enqueue(entry('a-prod', subject: 'A', path: '/p/A', second: 1));
    await outbox.enqueue(entry('a-field', subject: 'A', path: '/f/A1', second: 2));
    await outbox.enqueue(entry('b-prod', subject: 'B', path: '/p/B', second: 3));
    final report = await outbox.flush(me, (e) async {
      calls.add(e.payload['tag'] as String);
      if (e.payload['tag'] == 'a-prod') throw const ApiException(500, 'Erreur du serveur, réessai plus tard.');
      return null;
    });
    expect(calls, ['a-prod', 'b-prod'], reason: 'B part ; le champ de A attend toujours son producteur');
    expect((report.sent, report.interrupted), (1, false));
    expect(report.transientError, 'Erreur du serveur, réessai plus tard.');
    final left = await outbox.entries();
    expect(left.map((e) => e.id), ['a-prod', 'a-field']);
    expect(left.first.rejected, isFalse, reason: 'erreur transitoire : on réessaiera');
    expect(left.first.nextAttemptAt, now.add(const Duration(seconds: 10)));
  });

  test('une erreur inattendue sur le téléphone ne bloque que son producteur', () async {
    await outbox.enqueue(entry('a-prod', subject: 'A', path: '/p/A', second: 1));
    await outbox.enqueue(entry('b-prod', subject: 'B', path: '/p/B', second: 2));
    final report = await outbox.flush(me, (e) async {
      calls.add(e.payload['tag'] as String);
      if (e.payload['tag'] == 'a-prod') throw StateError('bogue');
      return null;
    });
    expect(calls, ['a-prod', 'b-prod']);
    expect(report.transientError, 'Erreur inattendue, nouvel essai plus tard', reason: 'jamais le texte brut de l\'exception');
  });

  test('réseau coupé ou session refusée : l\'envoi s\'arrête pour tous', () async {
    for (final error in <Object>[const SocketException('x'), const ApiException(401, 'Session expirée'), const ApiException(503, 'x')]) {
      calls.clear();
      await outbox.enqueue(entry('a-$error', subject: 'A', path: '/p/A', second: 1));
      await outbox.enqueue(entry('b-$error', subject: 'B', path: '/p/B', second: 2));
      final report = await outbox.flush(me, (e) async {
        calls.add(e.subjectId);
        throw error;
      }, force: true);
      expect(calls, ['A'], reason: '$error');
      expect(report.interrupted, isTrue);
      for (final e in await outbox.entries()) {
        await outbox.discard(e.id);
      }
    }
  });

  test('une photo disparue du téléphone : la fiche part sans elle, la file continue', () async {
    await outbox.enqueue(
      OutboxEntry(
        id: 'prod-1',
        method: 'PUT',
        path: '/api/app/producers/p1',
        payload: {'tag': 'prod-1', 'photo_id': 'ph-perdue', 'last_name': 'Diop'},
        profileId: me,
        subjectId: 'p1',
        label: 'Producteur',
        createdAt: DateTime.utc(2026, 11, 20),
        attachments: [
          OutboxAttachment(localPath: '${dir.path}/absente.jpg', uploadPath: '/api/photos/ph-perdue', contentType: 'image/jpeg'),
        ],
      ),
    );
    await outbox.enqueue(entry('b-prod', subject: 'B', path: '/p/B', second: 5));
    final sent = <Map<String, dynamic>>[];
    final report = await outbox.flush(me, (e) async => sent.add(e.payload), upload: (a) async => calls.add('upload ${a.uploadPath}'));
    expect(calls, isEmpty, reason: 'rien à déposer');
    expect(report.sent, 2);
    expect(sent.first, {'tag': 'prod-1', 'photo_id': null, 'last_name': 'Diop'}, reason: 'le serveur garde la photo qu\'il avait');
    expect(await outbox.entries(), isEmpty);
  });

  test('une photo du champ disparue du téléphone : retirée de la liste, les autres partent', () async {
    final kept = File('${dir.path}/ph-ok.jpg')..writeAsBytesSync([0xff, 0xd8, 0xff, 0xd9]);
    await outbox.enqueue(
      OutboxEntry(
        id: 'field-1',
        method: 'PUT',
        path: '/api/app/fields/f1',
        payload: {
          'producer_id': 'p1',
          'photo_ids': ['ph-ok', 'ph-perdue'],
        },
        profileId: me,
        subjectId: 'p1',
        label: 'Champ',
        createdAt: DateTime.utc(2026, 11, 20),
        attachments: [
          OutboxAttachment(localPath: kept.path, uploadPath: '/api/photos/ph-ok', contentType: 'image/jpeg'),
          OutboxAttachment(localPath: '${dir.path}/absente.jpg', uploadPath: '/api/photos/ph-perdue', contentType: 'image/jpeg'),
        ],
      ),
    );
    final sent = <Map<String, dynamic>>[];
    await outbox.flush(me, (e) async => sent.add(e.payload), upload: (a) async => calls.add('upload ${a.uploadPath}'));
    expect(calls, ['upload /api/photos/ph-ok']);
    expect(sent.single, {
      'producer_id': 'p1',
      'photo_ids': ['ph-ok'],
    });
  });

  test('le délai reste plafonné après de très nombreux échecs (pas de dépassement d\'entier)', () {
    for (final n in [7, 8, 63, 64, 100, 5000]) {
      expect(backoff(n), n == 7 ? const Duration(seconds: 640) : const Duration(minutes: 15), reason: '$n essais');
    }
  });
}
