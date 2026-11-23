import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'json_store.dart';
import 'model/dossier.dart';
import 'model/payloads.dart';
import 'sync/dossier_rpcs.dart';
import 'sync/outbox.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// État de la synchronisation affiché en tête des écrans.
@immutable
class SyncStatus {
  const SyncStatus({this.pending = 0, this.rejected = 0, this.syncing = false, this.lastSyncAt, this.lastError});

  final int pending;
  final int rejected;
  final bool syncing;
  final DateTime? lastSyncAt;
  final String? lastError;

  SyncStatus copyWith({int? pending, int? rejected, bool? syncing, DateTime? lastSyncAt, String? lastError, bool clearError = false}) =>
      SyncStatus(
        pending: pending ?? this.pending,
        rejected: rejected ?? this.rejected,
        syncing: syncing ?? this.syncing,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// Les dossiers saisis sur le téléphone, un fichier par compte.
class DossierStore {
  DossierStore(this._dir);

  final Directory _dir;
  Future<void> _lock = Future.value();

  JsonFileStore _store(String profileId) => JsonFileStore(File('${_dir.path}/dossiers_$profileId.json'));

  Future<List<Dossier>> all(String profileId) async {
    final raw = await _store(profileId).read();
    if (raw is! List) return [];
    return [for (final x in raw) Dossier.fromJson(Map<String, dynamic>.from(x as Map))];
  }

  Future<Dossier?> get(String profileId, String id) async {
    for (final d in await all(profileId)) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Lire, modifier, écrire — une mise à jour à la fois.
  Future<void> update(String profileId, void Function(List<Dossier> all) change) {
    final next = _lock.then((_) async {
      final list = await all(profileId);
      change(list);
      await _store(profileId).write([for (final d in list) d.toJson()]);
    });
    _lock = next.catchError((_) {});
    return next;
  }

  Future<void> put(Dossier d) => update(d.profileId, (list) {
        final i = list.indexWhere((x) => x.id == d.id);
        if (i < 0) {
          list.add(d);
        } else {
          list[i] = d;
        }
      });
}

/// Référentiels gardés sur le téléphone pour travailler hors ligne : régions, communes,
/// configurations des prêteurs, organisations, rattachements du compte.
class Referentials {
  Referentials({
    this.regions = const [],
    this.communes = const [],
    this.lenderConfigs = const [],
    this.organizations = const [],
    this.memberships = const [],
    this.fetchedAt,
  });

  final List<Map<String, dynamic>> regions;
  final List<Map<String, dynamic>> communes;
  final List<Map<String, dynamic>> lenderConfigs;
  final List<Map<String, dynamic>> organizations;
  final List<Map<String, dynamic>> memberships;
  final DateTime? fetchedAt;

  bool get isEmpty => regions.isEmpty;

  bool get isFieldAgent => memberships.any((m) => m['role'] == 'field_agent');

  /// Le prêteur du pilote : même règle que `save_draft` (un seul prêteur configuré du même
  /// côté bac à sable / production que l'organisation de l'agent, premier par code).
  String? get defaultLenderId {
    final agent = memberships.where((m) => m['role'] == 'field_agent').firstOrNull;
    if (agent == null) return null;
    final myOrg = organizations.where((o) => o['id'] == agent['organization_id']).firstOrNull;
    if (myOrg == null) return null;
    final candidates = [
      for (final o in organizations)
        if (o['is_sandbox'] == myOrg['is_sandbox'] && lenderConfigs.any((c) => c['organization_id'] == o['id'])) o,
    ]..sort((a, b) => (a['code'] as String).toLowerCase().compareTo((b['code'] as String).toLowerCase()));
    return candidates.isEmpty ? null : candidates.first['id'] as String;
  }

  Map<String, dynamic>? configFor(String? lenderId) {
    final id = lenderId ?? defaultLenderId;
    final row = lenderConfigs.where((c) => c['organization_id'] == id).firstOrNull;
    return row == null ? null : Map<String, dynamic>.from(row['config'] as Map);
  }

  String? lenderName(String? lenderId) =>
      organizations.where((o) => o['id'] == (lenderId ?? defaultLenderId)).firstOrNull?['name'] as String?;

  List<Map<String, dynamic>> communesOf(String? regionId) =>
      regionId == null ? const [] : communes.where((c) => c['region_id'] == regionId).toList();

  String? regionName(String? id) => regions.where((r) => r['id'] == id).firstOrNull?['name'] as String?;
  String? communeName(String? id) => communes.where((c) => c['id'] == id).firstOrNull?['name'] as String?;

  Map<String, dynamic> toJson() => {
        'regions': regions,
        'communes': communes,
        'lender_configs': lenderConfigs,
        'organizations': organizations,
        'memberships': memberships,
        'fetched_at': fetchedAt?.toUtc().toIso8601String(),
      };

  factory Referentials.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(Object? x) => [for (final e in (x as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    return Referentials(
      regions: l(j['regions']),
      communes: l(j['communes']),
      lenderConfigs: l(j['lender_configs']),
      organizations: l(j['organizations']),
      memberships: l(j['memberships']),
      fetchedAt: DateTime.tryParse(j['fetched_at'] as String? ?? ''),
    );
  }
}

/// Ce que les écrans partagent : le client Supabase, la file d'envoi, les dossiers
/// locaux, les référentiels, l'état de synchronisation.
class AgentServices {
  AgentServices({required this.client, required this.outbox, required this.dossiers, required this.dir, required this.photos});

  final SupabaseClient client;
  final Outbox outbox;
  final DossierStore dossiers;
  final Directory dir;

  /// Où les photos prises attendent leur dépôt : elles survivent à un redémarrage.
  final Directory photos;

  final status = ValueNotifier(const SyncStatus());

  /// Incrémenté quand les dossiers locaux changent (rafraîchit la liste).
  final revision = ValueNotifier(0);

  Referentials referentials = Referentials();
  Timer? _timer;

  static Future<AgentServices> open(SupabaseClient client) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/fieldproof_agent');
    await dir.create(recursive: true);
    return AgentServices(
      client: client,
      outbox: Outbox(JsonFileStore(File('${dir.path}/outbox.json'))),
      dossiers: DossierStore(dir),
      dir: dir,
      photos: await Directory('${dir.path}/photos').create(recursive: true),
    );
  }

  String? get profileId => client.auth.currentUser?.id;

  JsonFileStore _refStore(String profileId) => JsonFileStore(File('${dir.path}/referentials_$profileId.json'));
  JsonFileStore _serverStore(String profileId) => JsonFileStore(File('${dir.path}/server_files_$profileId.json'));

  Future<void> loadCachedReferentials() async {
    final id = profileId;
    if (id == null) return;
    final raw = await _refStore(id).read();
    referentials = raw is Map ? Referentials.fromJson(Map<String, dynamic>.from(raw)) : Referentials();
  }

  /// Rattachements du compte (`core.my_memberships()`) ; lève une erreur réseau si hors ligne.
  Future<List<Map<String, dynamic>>> fetchMemberships() async {
    final rows = await client.schema('core').rpc('my_memberships');
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  }

  /// Relit les référentiels (régions, communes, configurations prêteurs) et les garde sur le téléphone.
  Future<void> refreshReferentials() async {
    final id = profileId;
    if (id == null) return;
    final core = client.schema('core');
    final memberships = await fetchMemberships();
    final regions = await core.from('geo_regions').select('id,name,code').order('name');
    final communes = await core.from('geo_communes').select('id,name,region_id').order('name').limit(5000);
    final orgs = await core.from('organizations').select('id,code,name,kind,is_sandbox');
    final configs = await client.schema('dossier').from('lender_configs').select('organization_id,version,config');
    referentials = Referentials(
      regions: List<Map<String, dynamic>>.from(regions),
      communes: List<Map<String, dynamic>>.from(communes),
      organizations: List<Map<String, dynamic>>.from(orgs),
      lenderConfigs: List<Map<String, dynamic>>.from(configs),
      memberships: memberships,
      fetchedAt: DateTime.now(),
    );
    await _refStore(id).write(referentials.toJson());
  }

  // ---------------------------------------------------------------------------
  // Dossiers locaux
  // ---------------------------------------------------------------------------

  Future<List<Dossier>> localDossiers() async {
    final id = profileId;
    if (id == null) return [];
    final list = await dossiers.all(id);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<Dossier?> dossier(String id) async => profileId == null ? null : dossiers.get(profileId!, id);

  Dossier newDossier() {
    final id = profileId;
    if (id == null) throw StateError('Session absente : reconnectez-vous.');
    final d = Dossier(
      id: newId(),
      clientId: newId(),
      farmId: newId(),
      profileId: id,
      createdAt: DateTime.now(),
      lenderOrganizationId: referentials.defaultLenderId,
    );
    d.client['nationality'] = 'Sénégalaise';
    return d;
  }

  /// Dernière liste serveur (`dossier.file_overview`) gardée sur le téléphone.
  Future<List<Map<String, dynamic>>> cachedServerFiles() async {
    final id = profileId;
    if (id == null) return [];
    final raw = await _serverStore(id).read();
    return raw is List ? [for (final r in raw) Map<String, dynamic>.from(r as Map)] : [];
  }

  /// Enregistre sur le téléphone puis met le brouillon complet en file (sans attendre le réseau).
  Future<void> saveDraft(Dossier d) async {
    if (!d.editable) throw StateError('Dossier verrouillé : ${statusLabel(d.status)}.');
    d.updatedAt = DateTime.now();
    final stored = await dossiers.get(d.profileId, d.id);
    if (stored != null) _mergeSyncFields(d, stored);
    await dossiers.put(d);
    await outbox.enqueue(
      OutboxEntry(
        id: newId(),
        rpc: rpcSaveDraft,
        payload: buildSaveDraftPayload(d),
        profileId: d.profileId,
        subjectId: d.id,
        label: 'Brouillon — ${d.displayName}',
        createdAt: DateTime.now().toUtc(),
      ),
      replaceTail: true,
    );
    await _queueDocuments(d);
    revision.value++;
    await refreshCounts();
  }

  /// Un écran ouvert pendant une synchronisation garde une copie ancienne : on reprend du
  /// disque ce que seule la synchronisation écrit (référence, pièces déposées…).
  void _mergeSyncFields(Dossier d, Dossier stored) {
    d.reference = stored.reference ?? d.reference;
    d.lastSyncedAt = stored.lastSyncedAt ?? d.lastSyncedAt;
    d.lenderOrganizationId ??= stored.lenderOrganizationId;
    d.serverMessage = stored.serverMessage;
    d.returnReason = stored.returnReason;
    for (final doc in d.documents) {
      final s = stored.documents.where((x) => x.id == doc.id).firstOrNull;
      if (s != null) {
        doc.uploaded = doc.uploaded || s.uploaded;
        doc.queued = doc.queued || s.queued;
      }
    }
    if (d.consent != null && stored.consent != null && stored.consent!.signatureDocumentId == d.consent!.signatureDocumentId) {
      d.consent!.queued = d.consent!.queued || stored.consent!.queued;
    }
  }

  /// Met en file les pièces pas encore envoyées (dépôt Storage puis `register_document`).
  Future<void> _queueDocuments(Dossier d) async {
    var changed = false;
    for (final doc in d.documents.where((x) => !x.queued)) {
      await outbox.enqueue(OutboxEntry(
        id: 'doc-${doc.id}',
        rpc: rpcRegisterDocument,
        payload: buildRegisterDocumentParams(d.id, doc),
        profileId: d.profileId,
        subjectId: d.id,
        label: '${documentLabel(doc.kind)} — ${d.displayName}',
        createdAt: DateTime.now().toUtc(),
        attachments: [OutboxAttachment(localPath: doc.localPath, storagePath: doc.storagePath(d.id), contentType: doc.mime)],
      ));
      doc.queued = true;
      changed = true;
    }
    final c = d.consent;
    if (c != null && !c.queued) {
      for (final params in buildConsentParams(d.id, c)) {
        await outbox.enqueue(OutboxEntry(
          id: 'consent-${c.signatureDocumentId}-${params['p_purpose']}',
          rpc: rpcRecordConsent,
          payload: params,
          profileId: d.profileId,
          subjectId: d.id,
          label: 'Consentement (${params['p_purpose']}) — ${d.displayName}',
          createdAt: DateTime.now().toUtc(),
        ));
      }
      c.queued = true;
      changed = true;
    }
    if (changed) await dossiers.put(d);
  }

  /// Soumission : commande horodatée au moment du geste, rejouée après le brouillon et les pièces.
  Future<void> submit(Dossier d, DateTime tappedAt) async {
    final expected = d.status;
    await saveDraft(d);
    d.submitPending = true;
    d.serverMessage = null;
    await dossiers.put(d);
    await outbox.enqueue(OutboxEntry(
      id: 'submit-${d.id}-${tappedAt.microsecondsSinceEpoch}',
      rpc: rpcSubmitFile,
      payload: buildSubmitParams(d.id, expected, tappedAt),
      profileId: d.profileId,
      subjectId: d.id,
      label: 'Soumission — ${d.displayName}',
      createdAt: DateTime.now().toUtc(),
    ));
    revision.value++;
    await refreshCounts();
  }

  /// Supprime un brouillon jamais envoyé (rien sur le serveur).
  Future<void> deleteLocalDraft(Dossier d) async {
    await outbox.discardSubject(d.id);
    await dossiers.update(d.profileId, (list) => list.removeWhere((x) => x.id == d.id));
    for (final doc in d.documents) {
      final f = File(doc.localPath);
      if (await f.exists()) await f.delete();
    }
    revision.value++;
    await refreshCounts();
  }

  Future<List<OutboxEntry>> pendingFor(String dossierId) async =>
      profileId == null ? [] : outbox.entries(profileId: profileId, subjectId: dossierId);

  Future<void> refreshCounts() async {
    final id = profileId;
    if (id == null) return;
    final e = await outbox.entries(profileId: id);
    status.value = status.value.copyWith(pending: e.where((x) => !x.rejected).length, rejected: e.where((x) => x.rejected).length);
  }

  // ---------------------------------------------------------------------------
  // Synchronisation
  // ---------------------------------------------------------------------------

  void startAutoSync() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => sync());
  }

  void stopAutoSync() => _timer?.cancel();

  /// Envoie la file, applique les retours du serveur aux dossiers, puis relit la liste serveur.
  Future<FlushReport?> sync({bool force = false}) async {
    final id = profileId;
    if (id == null || status.value.syncing) return null;
    status.value = status.value.copyWith(syncing: true);
    try {
      final report = await outbox.flush(id, dossierRpcs(client), upload: documentUploader(client), force: force);
      await _applyReport(id, report);
      if (report.transientError == null) {
        try {
          if (force || referentials.isEmpty) await refreshReferentials();
          await refreshServer();
          status.value = status.value.copyWith(lastSyncAt: DateTime.now(), clearError: true);
        } catch (e) {
          status.value = status.value.copyWith(lastError: errorMessage(e));
        }
      } else {
        status.value = status.value.copyWith(lastError: report.transientError);
      }
      return report;
    } finally {
      status.value = status.value.copyWith(syncing: false);
      await refreshCounts();
      revision.value++;
    }
  }

  Future<void> _applyReport(String profileId, FlushReport report) async {
    if (report.sentEntries.isEmpty && report.rejectedEntries.isEmpty) return;
    final submitRejected = <String>[];
    await dossiers.update(profileId, (list) {
      Dossier? find(String id) => list.where((d) => d.id == id).firstOrNull;
      for (final e in report.sentEntries) {
        final d = find(e.subjectId);
        if (d == null) continue;
        d.lastSyncedAt = DateTime.now();
        switch (e.rpc) {
          case rpcRegisterDocument:
            for (final doc in d.documents.where((x) => x.id == e.payload['p_document'])) {
              doc.uploaded = true;
            }
          case rpcSubmitFile:
            d.status = statusSubmitted;
            d.submitPending = false;
            d.returnReason = null;
            d.serverMessage = null;
          case rpcSaveDraft:
            if (d.serverMessage != null && d.serverMessage!.startsWith('Envoi refusé')) d.serverMessage = null;
        }
      }
      for (final e in report.rejectedEntries) {
        final d = find(e.subjectId);
        if (d == null) continue;
        if (e.rpc == rpcSubmitFile) {
          // Refus de la soumission : le dossier se déverrouille, le motif du serveur s'affiche.
          d.submitPending = false;
          d.serverMessage = 'Soumission refusée : ${e.lastError}';
          submitRejected.add(e.id);
        } else {
          d.serverMessage = 'Envoi refusé (${e.label.split(' — ').first}) : ${e.lastError}';
        }
      }
    });
    for (final id in submitRejected) {
      await outbox.discard(id);
    }
  }

  /// Relit `dossier.file_overview` (les dossiers de l'agent) et aligne les dossiers locaux
  /// sans commande en attente sur le statut du serveur (renvoi, envoi…).
  Future<List<Map<String, dynamic>>> refreshServer() async {
    final id = profileId;
    if (id == null) return [];
    final rows = List<Map<String, dynamic>>.from(await client
        .schema('dossier')
        .from('file_overview')
        .select('id,reference,status,client_name,client_phone,region_name,commune_name,locality,lender_name,return_reason,'
            'submitted_at,sent_at,created_at,updated_at,parcel_count,total_gps_area_ha,lender_organization_id,packages')
        .order('updated_at', ascending: false));
    await _serverStore(id).write(rows);
    final pending = await outbox.entries(profileId: id);
    await dossiers.update(id, (list) {
      for (final d in list) {
        final row = rows.where((r) => r['id'] == d.id).firstOrNull;
        if (row == null) continue;
        d.reference = row['reference'] as String? ?? d.reference;
        d.lenderOrganizationId ??= row['lender_organization_id'] as String?;
        if (pending.any((e) => e.subjectId == d.id)) continue;
        final serverStatus = row['status'] as String;
        d.status = serverStatus;
        d.submitPending = false;
        d.returnReason = row['return_reason'] as String?;
      }
    });
    revision.value++;
    return rows;
  }

  /// Complétude calculée par le serveur (`dossier.completeness`), si le dossier y est déjà.
  Future<Map<String, dynamic>> serverCompleteness(String fileId) async {
    final r = await client.schema('dossier').rpc('completeness', params: {'p_file': fileId});
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> signOut() async {
    stopAutoSync();
    await client.auth.signOut();
  }
}
