import 'dart:async';
import 'dart:io';

import 'package:fieldproof_agent/core/json_store.dart';
import 'package:fieldproof_agent/core/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, StorageException;

const me = 'a0000000-0000-4000-8000-000000000061';
const other = 'a0000000-0000-4000-8000-000000000062';

OutboxEntry entry(String id, {String profile = me, String file = 'f1', String rpc = 'dossier.save_draft', int second = 0}) => OutboxEntry(
      id: id,
      rpc: rpc,
      payload: {'tag': id},
      profileId: profile,
      subjectId: file,
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

  Future<Object?> record(String rpc, Map<String, dynamic> p) async {
    calls.add(p['tag'] as String);
    return null;
  }

  test('un même identifiant n\'entre qu\'une fois dans la file', () async {
    await outbox.enqueue(entry('m1'));
    await outbox.enqueue(entry('m1'));
    expect((await outbox.entries()).length, 1);
  });

  test('envoie dans l\'ordre de saisie et vide la file', () async {
    await outbox.enqueue(entry('m2', second: 2));
    await outbox.enqueue(entry('m1', second: 1));
    final report = await outbox.flush(me, record);
    expect(calls, ['m1', 'm2']);
    expect(report.sent, 2);
    expect(await outbox.entries(), isEmpty);
  });

  test('ordre par dossier : un refus bloque la suite du même dossier, pas les autres dossiers', () async {
    await outbox.enqueue(entry('a-draft', file: 'A', second: 1));
    await outbox.enqueue(entry('b-draft', file: 'B', second: 2));
    await outbox.enqueue(entry('a-submit', file: 'A', rpc: 'dossier.submit_file', second: 3));
    await outbox.enqueue(entry('b-submit', file: 'B', rpc: 'dossier.submit_file', second: 4));
    final report = await outbox.flush(me, (rpc, p) async {
      calls.add(p['tag'] as String);
      if (p['tag'] == 'a-draft') throw const PostgrestException(message: 'save_draft: dossier FP-26-00001, statut « submitted » : seul le superviseur peut agir', code: 'P0001');
      return null;
    });
    expect(calls, ['a-draft', 'b-draft', 'b-submit'], reason: 'la soumission de A ne part jamais après un brouillon refusé');
    expect(report.rejected, 1);
    expect(report.sent, 2);
    final left = await outbox.entries();
    expect(left.map((e) => e.id), ['a-draft', 'a-submit']);
    expect(left.first.rejected, isTrue);
    expect(left.first.lastError, 'dossier FP-26-00001, statut « submitted » : seul le superviseur peut agir');
    expect(left.last.rejected, isFalse);
    expect(report.rejectedEntries.single.id, 'a-draft');

    // L'agent écarte le refus : la suite du dossier A se débloque.
    await outbox.discard('a-draft');
    calls.clear();
    await outbox.flush(me, record);
    expect(calls, ['a-submit']);
  });

  test('une erreur réseau arrête l\'envoi, garde l\'ordre et attend un délai croissant', () async {
    await outbox.enqueue(entry('m1', second: 1));
    await outbox.enqueue(entry('m2', second: 2));
    final first = await outbox.flush(me, (rpc, p) async {
      calls.add(p['tag'] as String);
      throw const SocketException('Failed host lookup');
    });
    expect(calls, ['m1'], reason: 'm2 ne doit pas passer devant m1');
    expect(first.transientError, 'Pas de réseau');
    expect(first.remaining, 2);
    final kept = await outbox.entries();
    expect(kept.first.attempts, 1);
    expect(kept.first.nextAttemptAt, now.add(const Duration(seconds: 10)));
    expect(kept.every((e) => !e.rejected), isTrue);

    // Avant le délai : rien ne part automatiquement.
    final early = await outbox.flush(me, record);
    expect(early.sent, 0);
    expect(calls, ['m1']);

    // Après le délai : tout part, dans l'ordre.
    now = now.add(const Duration(seconds: 11));
    final second = await outbox.flush(me, record);
    expect(calls, ['m1', 'm1', 'm2']);
    expect(second.remaining, 0);
  });

  test('« Synchroniser » ignore le délai', () async {
    await outbox.enqueue(entry('m1'));
    await outbox.flush(me, (rpc, p) async => throw const SocketException('x'));
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
    await outbox.flush(me, (rpc, p) async => throw const SocketException('x'));
    final reopened = Outbox(JsonFileStore(File('${dir.path}/outbox.json')), clock: () => now.add(const Duration(minutes: 1)));
    final e = (await reopened.entries()).single;
    expect((e.id, e.attempts, e.lastError), ('m1', 1, 'Pas de réseau'));
    final report = await reopened.flush(me, record);
    expect(report.sent, 1);
  });

  test('le brouillon remplace le précédent du même dossier s\'il est encore le dernier en file', () async {
    await outbox.enqueue(entry('d1', second: 1), replaceTail: true);
    await outbox.enqueue(entry('d2', second: 2), replaceTail: true);
    expect((await outbox.entries()).map((e) => e.id), ['d2']);
    await outbox.enqueue(entry('doc', rpc: 'dossier.register_document', second: 3));
    await outbox.enqueue(entry('d3', second: 4), replaceTail: true);
    expect((await outbox.entries()).map((e) => e.id), ['d2', 'doc', 'd3'], reason: 'jamais remplacé par-dessus une pièce');
    await outbox.flush(me, record);
    expect(calls, ['d2', 'doc', 'd3']);
  });

  test('une session expirée (PGRST…) n\'est pas un refus définitif', () async {
    await outbox.enqueue(entry('m1'));
    final report = await outbox.flush(me, (rpc, p) async => throw const PostgrestException(message: 'JWT expired', code: 'PGRST301'));
    expect(report.transientError, 'JWT expired');
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
    await outbox.enqueue(entry('m1', second: 1), replaceTail: true);
    final gate = Completer<void>();
    final flushing = outbox.flush(me, (rpc, p) async {
      calls.add(p['tag'] as String);
      await gate.future;
      return null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await outbox.enqueue(entry('m2', second: 2), replaceTail: true);
    gate.complete();
    await flushing;
    expect((await outbox.entries()).map((e) => e.id), ['m2'], reason: 'm1 en cours d\'envoi n\'est pas remplacé : m2 part ensuite');
  });

  test('une commande refusée peut être renvoyée', () async {
    await outbox.enqueue(entry('m1'));
    await outbox.flush(me, (rpc, p) async => throw const PostgrestException(message: 'permission denied', code: '42501'));
    expect((await outbox.entries()).single.rejected, isTrue);
    await outbox.requeue('m1');
    final report = await outbox.flush(me, record);
    expect(calls, ['m1']);
    expect(report.sent, 1);
  });

  test('classe les erreurs : refus de la base contre erreur transitoire', () {
    bool definitive(String? code) => isDefinitiveRefusal(PostgrestException(message: 'x', code: code));
    expect(definitive('P0001'), isTrue, reason: 'raise exception');
    expect(definitive('42501'), isTrue, reason: 'droit refusé');
    expect(definitive('23514'), isTrue, reason: 'contrainte');
    expect(definitive('40001'), isFalse, reason: 'sérialisation');
    expect(definitive('08006'), isFalse, reason: 'connexion');
    expect(definitive('PGRST301'), isFalse, reason: 'session');
    expect(definitive(null), isFalse);
    expect(isDefinitiveRefusal(const SocketException('x')), isFalse);
    expect(isDefinitiveRefusal(const StorageException('new row violates row-level security policy', statusCode: '403')), isTrue);
    expect(isDefinitiveRefusal(const StorageException('Too many requests', statusCode: '429')), isFalse);
    expect(isDefinitiveRefusal(const StorageException('Internal', statusCode: '500')), isFalse);
  });

  test('les pièces jointes partent avant la commande ; une coupure après le dépôt les redépose sans perte', () async {
    final photo = File('${dir.path}/p1.jpg')..writeAsBytesSync([1, 2, 3]);
    await outbox.enqueue(OutboxEntry(
      id: 'doc-1',
      rpc: 'dossier.register_document',
      payload: {'tag': 'doc-1'},
      profileId: me,
      subjectId: 'f1',
      label: 'Pièce',
      createdAt: DateTime.utc(2026, 11, 20),
      attachments: [OutboxAttachment(localPath: photo.path, storagePath: 'files/f1/d1.jpg', contentType: 'image/jpeg')],
    ));
    final cut = await outbox.flush(me, (rpc, p) async => throw Exception('réseau coupé'), upload: (a) async => calls.add('upload ${a.storagePath}'));
    expect((cut.sent, cut.remaining), (0, 1));
    final done = await outbox.flush(me, (rpc, p) async => calls.add('rpc $rpc'), upload: (a) async => calls.add('upload ${a.storagePath}'), force: true);
    expect(done.sent, 1);
    expect(calls, ['upload files/f1/d1.jpg', 'upload files/f1/d1.jpg', 'rpc dossier.register_document']);
    expect(photo.existsSync(), isTrue, reason: 'la photo reste affichable sur le téléphone');
  });

  test('le message du serveur perd son préfixe technique', () {
    expect(errorMessage(const PostgrestException(message: 'submit_file: dossier incomplet — Téléphone', code: 'P0001')), 'dossier incomplet — Téléphone');
  });
}
