import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../model/payloads.dart';
import 'outbox.dart';

/// Bucket privé des pièces (db/migrations/0006_storage.sql) : `files/<file_id>/<document_id>.jpg`.
const documentsBucket = 'documents';

/// Les seules RPC que l'outbox sait envoyer — toutes rejouables sans effet de bord :
/// - `save_draft` remplace chaque section par l'état du téléphone ;
/// - `register_document` rend l'identifiant déjà enregistré ;
/// - `record_consent` n'a pas de clef d'idempotence côté base : on vérifie d'abord qu'un
///   recueil de même finalité et même horodatage n'est pas déjà enregistré ;
/// - `submit_file` rejoué après une réponse perdue est refusé « entre-temps » : si le
///   dossier est bien « soumis » sur le serveur, c'est un succès.
RpcDispatcher dossierRpcs(SupabaseClient client) => (rpc, payload) async {
      final db = client.schema('dossier');
      switch (rpc) {
        case rpcSaveDraft:
          return db.rpc('save_draft', params: {'p': payload});
        case rpcRegisterDocument:
          return db.rpc('register_document', params: payload);
        case rpcRecordConsent:
          final existing = await db
              .from('consents')
              .select('id')
              .eq('file_id', payload['p_file'] as String)
              .eq('purpose', payload['p_purpose'] as String)
              .eq('collected_at', payload['p_collected_at'] as String)
              .isFilter('withdrawn_at', null)
              .limit(1);
          if ((existing as List).isNotEmpty) return existing.first['id'];
          return db.rpc('record_consent', params: payload);
        case rpcSubmitFile:
          try {
            return await db.rpc('submit_file', params: payload);
          } on PostgrestException catch (e) {
            if (e.message.contains('entre-temps')) {
              final row = await db.from('client_files').select('status').eq('id', payload['p_file'] as String).maybeSingle();
              if (row != null && row['status'] == 'submitted') return {'status': 'submitted', 'replayed': true};
            }
            rethrow;
          }
        default:
          throw ArgumentError.value(rpc, 'rpc', 'RPC inconnue de l\'outbox');
      }
    };

/// Dépose une pièce à son chemin déterministe, sans jamais écraser : un chemin déjà
/// déposé (reprise après coupure) répond « already exists » et vaut succès.
Uploader documentUploader(SupabaseClient client) => (a) async {
      final file = File(a.localPath);
      if (!await file.exists()) {
        throw const StorageException('Photo introuvable sur le téléphone : reprenez-la', statusCode: '404');
      }
      try {
        await client.storage
            .from(documentsBucket)
            .upload(a.storagePath, file, fileOptions: FileOptions(contentType: a.contentType, upsert: false));
      } on StorageException catch (e) {
        final m = e.message.toLowerCase();
        if (e.statusCode == '409' || m.contains('already exists') || m.contains('duplicate')) return;
        rethrow;
      }
    };
