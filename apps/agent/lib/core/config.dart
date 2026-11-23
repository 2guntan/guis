/// Configuration de compilation : `flutter run --dart-define-from-file=env.json`
/// (modèle : `env.json.example`) ou `--dart-define=API_URL=https://…`.
/// Seule l'adresse du serveur entre dans l'application : aucun secret.
class AppConfig {
  static const apiUrl = String.fromEnvironment('API_URL');

  static List<String> get missing => [if (apiUrl.isEmpty) 'API_URL'];
}
