import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../api.dart';
import '../json_store.dart';

export '../api.dart' show errorMessage, isConnectivityError, isDefinitiveRefusal;

/// Une pièce jointe d'une commande : un fichier de l'appareil déposé sur le serveur à un
/// chemin déterministe (`/api/photos/<id>`) **avant** la requête qui le référence.
class OutboxAttachment {
  const OutboxAttachment({required this.localPath, required this.uploadPath, required this.contentType, this.headers = const {}});

  final String localPath;
  final String uploadPath;
  final String contentType;

  /// En-têtes du dépôt (position, date de prise de vue).
  final Map<String, String> headers;

  Map<String, dynamic> toJson() => {'local_path': localPath, 'upload_path': uploadPath, 'content_type': contentType, 'headers': headers};

  factory OutboxAttachment.fromJson(Map<String, dynamic> j) => OutboxAttachment(
    localPath: j['local_path'] as String,
    uploadPath: j['upload_path'] as String,
    contentType: j['content_type'] as String,
    headers: Map<String, String>.from((j['headers'] as Map?) ?? const {}),
  );
}

/// Une commande en attente d'envoi : une requête HTTP (upsert par identifiant), rattachée à un producteur.
///
/// Reprise de l'outbox Fieldproof (elle-même reprise d'Agriva). Différences voulues : une requête
/// REST (`PUT /api/app/...`) remplace l'appel de RPC Supabase ; le sujet est le **producteur**
/// (le producteur et ses champs partagent le même sujet : un champ ne part jamais avant son producteur).
/// L'ordre est garanti par sujet — un refus bloque la suite du même producteur, jamais celle des autres —
/// et les erreurs transitoires attendent un délai croissant avant de repartir.
class OutboxEntry {
  OutboxEntry({
    required this.id,
    required this.method,
    required this.path,
    required this.payload,
    required this.profileId,
    required this.subjectId,
    required this.label,
    required this.createdAt,
    this.attachments = const [],
    this.attempts = 0,
    this.rejected = false,
    this.lastError,
    this.nextAttemptAt,
  });

  /// Identifiant de la commande (clef locale, jamais envoyée).
  final String id;

  /// `PUT`.
  final String method;

  /// `/api/app/producers/<id>`.
  final String path;
  final Map<String, dynamic> payload;

  /// Fichiers déposés avant la requête, dans l'ordre ; le chemin étant déterministe et le dépôt
  /// idempotent, un dépôt repris après coupure ne crée pas de doublon.
  final List<OutboxAttachment> attachments;

  /// Le compte qui a saisi la commande : elle ne part que sous sa session.
  final String profileId;

  /// Le producteur concerné : l'ordre est garanti par producteur.
  final String subjectId;

  /// Libellé lisible par l'agent (« Producteur — Awa DIOP »).
  final String label;
  final DateTime createdAt;
  int attempts;

  /// Refusée par le serveur : ne repartira pas seule ; bloque la suite du même producteur.
  bool rejected;

  /// Dernier message reçu, tel que rendu par le serveur ou par le réseau.
  String? lastError;

  /// Pas d'envoi automatique avant cette date (délai croissant après une erreur transitoire).
  DateTime? nextAttemptAt;

  /// Clé de remplacement : deux instantanés de la même ressource se remplacent.
  String get resource => '$method $path';

  /// La même commande, sans les références (`photo_id`…) aux identifiants donnés.
  OutboxEntry withoutReferences(Set<String> ids) => OutboxEntry(
    id: id,
    method: method,
    path: path,
    payload: {for (final MapEntry(:key, :value) in payload.entries) key: ids.contains(value) ? null : value},
    profileId: profileId,
    subjectId: subjectId,
    label: label,
    createdAt: createdAt,
    attempts: attempts,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'method': method,
    'path': path,
    'payload': payload,
    'profile_id': profileId,
    'subject_id': subjectId,
    'label': label,
    'created_at': createdAt.toUtc().toIso8601String(),
    if (attachments.isNotEmpty) 'attachments': [for (final a in attachments) a.toJson()],
    'attempts': attempts,
    'rejected': rejected,
    'last_error': lastError,
    'next_attempt_at': nextAttemptAt?.toUtc().toIso8601String(),
  };

  factory OutboxEntry.fromJson(Map<String, dynamic> j) => OutboxEntry(
    id: j['id'] as String,
    method: j['method'] as String,
    path: j['path'] as String,
    payload: Map<String, dynamic>.from(j['payload'] as Map),
    profileId: j['profile_id'] as String,
    subjectId: j['subject_id'] as String,
    label: j['label'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    attachments: [for (final a in (j['attachments'] as List?) ?? const []) OutboxAttachment.fromJson(Map<String, dynamic>.from(a as Map))],
    attempts: j['attempts'] as int? ?? 0,
    rejected: j['rejected'] as bool? ?? false,
    lastError: j['last_error'] as String?,
    nextAttemptAt: DateTime.tryParse(j['next_attempt_at'] as String? ?? ''),
  );
}

/// Envoie une requête (`services.dart`).
typedef Sender = Future<Object?> Function(OutboxEntry entry);

/// Dépose une pièce jointe ; un chemin déjà déposé est un succès.
typedef Uploader = Future<void> Function(OutboxAttachment attachment);

class FlushReport {
  const FlushReport({
    required this.sent,
    required this.rejected,
    required this.remaining,
    this.transientError,
    this.interrupted = false,
    this.sentEntries = const [],
    this.rejectedEntries = const [],
  });

  final int sent;
  final int rejected;
  final int remaining;

  /// Dernière erreur transitoire (réseau, session, erreur du serveur) : la commande concernée sera réessayée.
  final String? transientError;

  /// Vrai si l'envoi s'est arrêté avant la fin (réseau coupé, session refusée).
  final bool interrupted;
  final List<OutboxEntry> sentEntries;
  final List<OutboxEntry> rejectedEntries;
}

/// Délai avant la prochaine tentative automatique : 10 s, 20 s, 40 s… plafonné à 15 min
/// (exposant borné : pas de dépassement d'entier après de nombreux échecs).
Duration backoff(int attempts) => Duration(seconds: math.min(900, 10 << math.min(7, math.max(0, attempts - 1))));

/// La file d'envoi, persistée dans un fichier de l'appareil : elle survit aux redémarrages.
class Outbox {
  Outbox(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final JsonFileStore _store;
  final DateTime Function() _clock;
  Future<FlushReport>? _running;
  Future<void> _lock = Future.value();

  /// La commande en cours d'envoi : jamais remplacée ni retirée pendant l'appel.
  String? _inFlight;

  Future<List<OutboxEntry>> entries({String? profileId, String? subjectId}) async {
    final raw = await _store.read();
    final all = raw == null
        ? <OutboxEntry>[]
        : (raw as List).map((x) => OutboxEntry.fromJson(Map<String, dynamic>.from(x as Map))).toList();
    return all.where((e) => (profileId == null || e.profileId == profileId) && (subjectId == null || e.subjectId == subjectId)).toList();
  }

  /// Fichier de la file illisible : renommé à côté, jamais effacé (un technicien peut le récupérer).
  /// La file repart vide. Rend le chemin du fichier mis de côté.
  Future<String> setAside() async {
    final f = _store.file;
    final dest = '${f.path}.illisible-${_clock().millisecondsSinceEpoch}';
    await f.rename(dest);
    return dest;
  }

  /// Lire, modifier, écrire — une seule mise à jour à la fois, relue sur le disque :
  /// une saisie pendant un envoi n'est jamais écrasée.
  Future<void> _update(void Function(List<OutboxEntry> all) change) {
    final next = _lock.then((_) async {
      final all = await entries();
      change(all);
      await _store.write(all.map((e) => e.toJson()).toList());
    });
    _lock = next.catchError((_) {});
    return next;
  }

  /// Ajoute une commande ; un même identifiant n'entre jamais deux fois.
  ///
  /// Les requêtes sont des instantanés (upsert par identifiant) : une commande sur la même ressource
  /// remplace la précédente du même producteur si elle est encore la dernière de cette ressource en file,
  /// n'est pas en cours d'envoi et n'a pas été refusée — le serveur n'a besoin que du dernier état.
  /// Les pièces jointes de l'ancienne commande sont gardées (une photo prise avant reste à déposer).
  Future<void> enqueue(OutboxEntry entry, {bool replaceTail = true}) {
    return _update((all) {
      if (all.any((e) => e.id == entry.id)) return;
      if (replaceTail) {
        final same = all.where((e) => e.subjectId == entry.subjectId && e.profileId == entry.profileId).toList();
        if (same.isNotEmpty) {
          final tail = same.last;
          if (tail.resource == entry.resource && tail.id != _inFlight && !tail.rejected) {
            final i = all.indexOf(tail);
            final paths = {for (final a in entry.attachments) a.uploadPath};
            all[i] = OutboxEntry(
              id: entry.id,
              method: entry.method,
              path: entry.path,
              payload: entry.payload,
              profileId: entry.profileId,
              subjectId: entry.subjectId,
              label: entry.label,
              createdAt: tail.createdAt, // garde sa place dans l'ordre
              attachments: [...tail.attachments.where((a) => !paths.contains(a.uploadPath)), ...entry.attachments],
            );
            return;
          }
        }
      }
      all.add(entry);
    });
  }

  /// L'agent a lu le refus : la commande quitte la file (la suite du producteur se débloque).
  Future<void> discard(String id) => _update((all) => all.removeWhere((e) => e.id == id && e.id != _inFlight));

  /// Retire toutes les commandes en attente d'un compte (déconnexion forcée).
  Future<void> discardProfile(String profileId) => _update((all) => all.removeWhere((e) => e.profileId == profileId && e.id != _inFlight));

  /// Remet une commande refusée dans la file, sans délai.
  /// Remet une commande refusée dans la file. Elle part telle quelle : sans la date de dernière
  /// modification connue, elle remplace une version modifiée ailleurs entre-temps (ADR-0004).
  Future<void> requeue(String id) => _update((all) {
    for (final x in all.where((e) => e.id == id)) {
      x.rejected = false;
      x.nextAttemptAt = null;
      x.payload.remove('base_edited_at');
    }
  });

  /// Envoie, dans l'ordre de saisie, les commandes du compte connecté.
  ///
  /// - Succès → retirée.
  /// - Refus du serveur → marquée refusée ; la suite **du même producteur** attend
  ///   (un champ ne part jamais après un producteur refusé) ; les autres producteurs continuent.
  /// - Erreur transitoire (réseau, session) → délai croissant, on s'arrête pour garder l'ordre.
  ///
  /// [force] ignore les délais (bouton « Synchroniser »). Chaque pas est écrit sur le
  /// disque : une coupure ne perd ni ne duplique rien, les commandes sont rejouables.
  Future<FlushReport> flush(String profileId, Sender send, {Uploader? upload, bool force = false}) {
    return _running ??= _flush(profileId, send, upload, force).whenComplete(() => _running = null);
  }

  Future<FlushReport> _flush(String profileId, Sender send, Uploader? upload, bool force) async {
    var sent = 0, rejected = 0;
    final sentEntries = <OutboxEntry>[], rejectedEntries = <OutboxEntry>[];
    String? transient;
    var interrupted = false;
    final now = _clock();
    final all = (await entries(profileId: profileId))..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final blocked = <String>{};
    for (final entry in all) {
      if (blocked.contains(entry.subjectId)) continue;
      if (entry.rejected) {
        blocked.add(entry.subjectId);
        continue;
      }
      if (!force && entry.nextAttemptAt != null && entry.nextAttemptAt!.isAfter(now)) {
        blocked.add(entry.subjectId);
        continue;
      }
      _inFlight = entry.id;
      try {
        // Une photo disparue du téléphone ne peut plus partir : la fiche part sans elle plutôt que
        // de bloquer la file pour toujours (le serveur garde alors la photo qu'il avait déjà).
        final lost = <String>{};
        for (final a in entry.attachments) {
          if (upload == null) throw StateError('pièce jointe sans dépôt configuré');
          if (!File(a.localPath).existsSync()) {
            lost.add(a.uploadPath.split('/').last);
            continue;
          }
          await upload(a);
        }
        await send(lost.isEmpty ? entry : entry.withoutReferences(lost));
        _inFlight = null;
        await _update((all) => all.removeWhere((e) => e.id == entry.id));
        sent++;
        sentEntries.add(entry);
      } catch (e) {
        _inFlight = null;
        final message = errorMessage(e);
        final definitive = isDefinitiveRefusal(e);
        await _update((all) {
          for (final x in all.where((x) => x.id == entry.id)) {
            x.attempts++;
            x.lastError = message;
            x.rejected = definitive;
            x.nextAttemptAt = definitive ? null : _clock().add(backoff(x.attempts));
          }
        });
        blocked.add(entry.subjectId);
        if (!definitive) {
          transient = message;
          // Réseau ou session : on s'arrête. Sinon (500, erreur inattendue) seul ce producteur attend,
          // les autres continuent : l'ordre n'est garanti que par producteur.
          if (isConnectivityError(e)) {
            interrupted = true;
            break;
          }
          continue;
        }
        rejected++;
        rejectedEntries.add(
          entry
            ..rejected = true
            ..lastError = message,
        );
      }
    }
    final remaining = (await entries(profileId: profileId)).where((e) => !e.rejected).length;
    return FlushReport(
      sent: sent,
      rejected: rejected,
      remaining: remaining,
      transientError: transient,
      interrupted: interrupted,
      sentEntries: sentEntries,
      rejectedEntries: rejectedEntries,
    );
  }
}
