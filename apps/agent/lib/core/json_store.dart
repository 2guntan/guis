import 'dart:convert';
import 'dart:io';

/// Un document JSON sur le disque de l'appareil, écrit de façon atomique
/// (fichier temporaire puis renommage) : une coupure pendant l'écriture laisse
/// l'ancienne version intacte, jamais un fichier tronqué.
class JsonFileStore {
  JsonFileStore(this.file);

  final File file;

  Future<Object?> read() async {
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<void> write(Object? value) => writeText(jsonEncode(value));

  /// Écrit un texte JSON déjà encodé (même écriture atomique).
  Future<void> writeText(String json) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(file.path);
  }
}
