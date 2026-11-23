import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'json_store.dart';
import 'model/models.dart';
import 'sync/outbox.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Tout ce que l'app sait faire, sans écran : session, données gardées sur le téléphone,
/// file d'envoi et synchronisation avec le serveur Guis. Les écrans ne parlent qu'à cette classe.
class AppServices extends ChangeNotifier {
  AppServices._(this.api, this._session, this._data, this.outbox);

  final Api api;
  final JsonFileStore _session;
  final JsonFileStore _data;
  final Outbox outbox;

  Account? account;
  Lists lists = const Lists();
  final Map<String, Producer> producers = {};

  /// Champs tels que reçus ou saisis (typés au ticket 03).
  final Map<String, Map<String, dynamic>> fields = {};
  DateTime? syncedAt;

  /// Commandes du compte encore dans la file (en attente ou refusées).
  List<OutboxEntry> pending = const [];
  bool syncing = false;
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
        final m = Map<String, dynamic>.from(f as Map);
        fields[m['id'] as String] = m;
      }
      syncedAt = DateTime.tryParse(data['synced_at'] as String? ?? '');
    }
    await _reloadPending();
  }

  Future<void> _saveData() => _data.write({
    'lists': lists.toJson(),
    'producers': [for (final p in producers.values) p.toJson()],
    'fields': fields.values.toList(),
    'synced_at': syncedAt?.toUtc().toIso8601String(),
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

  /// Producteurs triés par nom.
  List<Producer> get producerList =>
      producers.values.toList()..sort((a, b) => fold('${a.lastName} ${a.firstName}').compareTo(fold('${b.lastName} ${b.firstName}')));

  List<Map<String, dynamic>> fieldsOf(String producerId) => fields.values.where((f) => f['producer_id'] == producerId).toList();

  // --- Session -------------------------------------------------------------------------------

  /// Connexion, puis premier chargement des données (réseau nécessaire).
  Future<void> signIn(String phone, String password) async {
    final r = await api.login(phone, password);
    api.token = r['token'] as String;
    account = Account.fromJson(Map<String, dynamic>.from(r['user'] as Map));
    sessionExpired = false;
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
  /// prochaine connexion du même compte.
  Future<void> signOut() async {
    stopAutoSync();
    try {
      await api.sendJson('POST', '/api/auth/logout', {});
    } catch (_) {}
    api.token = null;
    account = null;
    sessionExpired = false;
    pending = const [];
    await _session.write(null);
    notifyListeners();
  }

  // --- Saisie ---------------------------------------------------------------------------------

  /// Enregistre un producteur sur le téléphone et le met dans la file d'envoi.
  Future<void> saveProducer(Producer p, {List<String> deletedSeedIds = const []}) async {
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
      ),
    );
    await _reloadPending();
    notifyListeners();
    if (syncAfterSave) unawaited(sync().catchError((_) => null));
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
      if (report.transientError == null) await refresh();
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

    final nextFields = <String, Map<String, dynamic>>{};
    for (final f in (data['fields'] as List)) {
      final m = Map<String, dynamic>.from(f as Map);
      nextFields[m['id'] as String] = m;
    }
    for (final f in fields.values) {
      if (keep.contains(f['producer_id'])) nextFields[f['id'] as String] = f;
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
