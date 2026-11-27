import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'error_log.dart';
import 'json_store.dart';
import 'model/models.dart';
import 'photos.dart';
import 'sync/outbox.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Tout ce que l'app sait faire, sans écran : session, données gardées sur le téléphone,
/// file d'envoi et synchronisation avec le serveur Guis. Les écrans ne parlent qu'à cette classe.
class AppServices extends ChangeNotifier {
  AppServices._(this.api, this._session, this._data, this.outbox, this.photosDir, this._draftStore, this.errorLog, this.appBuild);

  final Api api;
  final JsonFileStore _session;
  final JsonFileStore _data;
  final Outbox outbox;

  /// Photos prises sur le téléphone (gardées après dépôt pour l'aperçu).
  final Directory photosDir;

  final JsonFileStore _draftStore;
  Map<String, dynamic>? _draft;
  Future<void> _draftLock = Future.value();

  /// Erreurs inattendues de l'app (écrans, synchronisation), gardées sur le téléphone.
  final ErrorLog errorLog;

  /// Problème trouvé au démarrage et réparé (fichier illisible mis de côté) : affiché à l'agent.
  String? recoveryNotice;

  /// Numéro de build de l'app installée (`--build-number` de la CI) ; null en test.
  final int? appBuild;

  /// Versions de l'app réglées sur le serveur (audit M10) : `min_build`, `latest_build`, `apk_url`.
  Map<String, dynamic> appVersions = const {};

  int? get _minBuild => (appVersions['min_build'] as num?)?.toInt();
  int? get _latestBuild => (appVersions['latest_build'] as num?)?.toInt();
  String? get apkUrl => appVersions['apk_url'] as String?;

  /// L'app est trop ancienne pour le serveur : elle demande la mise à jour avant tout.
  bool get updateRequired => appBuild != null && _minBuild != null && appBuild! < _minBuild!;

  /// Une version plus récente existe (bandeau, sans bloquer).
  bool get updateAvailable => appBuild != null && _latestBuild != null && appBuild! < _latestBuild!;

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
  bool _syncAgain = false;

  /// Lance un envoi après chaque saisie (désactivé dans les tests pour garder l'ordre maîtrisé).
  bool syncAfterSave = true;

  /// Synchronisation périodique (désactivée dans les tests d'écran).
  bool autoSyncEnabled = true;

  static Future<AppServices> open(Directory dir, Api api, {DateTime Function()? clock, int? appBuild}) async {
    final s = AppServices._(
      api,
      JsonFileStore(File('${dir.path}/session.json')),
      JsonFileStore(File('${dir.path}/data.json')),
      Outbox(JsonFileStore(File('${dir.path}/outbox.json')), clock: clock),
      Directory('${dir.path}/photos'),
      JsonFileStore(File('${dir.path}/draft.json')),
      ErrorLog(File('${dir.path}/erreurs.log')),
      appBuild,
    );
    await s._load();
    return s;
  }

  /// Relit les fichiers du téléphone. Un fichier illisible (coupure pendant une écriture, mémoire
  /// défectueuse, ancienne version) ne bloque jamais le démarrage : session et données reçues se
  /// refont avec le réseau ; la file d'envoi, elle, n'est jamais effacée mais mise de côté.
  Future<void> _load() async {
    var damaged = false;
    try {
      final session = await _session.read();
      if (session is Map) {
        api.token = session['token'] as String?;
        account = Account.fromJson(Map<String, dynamic>.from(session['account'] as Map));
      }
    } catch (e, st) {
      await errorLog.write(e, st);
      api.token = null;
      account = null;
    }
    try {
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
        if (data['app'] is Map) appVersions = Map<String, dynamic>.from(data['app'] as Map);
      }
    } catch (e, st) {
      damaged = true;
      await errorLog.write(e, st);
      producers.clear();
      fields.clear();
      lists = const Lists();
      syncedAt = null;
      _owner = account?.id;
    }
    try {
      await outbox.entries();
    } catch (e, st) {
      damaged = true;
      await errorLog.write(e, st);
      final aside = await outbox.setAside();
      recoveryNotice =
          'La file d\'envoi était illisible : elle a été mise de côté sur le téléphone (${aside.split('/').last}). '
          'Prévenez le coordinateur et ne supprimez pas les données de l\'app.';
    }
    try {
      final d = await _draftStore.read();
      _draft = d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (e, st) {
      await errorLog.write(e, st);
      _draft = null;
    }
    await _reloadPending();
    // Après une réparation, les photos restent : elles peuvent servir à récupérer la file mise de côté.
    if (!damaged) await _deleteUnusedPhotos(keepShown: true);
  }

  /// JSON de chaque producteur et champ, gardé tant que l'objet (immuable) ne change pas : un
  /// enregistrement ne réencode que ce qui a changé, pas des milliers de contours (compte admin).
  final _encoded = Expando<String>();

  String _json(Object o) => _encoded[o] ??= jsonEncode(o);

  Future<void> _saveData() => _data.writeText(
    '{"lists":${jsonEncode(lists.toJson())},'
    '"producers":[${producers.values.map(_json).join(',')}],'
    '"fields":[${fields.values.map(_json).join(',')}],'
    '"synced_at":${jsonEncode(syncedAt?.toUtc().toIso8601String())},'
    '"owner":${jsonEncode(_owner)},'
    '"app":${jsonEncode(appVersions)}}',
  );

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

  // --- Saisie interrompue ----------------------------------------------------------------------

  /// Saisie en cours sur un écran (`producer`, `field`), écrite sur le disque quand l'app passe en
  /// arrière-plan, avant l'appareil photo et à chaque point du tour : Android peut arrêter l'app pendant
  /// ce temps. Reprise au lancement suivant, pour le même compte seulement.
  Map<String, dynamic>? get draft => _draft != null && account != null && _draft!['profile'] == account!.id ? _draft : null;

  /// Écrit (ou retire, si [value] est null) une partie de la saisie en cours.
  Future<void> saveDraft(String part, Map<String, dynamic>? value) {
    final next = _draftLock.then((_) async {
      if (account == null) return;
      final d = {...?draft, 'profile': account!.id};
      if (value == null) {
        d.remove(part);
      } else {
        d[part] = value;
      }
      _draft = d.length > 1 ? d : null;
      await _draftStore.write(_draft);
    });
    _draftLock = next.catchError((_) {});
    return next;
  }

  Future<void> clearDraft() {
    final next = _draftLock.then((_) async {
      _draft = null;
      await _draftStore.write(null);
    });
    _draftLock = next.catchError((_) {});
    return next;
  }

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
      await clearDraft();
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
    await clearDraft();
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
  /// Avec [keepShown], garde aussi celles des producteurs et champs du téléphone (aperçu) et de la saisie
  /// interrompue : ne restent effacées que les photos prises puis abandonnées (fiche quittée sans enregistrer).
  Future<void> _deleteUnusedPhotos({bool keepShown = false}) async {
    try {
      if (!await photosDir.exists()) return;
      String path(String id) => File('${photosDir.path}/$id.jpg').absolute.path;
      final needed = {
        for (final e in await outbox.entries())
          for (final a in e.attachments) File(a.localPath).absolute.path,
        if (keepShown) ...[
          for (final p in producers.values)
            if (p.photoId != null) path(p.photoId!),
          for (final f in fields.values)
            if (f.photoId != null) path(f.photoId!),
          for (final part in [...?_draft?.values.whereType<Map>()]) ...[
            if (part['camera'] is String) path(part['camera'] as String),
            if (part['photo'] is Map && (part['photo'] as Map)['id'] is String) path((part['photo'] as Map)['id'] as String),
          ],
        ],
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
    if (!signedIn) return null;
    if (syncing) {
      // Demande de l'agent (« Synchroniser », « Renvoyer ») pendant un envoi : relancée juste après.
      if (force) _syncAgain = true;
      return null;
    }
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
    } catch (e, st) {
      lastSyncError = errorMessage(e);
      if (e is ApiException && e.status == 401) sessionExpired = true;
      if (e is! ApiException && !isConnectivityError(e)) unawaited(errorLog.write(e, st));
    } finally {
      syncing = false;
      await _reloadPending();
      notifyListeners();
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(sync(force: true).catchError((_) => null));
      }
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
    final data = Map<String, dynamic>.from(await api.get('/api/app/bootstrap', timeLimit: Api.bootstrapTimeout) as Map);
    await _reloadPending();
    final keep = {for (final e in pending) e.subjectId};
    lists = Lists.fromJson(Map<String, dynamic>.from(data['lists'] as Map));
    if (data['app'] is Map) appVersions = Map<String, dynamic>.from(data['app'] as Map);
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
