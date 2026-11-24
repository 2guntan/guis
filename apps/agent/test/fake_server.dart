import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Faux serveur Guis en mémoire, au niveau HTTP : il reçoit exactement les requêtes que l'app
/// enverrait au vrai serveur (voir apps/web/README.md, « Contrat de l'API de l'app »).
class FakeServer {
  bool offline = false;

  /// Refuse (422) l'enregistrement des producteurs dont le nom est dans cet ensemble.
  final Set<String> rejectLastNames = {};

  final List<String> log = [];
  final Map<String, Map<String, dynamic>> producers = {};
  final Map<String, Map<String, dynamic>> seeds = {};
  final Map<String, Map<String, dynamic>> fields = {};
  final Map<String, List<int>> photos = {};
  List<String> villages = ['Village A'];

  static const token = 'jeton-de-test';
  static const user = {'id': 'u-1', 'name': 'Agent Test', 'phone': '221770000001', 'role': 'agent'};

  http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  late final client = MockClient((req) async {
    if (offline) throw const SocketException('Failed host lookup');
    final path = req.url.path;
    log.add('${req.method} $path');
    if (path == '/api/auth/login') {
      final b = jsonDecode(req.body) as Map;
      if (b['password'] != 'motdepasse') return _json({'error': 'Numéro ou mot de passe incorrect.'}, 401);
      return _json({'token': token, 'user': user});
    }
    if (req.headers['Authorization'] != 'Bearer $token') return _json({'error': 'Session expirée : reconnectez-vous.'}, 401);
    if (path == '/api/auth/logout') return _json({'ok': true});
    if (path == '/api/app/bootstrap') {
      return _json({
        'user': user,
        'lists': {
          'villages': villages,
          'varieties': ['Spunta'],
          'irrigation': ['Goutte-à-goutte'],
          'water_sources': ['Puits'],
        },
        'producers': [for (final p in producers.values) p],
        'seeds': [for (final s in seeds.values) s],
        'fields': [for (final f in fields.values) f],
      });
    }
    final m = RegExp(r'^/api/app/producers/([^/]+)$').firstMatch(path);
    if (m != null && req.method == 'PUT') {
      final id = m.group(1)!;
      final b = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      if (rejectLastNames.contains(b['last_name'])) return _json({'error': 'Donnée refusée.'}, 422);
      producers[id] = {
        'id': id,
        for (final k in ['last_name', 'first_name', 'phone', 'member_card', 'sex', 'village', 'photo_id', 'consent_at']) k: b[k],
        'source': 'app',
      };
      for (final s in (b['seeds'] as List)) {
        final sm = Map<String, dynamic>.from(s as Map);
        seeds[sm['id'] as String] = {...sm, 'producer_id': id};
      }
      for (final d in (b['deleted_seed_ids'] as List)) {
        seeds.remove(d);
      }
      return _json({'ok': true});
    }
    final f = RegExp(r'^/api/app/fields/([^/]+)$').firstMatch(path);
    if (f != null && req.method == 'PUT') {
      final b = Map<String, dynamic>.from(jsonDecode(req.body) as Map);
      if (!producers.containsKey(b['producer_id'])) return _json({'error': 'Le producteur de ce champ est inconnu du serveur.'}, 409);
      fields[f.group(1)!] = {'id': f.group(1), ...b};
      return _json({'ok': true});
    }
    final ph = RegExp(r'^/api/photos/([^/]+)$').firstMatch(path);
    if (ph != null && req.method == 'PUT') {
      photos[ph.group(1)!] = req.bodyBytes;
      return _json({'ok': true});
    }
    return _json({'error': 'Introuvable'}, 404);
  });
}
