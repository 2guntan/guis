# apps/agent : app Android Guis (Flutter)

Collecte hors ligne des producteurs, de leurs semences et de leurs champs, par les agents de la coopérative.

## Lancer

```bash
cp env.json.example env.json   # adresse du serveur, jamais de secret
flutter run --dart-define-from-file=env.json
```

En local avec le serveur de développement sur la même machine qu'un émulateur Android : `API_URL=http://10.0.2.2:3000`.

## Tests

```bash
flutter analyze
flutter test
```

- `test/outbox_test.dart` : file d'envoi (ordre par producteur, reprise, refus) ;
- `test/services_test.dart` : saisie hors ligne et synchronisation contre un faux serveur HTTP (`test/fake_server.dart`, même contrat que `apps/web`) ;
- `test/screens_test.dart` : parcours et absence de débordement sur un téléphone 360 × 640.

## APK

La CI (`.github/workflows/apk.yml`) construit l'APK à chaque push qui touche `apps/agent/` et la publie en artefact (onglet Actions → l'exécution → `guis-apk-N`). L'adresse du serveur vient de la variable de dépôt `GUIS_API_URL`.

Signature : hors du dépôt, par `GUIS_SIGNING` (chemin d'un `signing.properties` : `storeFile`, `storePassword`, `keyAlias`, `keyPassword`) ou `~/.guis-keystore/signing.properties`. Sans clé, l'APK est signée avec la clé de debug.
