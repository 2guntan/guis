import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Réponse d'erreur du serveur Guis : `{"error": "message en français"}` et un code HTTP.
class ApiException implements Exception {
  const ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Client de l'API REST du serveur Guis (remplace la couche Supabase de Fieldproof).
class Api {
  Api(String baseUrl, {http.Client? client, this.token}) : base = baseUrl.replaceAll(RegExp(r'/+$'), ''), _http = client ?? http.Client();

  final String base;
  final http.Client _http;
  String? token;

  static const timeout = Duration(seconds: 45);

  Map<String, String> _headers([Map<String, String>? extra]) => {if (token != null) 'Authorization': 'Bearer $token', ...?extra};

  Future<Object?> _decode(http.Response r) async {
    final text = utf8.decode(r.bodyBytes);
    Object? data;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      data = null;
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return data;
    final msg = data is Map && data['error'] is String ? data['error'] as String : 'Erreur du serveur (${r.statusCode})';
    throw ApiException(r.statusCode, msg);
  }

  Future<Object?> get(String path) async => _decode(await _http.get(Uri.parse('$base$path'), headers: _headers()).timeout(timeout));

  Future<Object?> sendJson(String method, String path, Object? body) async {
    final req = http.Request(method, Uri.parse('$base$path'))
      ..headers.addAll(_headers({'Content-Type': 'application/json'}))
      ..body = jsonEncode(body);
    return _decode(await http.Response.fromStream(await _http.send(req).timeout(timeout)));
  }

  Future<Object?> putBytes(String path, List<int> bytes, {required String contentType, Map<String, String>? headers}) async {
    final req = http.Request('PUT', Uri.parse('$base$path'))
      ..headers.addAll(_headers({'Content-Type': contentType, ...?headers}))
      ..bodyBytes = bytes;
    return _decode(await http.Response.fromStream(await _http.send(req).timeout(const Duration(minutes: 3))));
  }

  /// Connexion : `{token, user}`.
  Future<Map<String, dynamic>> login(String phone, String password) async {
    final r = await sendJson('POST', '/api/auth/login', {'phone': phone, 'password': password});
    return Map<String, dynamic>.from(r as Map);
  }
}

/// Refus définitif du serveur (donnée invalide, conflit, droit) : rejouer ne changera rien.
/// Tout le reste — réseau, session expirée (401), délai (408), surcharge (429), panne (5xx) — se réessaie.
bool isDefinitiveRefusal(Object error) {
  if (error is! ApiException) return false;
  final s = error.status;
  return s >= 400 && s < 500 && s != 401 && s != 408 && s != 429;
}

/// Le serveur est injoignable ou la session n'est plus valable : inutile d'essayer les commandes
/// suivantes, l'envoi s'arrête. Les autres erreurs transitoires (500, erreur inattendue) ne bloquent
/// que le producteur concerné.
bool isConnectivityError(Object error) => switch (error) {
  SocketException _ || http.ClientException _ || TimeoutException _ || HandshakeException _ => true,
  ApiException e => const {401, 408, 429, 502, 503, 504}.contains(e.status),
  _ => false,
};

/// Message lisible par l'agent, toujours en français (jamais le texte brut d'une exception).
String errorMessage(Object error) => switch (error) {
  ApiException e => e.message,
  SocketException _ => 'Pas de réseau',
  http.ClientException _ => 'Pas de réseau',
  TimeoutException _ => 'Délai dépassé',
  HandshakeException _ => 'Connexion sécurisée impossible',
  FileSystemException _ => 'Fichier introuvable sur le téléphone',
  _ => 'Erreur inattendue, nouvel essai plus tard',
};
