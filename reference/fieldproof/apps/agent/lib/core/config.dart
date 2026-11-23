/// Configuration de compilation : `flutter run --dart-define-from-file=env.json`
/// (modèle : `env.json.example`). Seules l'URL du projet et la clé `anon` publique
/// entrent dans l'application ; jamais la clé `service_role`.
class AgentConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static List<String> get missing => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      ];
}
