import 'dart:io';

/// Journal des erreurs inattendues, gardé sur le téléphone (aucun service externe : rien ne quitte
/// l'appareil). Lisible dans le menu « Journal des erreurs ». Plafonné : au-delà de [maxBytes], la
/// moitié la plus ancienne est effacée.
class ErrorLog {
  ErrorLog(this.file);

  final File file;

  static const maxBytes = 256 * 1024;

  Future<void> write(Object error, [StackTrace? stack]) async {
    try {
      await file.parent.create(recursive: true);
      if (await file.exists() && await file.length() > maxBytes) {
        final text = await file.readAsString();
        await file.writeAsString(text.substring(text.length ~/ 2), flush: true);
      }
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} ${error.runtimeType}: $error\n${stack ?? ''}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      /* le journal ne doit jamais faire tomber l'app */
    }
  }

  /// Les dernières lignes du journal (les plus récentes à la fin), vide s'il n'y a rien.
  Future<String> tail({int maxChars = 6000}) async {
    try {
      if (!await file.exists()) return '';
      final text = await file.readAsString();
      return text.length <= maxChars ? text : text.substring(text.length - maxChars);
    } catch (_) {
      return '';
    }
  }
}
