import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'json_store.dart';
import 'model/models.dart';
import 'photos.dart';
import 'sync/outbox.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Tout ce que l'app sait faire, sans écran : session, données gardées sur le téléphone,
/// file d'envoi et synchronisation avec le serveur Guis. Les écrans ne parlent qu'à cette classe.
class AppServices extends ChangeNotifier {
  AppServices._(this.api, this._session, this._data, this.outbox, this.photosDir);

  final Api api;
  final JsonFileStore _session;
  final JsonFileStore _data;
  final Outbox outbox;

  /// Photos prises sur le téléphone (gardées après dépôt pour l'aperçu).
  final Directory photosDir;

  Account? account;
  Lists lists = const Lists();
  final Map<String, Producer> producers = {};

  final Map<String, Field> fields = {};
  DateTime? syncedAt;

  /// Le compte à qui appartiennent les données gardées sur le téléphone : un autre compte qui se
  /// connecte ne les voit jamais (elles sont effacées avant son premier chargement).
  String? _owner;

  /// Commandes du compte encore dans la file (en attente ou refusées).
  List<OutboxEntry> pending = const [];
  bool syncing = false;

  /// Producteurs envoyés lors de la dernière synchronisation (pastille « Envoyé »).
  Set<String> recentlySent = const {};
  String? lastSyncError;

  /// La session n'est plus acceptée par le serveur : il faut se reconnecter.
  bool sessionExpired = false;

  Timer? _timer;

  /// Lance un envoi après chaque saisie (désactivé dans les tests pour garder l'ordre maîtrisé).
  bool syncAfterSave = true;

  /// Synchronisation périodique (désactivée dans les tests d'écran).
  bool autoSyncEnabled = true;

  static Future<AppServices> open(Directory dir, Api api, {DateTime Function()? clock}) async {
    final s = AppServices._(
      api,
      JsonFileStore(File('${dir.path}/session.json')),
      JsonFileStore(File('${dir.path}/data.json')),
      Outbox(JsonFileStore(File('${dir.path}/outbox.json')), clock: clock),
      Directory('${dir.path}/photos'),
    );
    await s._load();
    return s;
  }

  Future<void> _load() async {
    final session = await _session.read();
    if (session is Map) {
      api.token = session['token'] as String?;
      account = Account.fromJson(Map<String, dynamic>.from(session['account'] as Map));
    }
    final data = await _data.read();
    if (data is Map) {
      lists = Lists.fromJson(Map<String, dynamic>.from((data['lists'] as Map?) ?? const {}));
      for (final p in (data['producers'] as List?) ?? const []) {
        final pr = Producer.fromJson(Map<String, dynamic>.from(p as Map));
        producers[pr.id] = pr;
      }
      for (final f in (data['fields'] as List?) ?? const []) {
        final field = Field.fromJson(Map<String, dynamic>.from(f as Map));
        fields[field.id] = field;
      }
      syncedAt = DateTime.tryParse(data['synced_at'] as String? ?? '');
      // Données écrites avant l'ajout du propriétaire : elles sont celles de la session en cours.
      _owner = data['owner'] as String? ?? account?.id;
    }
    await _reloadPending();
  }

  Future<void> _saveData() => _data.write({
    'lists': lists.toJson(),
    'producers': [for (final p in producers.values) p.toJson()],
    'fields': fields.values.toList(),
    'synced_at': syncedAt?.toUtc().toIso8601String(),
    'owner': _owner,
  });

  Future<void> _reloadPending() async {
    pending = account == null ? const [] : await outbox.entries(profileId: account!.id);
  }

  bool get signedIn => account != null && api.token != null;
  bool get hasData => syncedAt != null;
  int get pendingCount => pending.where((e) => !e.rejected).length;
  List<OutboxEntry> get rejected => pending.where((e) => e.rejected).toList();
  bool isPending(String producerId) => pending.any((e) => e.subjectId == producerId);
  OutboxEntry? rejectionFor(String producerId) => pending.where((e) => e.subjectId == producerId && e.rejected).firstOrNull;

  /// Producteurs reçus (pour un agent : ses producteurs attribués, ADR-0002), triés par village puis
  /// par nom ; les producteurs sans village viennent en dernier.
  List<Producer> get producerList => producers.values.toList()
    ..sort((a, b) {
      final va = fold(a.village ?? ''), vb = fold(b.village ?? '');
      if (va.isEmpty != vb.isEmpty) return va.isEmpty ? 1 : -1;
      final byVillage = va.compareTo(vb);
      return byVillage != 0 ? byVillage : fold('${a.lastName} ${a.firstName}').compareTo(fold('${b.lastName} ${b.firstName}'));
    });

  /// Communes des producteurs reçus, triées (filtre de la liste quand il y en a plusieurs).
  List<String> get producerCommunes => ({
    for (final p in producers.values)
      if (p.commune != null && p.commune!.isNotEmpty) p.commune!,
  }.toList()..sort());

  List<Field> fieldsOf(String producerId) => fields.values.where((f) => f.producerId == producerId).toList();

  // --- Session -------------------------------------------------------------------------------

  /// Connexion, puis premier chargement des données (réseau nécessaire).
  Future<void> signIn(String phone, String password) async {
    final r = await api.login(phone, password);
    api.token = r['token'] as String;
    account = Account.fromJson(Map<String, dynamic>.from(r['user'] as Map));
    sessionExpired = false;
    if (_owner != account!.id) {
      _clearCache();
      _owner = account!.id;
      await _saveData();
    }
    await _session.write({'token': api.token, 'account': account!.toJson()});
    await _reloadPending();
    notifyListeners();
    try {
      await sync(force: true);
    } catch (_) {
      /* la liste se chargera à la prochaine synchronisation */
    }
  }

  /// Déconnexion. Les saisies non envoyées restent sur le téléphone et partiront à la
  /// prochaine connexion du même compte. Le reste des données (producteurs reçus, photos déjà
  /// envoyées) est effacé : le téléphone peut passer à un autre agent.
  Future<void> signOut() async {
    stopAutoSync();
    try {
      await api.sendJson('POST', '/api/auth/logout', {});
    } catch (_) {}
    final keep = {for (final e in pending) e.subjectId};
    api.token = null;
    account = null;
    sessionExpired = false;
    pending = const [];
    _clearCache(keepSubjects: keep);
    await _saveData();
    await _session.write(null);
    await _deleteUnusedPhotos();
    notifyListeners();
  }

  /// Vide les données reçues ; garde seulement les producteurs (et leurs champs) dont une saisie
  /// attend encore l'envoi.
  void _clearCache({Set<String> keepSubjects = const {}}) {
    producers.removeWhere((id, _) => !keepSubjects.contains(id));
    fields.removeWhere((_, f) => !keepSubjects.contains(f.producerId));
    lists = const Lists();
    syncedAt = null;
    recentlySent = const {};
    lastSyncError = null;
  }

  /// Efface les photos qu'aucune saisie en attente (de n'importe quel compte) ne doit encore déposer.
  Future<void> _deleteUnusedPhotos() async {
    try {
      if (!await photosDir.exists()) return;
      final needed = {
        for (final e in await outbox.entries())
          for (final a in e.attachments) File(a.localPath).absolute.path,
      };
      await for (final f in photosDir.list()) {
        if (f is File && !needed.contains(f.absolute.path)) await f.delete();
      }
    } on FileSystemException {
      /* nettoyage au mieux : une photo restée sera effacée à la prochaine déconnexion */
    }
  }

  // --- Saisie ---------------------------------------------------------------------------------

  /// Enregistre un producteur sur le téléphone et le met dans la file d'envoi.
  Future<void> saveProducer(Producer p, {List<String> deletedSeedIds = const [], LocalPhoto? photo}) async {
    if (photo != null) p = p.copyWith(photoId: photo.id);
    if (p.consentAt == null) throw StateError('consentement manquant');
    final path = '/api/app/producers/${p.id}';
    // Un instantané précédent encore en file sera remplacé : on garde ses suppressions de semences.
    final previous = pending.where((e) => e.path == path && !e.rejected).lastOrNull;
    final deleted = {...deletedSeedIds, ...((previous?.payload['deleted_seed_ids'] as List?) ?? const []).cast<String>()};
    producers[p.id] = p;
    await _saveData();
    await outbox.enqueue(
      OutboxEntry(
        id: newId(),
        method: 'PUT',
        path: path,
        payload: p.toPayload(deletedSeedIds: deleted.toList()),
        profileId: account!.id,
        subjectId: p.id,
        label: 'Producteur — ${p.fullName}',
        createdAt: DateTime.now(),
        attachments: _attach(photo),
      ),
    );
    await _reloadPending();
    notifyListeners();
    if (syncAfterSave) unawaited(sync().catchError((_) => null));
  }

  /// Enregistre un champ sur le téléphone et le met dans la file d'envoi, derrière son producteur
  /// (même sujet : le champ ne part jamais avant le producteur).
  Future<void> saveField(Field f, {LocalPhoto? photo}) async {
    if (photo != null) f = f.copyWith(photoId: photo.id);
    fields[f.id] = f;
    await _saveData();
    final p = producers[f.producerId];
    await outbox.enqueue(
      OutboxEntry(
        id: newId(),
        method: 'PUT',
        path: '/api/app/fields/${f.id}',
        payload: f.toPayload(),
        profileId: account!.id,
        subjectId: f.producerId,
        label: 'Champ — ${f.name ?? p?.fullName ?? ''}',
        createdAt: DateTime.now(),
        attachments: _attach(photo),
      ),
    );
    await _reloadPending();
    notifyListeners();
    if (syncAfterSave) unawaited(sync().catchError((_) => null));
  }

  List<OutboxAttachment> _attach(LocalPhoto? photo) => [
    if (photo != null)
      OutboxAttachment(localPath: photo.path, uploadPath: '/api/photos/${photo.id}', contentType: 'image/jpeg', headers: photo.headers),
  ];

  /// La photo sur le téléphone, si elle y a été prise.
  File? localPhoto(String? id) {
    if (id == null) return null;
    final f = File('${photosDir.path}/$id.jpg');
    return f.existsSync() ? f : null;
  }

  /// L'agent écarte une commande refusée (la suite du producteur se débloque).
  Future<void> discard(OutboxEntry e) async {
    await outbox.discard(e.id);
    await _reloadPending();
    notifyListeners();
  }

  /// L'agent renvoie une commande refusée (après correction côté serveur, par exemple).
  Future<void> retry(OutboxEntry e) async {
    await outbox.requeue(e.id);
    await _reloadPending();
    await sync(force: true);
  }

  // --- Synchronisation ------------------------------------------------------------------------

  /// Envoie la file, puis recharge les données du serveur si tout est parti.
  Future<FlushReport?> sync({bool force = false}) async {
    if (!signedIn || syncing) return null;
    syncing = true;
    notifyListeners();
    FlushReport? report;
    try {
      report = await outbox.flush(account!.id, _send, upload: _upload, force: force);
      lastSyncError = report.transientError;
      recentlySent = {for (final e in report.sentEntries) e.subjectId};
      // Réseau coupé : on rechargera plus tard. Un envoi en attente sur un seul producteur n'empêche pas
      // le rechargement (sa version locale est gardée).
      if (!report.interrupted) await refresh();
    } catch (e) {
      lastSyncError = errorMessage(e);
      if (e is ApiException && e.status == 401) sessionExpired = true;
    } finally {
      syncing = false;
      await _reloadPending();
      notifyListeners();
    }
    return report;
  }

  Future<Object?> _send(OutboxEntry e) => _watch(() => api.sendJson(e.method, e.path, e.payload));

  Future<void> _upload(OutboxAttachment a) => _watch(() async {
    final bytes = await File(a.localPath).readAsBytes();
    return api.putBytes(a.uploadPath, bytes, contentType: a.contentType, headers: a.headers);
  });

  /// Repère une session refusée par le serveur pendant l'envoi.
  Future<Object?> _watch(Future<Object?> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      if (e.status == 401) sessionExpired = true;
      rethrow;
    }
  }

  /// Recharge listes, producteurs et champs. Ce qui a encore des envois en attente garde sa
  /// version locale : une saisie pas encore partie n'est jamais écrasée.
  Future<void> refresh() async {
    final data = Map<String, dynamic>.from(await api.get('/api/app/bootstrap') as Map);
    await _reloadPending();
    final keep = {for (final e in pending) e.subjectId};
    lists = Lists.fromJson(Map<String, dynamic>.from(data['lists'] as Map));
    final user = data['user'];
    if (account != null && user is Map && user['communes'] is List) {
      account = account!.withCommunes([for (final c in user['communes'] as List) c as String]);
      await _session.write({'token': api.token, 'account': account!.toJson()});
    }

    final seedsBy = <String, List<Seed>>{};
    for (final s in (data['seeds'] as List)) {
      final m = Map<String, dynamic>.from(s as Map);
      (seedsBy[m['producer_id'] as String] ??= []).add(Seed.fromJson(m));
    }
    final next = <String, Producer>{};
    for (final p in (data['producers'] as List)) {
      final m = Map<String, dynamic>.from(p as Map);
      final id = m['id'] as String;
      next[id] = keep.contains(id) && producers.containsKey(id) ? producers[id]! : Producer.fromJson(m, seeds: seedsBy[id] ?? const []);
    }
    for (final id in keep) {
      if (producers.containsKey(id)) next[id] = producers[id]!;
    }

    final nextFields = <String, Field>{};
    for (final f in (data['fields'] as List)) {
      final field = Field.fromJson(Map<String, dynamic>.from(f as Map));
      nextFields[field.id] = field;
    }
    for (final f in fields.values) {
      if (keep.contains(f.producerId)) nextFields[f.id] = f;
    }

    producers
      ..clear()
      ..addAll(next);
    fields
      ..clear()
      ..addAll(nextFields);
    syncedAt = DateTime.now();
    sessionExpired = false;
    await _saveData();
  }

  /// Synchronisation automatique toutes les minutes (sans effet hors ligne : délai croissant).
  void startAutoSync() {
    if (!autoSyncEnabled) return;
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => sync().catchError((_) => null));
  }

  void stopAutoSync() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stopAutoSync();
    super.dispose();
  }
}
