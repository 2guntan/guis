# Fieldproof Agent (`apps/agent`)

Application Flutter Android des **agents terrain** : collecte hors ligne du **dossier client**
(client, adresse, exploitation, parcelles tracées au GPS, besoin, champs complémentaires du
prêteur, pièces, consentement), **complétude**, puis **soumission** au superviseur.
Adaptée de l'application terrain d'Agriva (`apps/field`) — voir `docs/provenance-pending/agent.md`.

- Paquet Dart : `fieldproof_agent` · Android : `com.fieldproof.agent` · libellé « Fieldproof Agent ».
- Backend : le projet Supabase Fieldproof (schémas `core`, `identity`, `dossier`, bucket `documents`).

## Configuration

L'application ne contient que l'URL du projet et la clé **anon** publique, passées à la compilation :

```bash
cp env.json.example env.json      # puis renseigner SUPABASE_URL et SUPABASE_ANON_KEY
```

`env.json` est ignoré par git. Pour le régénérer depuis `.env.local` (racine du dépôt) sans afficher les valeurs :

```bash
set -a; source ../../.env.local; set +a
python3 -c 'import json,os;json.dump({k:os.environ[k] for k in ("SUPABASE_URL","SUPABASE_ANON_KEY")},open("env.json","w"),indent=2)'
```

**Jamais** la clé `service_role` dans l'application.

## Développer, tester

```bash
flutter pub get
flutter analyze
flutter test                         # outbox, surface des parcelles, payloads, écrans 360 × 640
flutter run --dart-define-from-file=env.json
```

Essai réel contre Supabase avec le code de synchronisation de l'application (sans émulateur) —
crée un dossier complet **dans le bac à sable** et le soumet :

```bash
FP_TEST_EMAIL=agent2.demo@fieldproof.test FP_TEST_PASSWORD=… flutter test test/connected_test.dart
```

## Construire l'APK

```bash
flutter build apk --release --dart-define-from-file=env.json
cp build/app/outputs/flutter-apk/app-release.apk ../../dist/fieldproof-agent.apk
```

### Signature

La clé de signature vit **hors du dépôt** : `~/.fieldproof-agent-keystore/` (`fieldproof-agent.jks`
et `signing.properties` : `storeFile`, `storePassword`, `keyAlias`, `keyPassword`). Un autre
emplacement peut être donné par la variable `FIELDPROOF_AGENT_SIGNING` (chemin du `.properties`).
Sans ce fichier, la version release est signée avec la clé de **debug** (développement, CI).

La clé actuelle a été générée localement le 20/11/2026 (RSA 4096, alias `fieldproof-agent`,
validité 10 000 jours). **Sauvegardez ce dossier** : sans la même clé, une mise à jour ne
s'installe pas par-dessus l'application existante (il faut la désinstaller, ce qui efface les
brouillons non synchronisés). Pour la diffusion par le Play Store, prévoir la signature d'application Google Play.

## Installer l'APK sur un téléphone

1. Copier `dist/fieldproof-agent.apk` sur le téléphone (câble, WhatsApp, Drive…), ou `adb install -r dist/fieldproof-agent.apk`.
2. Sur le téléphone, ouvrir le fichier et autoriser « Installer des applications inconnues » pour l'application qui l'ouvre.
3. Première ouverture **avec du réseau** : connexion (compte agent terrain), vérification du rôle,
   chargement des régions, communes et de la configuration du prêteur. Ensuite, tout fonctionne hors ligne.
4. Autoriser la localisation (« Pendant l'utilisation de l'application ») et l'appareil photo.

## Modèle hors ligne (ADR-0007)

- **Le téléphone écrit, seul, tant que le dossier est Brouillon ou Renvoyé.** Chaque changement
  d'étape enregistre le dossier dans un fichier JSON de l'appareil (écriture atomique), puis met
  en **file d'envoi** (outbox, `outbox.json`) un `dossier.save_draft` complet et rejouable ; les
  UUID (dossier, client, exploitation, parcelles, pièces) sont générés par le téléphone.
- **Pièces** : photo compressée (1600 px, JPEG 75 %), datée et géolocalisée, gardée dans le
  dossier de l'application ; l'outbox la dépose dans Storage (`documents/files/<dossier>/<pièce>.jpg`,
  `upsert: false`, « already exists » = succès) **puis** appelle `dossier.register_document`
  (idempotent par identifiant). Une nouvelle photo = une nouvelle version, jamais un écrasement.
- **Consentement** (ADR-0008) : 3 finalités cochées séparément (1 et 2 obligatoires), signature à
  l'écran ou trait / empreinte, photo du client, GPS, heure, langue (fr / wo), version du texte
  (`config.consent_notice_version`). La signature et la photo partent comme pièces, puis un
  `dossier.record_consent` par finalité accordée (rejeu vérifié côté téléphone : même finalité, même heure).
- **Soumission** : commande horodatée `dossier.submit_file(dossier, statut attendu, heure du geste)`,
  mise en file **après** le brouillon et les pièces. Le dossier est verrouillé sur le téléphone dès
  le geste. Si le serveur refuse (statut changé entre-temps, dossier incomplet), le message du
  serveur s'affiche sur le dossier et il se déverrouille. Une soumission rejouée après une réponse
  perdue (« passé soumis entre-temps ») vaut succès si le serveur dit « soumis ».
- **Ordre et reprises** : la file est **ordonnée par dossier** ; un refus du serveur bloque la
  suite du même dossier (jamais une soumission après un brouillon refusé), pas les autres dossiers ;
  l'agent peut « Réessayer » ou « Écarter ». Une erreur réseau ou de session arrête l'envoi et
  attend un délai croissant (10 s, 20 s, 40 s… 15 min max) ; le bouton « Synchroniser » l'ignore.
  La file survit aux redémarrages. Synchronisation automatique toutes les 45 s, au retour dans
  l'application et après chaque enregistrement.
- **Retour du serveur** : `dossier.file_overview` donne la liste serveur (référence, statut, motif
  de renvoi). Un dossier local sans commande en attente s'aligne sur le statut du serveur :
  Renvoyé → de nouveau modifiable, motif affiché en tête.
- **Référentiels gardés hors ligne** : rattachements (`core.my_memberships()`), régions, communes,
  organisations, configurations des prêteurs (champs complémentaires, pièces obligatoires).

## Parcelles

Tour au GPS (`geolocator`) : sommet ajouté à la main ou automatiquement tous les 5 m ; un point
dont la précision dépasse 30 m est refusé ; 3 sommets minimum ; contour qui se croise, moins de
100 m² ou plus de 500 ha refusés (mêmes règles que la base). Carte `flutter_map` sur les tuiles
OpenStreetMap quand il y a du réseau (sinon le tracé s'affiche sur fond uni). Surface calculée sur
l'ellipsoïde WGS84 (écart < 0,2 % avec `ST_Area(geography)`, vérifié par l'essai connecté).

## Arborescence

```
lib/main.dart                       démarrage, connexion, contrôle du rôle field_agent
lib/core/sync/outbox.dart           file d'envoi persistée, ordre par dossier, délais
lib/core/sync/dossier_rpcs.dart     RPC dossier.* et dépôt Storage
lib/core/services.dart              dossiers locaux, référentiels, synchronisation
lib/core/model/                     dossier, géométrie (surface), payloads, complétude locale
lib/features/dossiers/              « Mes dossiers » et état de synchronisation
lib/features/editor/                étapes du dossier, tracé GPS, récapitulatif et soumission
lib/features/consent/               consentement, zone de signature
```
