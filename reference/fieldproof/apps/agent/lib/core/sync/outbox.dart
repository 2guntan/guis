import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, StorageException, AuthException;

import '../json_store.dart';

/// Une pièce jointe d'une commande : un fichier de l'appareil déposé dans Storage à un
/// chemin déterministe **avant** l'appel de la RPC qui le référence.
class OutboxAttachment {
  const OutboxAttachment({required this.localPath, required this.storagePath, required this.contentType});

  final String localPath;
  final String storagePath;
  final String contentType;

  Map<String, dynamic> toJson() => {'local_path': localPath, 'storage_path': storagePath, 'content_type': contentType};

  factory OutboxAttachment.fromJson(Map<String, dynamic> j) => OutboxAttachment(
        localPath: j['local_path'] as String,
        storagePath: j['storage_path'] as String,
        contentType: j['content_type'] as String,
      );
}

/// Une commande en attente d'envoi : un appel de RPC, rattaché à un dossier client.
///
/// Repris de l'outbox Agriva (elle-même transplantée de SOLIR). Différences voulues
/// (ADR-0007) : l'ordre est garanti **par dossier** — un refus bloque la suite du même
/// dossier, jamais celle des autres — et les erreurs transitoires attendent un délai
/// croissant avant de repartir.
class OutboxEntry {
  OutboxEntry({
    required this.id,
    required this.rpc,
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

  /// Nom qualifié de la RPC (`dossier.save_draft`).
  final String rpc;
  final Map<String, dynamic> payload;

  /// Fichiers déposés avant l'appel, dans l'ordre ; le chemin étant déterministe, un
  /// dépôt repris après coupure ne crée pas de doublon.
  final List<OutboxAttachment> attachments;

  /// Le compte qui a saisi la commande : elle ne part que sous sa session.
  final String profileId;

  /// Le dossier client concerné (`file_id`) : l'ordre est garanti par dossier.
  final String subjectId;

  /// Libellé lisible par l'agent (« Brouillon — Awa DIATTA »).
  final String label;
  final DateTime createdAt;
  int attempts;

  /// Refusée par la base : ne repartira pas seule ; bloque la suite du même dossier.
  bool rejected;

  /// Dernier message reçu, tel que rendu par la base ou par le réseau.
  String? lastError;

  /// Pas d'envoi automatique avant cette date (délai croissant après une erreur transitoire).
  DateTime? nextAttemptAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'rpc': rpc,
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
        rpc: j['rpc'] as String,
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        profileId: j['profile_id'] as String,
        subjectId: j['subject_id'] as String,
        label: j['label'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        attachments: [
          for (final a in (j['attachments'] as List?) ?? const []) OutboxAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        attempts: j['attempts'] as int? ?? 0,
        rejected: j['rejected'] as bool? ?? false,
        lastError: j['last_error'] as String?,
        nextAttemptAt: DateTime.tryParse(j['next_attempt_at'] as String? ?? ''),
      );
}

/// Exécute une RPC nommée (`dossier_rpcs.dart`).
typedef RpcDispatcher = Future<Object?> Function(String rpc, Map<String, dynamic> payload);

/// Dépose une pièce jointe ; un chemin déjà déposé est un succès (`dossier_rpcs.dart`).
typedef Uploader = Future<void> Function(OutboxAttachment attachment);

class FlushReport {
  const FlushReport({required this.sent, required this.rejected, required this.remaining, this.transientError, this.sentEntries = const [], this.rejectedEntries = const []});

  final int sent;
  final int rejected;
  final int remaining;

  /// Présent quand l'envoi s'est arrêté faute de réseau ou de session : on réessaiera.
  final String? transientError;
  final List<OutboxEntry> sentEntries;
  final List<OutboxEntry> rejectedEntries;
}

/// Refus définitif de la base (`raise exception`, contrainte, droit) : rejouer ne
/// changera rien. Tout le reste — réseau, session expirée (`PGRST…`), conflit
/// transitoire — se réessaie plus tard, dans le même ordre.
bool isDefinitiveRefusal(Object error) {
  // Storage : un 4xx (politique, taille, type) est un refus ; 401, 408 et 429 se réessaient.
  if (error is StorageException) {
    final status = int.tryParse(error.statusCode ?? '') ?? 0;
    if (error.message.toLowerCase().contains('jwt')) return false;
    return status >= 400 && status < 500 && status != 401 && status != 408 && status != 429;
  }
  if (error is AuthException) return false;
  if (error is! PostgrestException) return false;
  final code = error.code ?? '';
  if (!RegExp(r'^[0-9A-Z]{5}$').hasMatch(code)) return false;
  // 08 connexion, 40 sérialisation / interblocage, 53 ressources, 57 intervention, 58 système
  return !const {'08', '40', '53', '57', '58'}.contains(code.substring(0, 2));
}

/// Le message du serveur, débarrassé du préfixe technique (« submit_file: »).
String errorMessage(Object error) {
  final raw = switch (error) {
    PostgrestException e => e.message,
    StorageException e => e.message,
    AuthException e => e.message,
    SocketException _ => 'Pas de réseau',
    TimeoutException _ => 'Délai dépassé',
    _ => error.toString(),
  };
  return raw.replaceFirst(RegExp(r'^[a-z_]+: '), '');
}

/// Délai avant la prochaine tentative automatique : 10 s, 20 s, 40 s… plafonné à 15 min.
Duration backoff(int attempts) => Duration(seconds: math.min(900, 10 * math.pow(2, math.max(0, attempts - 1)).toInt()));

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
    return all
        .where((e) => (profileId == null || e.profileId == profileId) && (subjectId == null || e.subjectId == subjectId))
        .toList();
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
  /// [replaceTail] : une commande « instantané » (le brouillon complet) remplace la
  /// précédente du même dossier si elle est encore la dernière en file et n'est pas
  /// en cours d'envoi — le serveur n'a besoin que du dernier état.
  Future<void> enqueue(OutboxEntry entry, {bool replaceTail = false}) {
    return _update((all) {
      if (all.any((e) => e.id == entry.id)) return;
      if (replaceTail) {
        final same = all.where((e) => e.subjectId == entry.subjectId && e.profileId == entry.profileId).toList();
        if (same.isNotEmpty) {
          final tail = same.last;
          if (tail.rpc == entry.rpc && tail.id != _inFlight && !tail.rejected) {
            final i = all.indexOf(tail);
            all[i] = OutboxEntry(
              id: entry.id,
              rpc: entry.rpc,
              payload: entry.payload,
              profileId: entry.profileId,
              subjectId: entry.subjectId,
              label: entry.label,
              createdAt: tail.createdAt, // garde sa place dans l'ordre
              attachments: entry.attachments,
            );
            return;
          }
        }
      }
      all.add(entry);
    });
  }

  /// L'agent a lu le refus : la commande quitte la file (la suite du dossier se débloque).
  Future<void> discard(String id) => _update((all) => all.removeWhere((e) => e.id == id && e.id != _inFlight));

  /// Retire toutes les commandes en attente d'un dossier.
  Future<void> discardSubject(String subjectId) => _update((all) => all.removeWhere((e) => e.subjectId == subjectId && e.id != _inFlight));

  /// Remet une commande refusée dans la file, sans délai.
  Future<void> requeue(String id) => _update((all) {
        for (final x in all.where((e) => e.id == id)) {
          x.rejected = false;
          x.nextAttemptAt = null;
        }
      });

  /// Envoie, dans l'ordre de saisie, les commandes du compte connecté.
  ///
  /// - Succès → retirée.
  /// - Refus de la base → marquée refusée ; la suite **du même dossier** attend
  ///   (une soumission ne part jamais après un brouillon refusé) ; les autres dossiers continuent.
  /// - Erreur transitoire (réseau, session) → délai croissant, on s'arrête pour garder l'ordre.
  ///
  /// [force] ignore les délais (bouton « Synchroniser »). Chaque pas est écrit sur le
  /// disque : une coupure ne perd ni ne duplique rien, les commandes sont rejouables.
  Future<FlushReport> flush(String profileId, RpcDispatcher call, {Uploader? upload, bool force = false}) {
    return _running ??= _flush(profileId, call, upload, force).whenComplete(() => _running = null);
  }

  Future<FlushReport> _flush(String profileId, RpcDispatcher call, Uploader? upload, bool force) async {
    var sent = 0, rejected = 0;
    final sentEntries = <OutboxEntry>[], rejectedEntries = <OutboxEntry>[];
    String? transient;
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
        for (final a in entry.attachments) {
          if (upload == null) throw StateError('pièce jointe sans dépôt configuré');
          await upload(a);
        }
        await call(entry.rpc, entry.payload);
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
          break;
        }
        rejected++;
        rejectedEntries.add(entry
          ..rejected = true
          ..lastError = message);
      }
    }
    final remaining = (await entries(profileId: profileId)).where((e) => !e.rejected).length;
    return FlushReport(
        sent: sent, rejected: rejected, remaining: remaining, transientError: transient, sentEntries: sentEntries, rejectedEntries: rejectedEntries);
  }
}
