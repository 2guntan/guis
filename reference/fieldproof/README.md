# reference/fieldproof : copie de référence, en lecture seule

Ce dossier contient un extrait de **Fieldproof** pris au commit `57ba3a7` le 23/11/2026, en gardant les chemins d'origine. Fieldproof est la plateforme de dossiers de crédit et de preuve satellite d'IBRIZ.

**Règles d'usage**

- On ne modifie **jamais** ce dossier. Pour réutiliser un fichier, on le **copie** au bon endroit dans Guis (`apps/`, `workers/`, `db/`), on l'adapte là-bas, puis on ajoute une ligne dans `/PROVENANCE.md`.
- Guis ne dépend pas de ce dossier, et rien ne doit l'importer ni le compiler. Une fois la V1 livrée, on pourra le supprimer.
- Fieldproof reprend lui-même une partie du code d'Agriva (son app terrain notamment). Cette origine est tracée dans le `PROVENANCE.md` de Fieldproof.
- Les identifiants de projet qui apparaissent ici (Supabase `rxoddvvdjxmbvjekjedq`, Netlify `fieldproof-sn`, Railway `fieldproof-workers`) sont **ceux de Fieldproof**. Guis ne les utilise **jamais** : il tourne sur son propre VPS (voir `NOTE-CADRAGE.md` §5).

## Contenu

| Chemin | Usage dans Guis |
|---|---|
| `apps/agent/lib/features/editor/parcel_walk_page.dart` | Tour du champ au GPS : relevé manuel ou automatique tous les 5 m, refus des points dont la précision dépasse 30 m. **À copier.** |
| `apps/agent/lib/core/model/geo.dart` (+ `test/geo_test.dart`) | Surface, validité du contour, GeoJSON. **À copier.** |
| `apps/agent/lib/core/sync/outbox.dart` (+ `test/outbox_test.dart`) | File d'envoi hors ligne avec reprise. **À copier et simplifier** : Guis n'a pas de statut de dossier. |
| `apps/agent/lib/core/photos.dart`, `json_store.dart`, `config.dart` | Photos géolocalisées, stockage local, configuration par `--dart-define`. **À copier.** |
| `apps/agent/lib/features/auth/sign_in_page.dart`, `lib/ui/theme.dart`, `lib/main.dart` | Connexion, thème, démarrage de l'app. **À copier et renommer.** |
| `apps/agent/lib/core/services.dart`, `sync/dossier_rpcs.dart`, `features/editor/editor_page.dart`, `fields.dart`, `features/dossiers/dossiers_page.dart` | Exemples de structure (étapes, champs de saisie, liste). **Pour s'inspirer seulement** : leur logique dossier et prêteur ne s'applique pas. |
| `apps/agent/android/`, `pubspec.yaml`, `analysis_options.yaml` | Projet Android Flutter. **À copier en changeant** le paquet `com.fieldproof.agent` en `com.guis.app` et le libellé de l'app. |
| `apps/web/components/map/*`, `components/ui/*`, `AppHeader.tsx`, `StatusBadge.tsx`, `superviseur/NdviChart.tsx`, `FilterBar.tsx`, `NavLink.tsx`, `Gallery.tsx` | Carte des parcelles, courbe NDVI, filtres, galerie photo, boutons et fenêtres. **À copier.** |
| `apps/web/lib/supabase/*`, `session.ts`, `middleware.ts`, `app/login`, `app/deconnexion`, `app/layout.tsx`, `globals.css`, configurations | Connexion Supabase côté serveur, protection des pages, base Next.js et Tailwind. **À copier.** |
| `apps/web/app/superviseur/*` | Exemple de tableau de bord (accueil, liste, fiche). **Pour s'inspirer seulement.** |
| `workers/sat/sat/retro.py` | Accès Planetary Computer (STAC + COG), `scene_ndvi`, `select_items`, masque nuages, `square`. **Copier les fonctions de lecture d'images.** La logique hivernage / contre-saison et `verdict_of` ne s'appliquent **pas** : la pomme de terre se cultive en contre-saison irriguée. |
| `workers/sat/sat/main.py`, `Dockerfile`, `requirements.txt` | Boucle du worker (`claim_jobs` → traitement → `complete_job`), conteneur. **À copier.** |
| `db/migrations/0003_core_jobs.sql` | Table de travaux, `claim_jobs`, nouvelles tentatives. **À copier et simplifier.** |
| `db/migrations/0000_core.sql`, `0005_watch.sql`, `0006_storage.sql`, `0008`, `0009` | Modèles d'événements, d'analyse satellite, de stockage et de durcissement (RLS, droits). **Pour s'inspirer seulement.** Guis a un schéma neuf et court. |
| `docs/adr/0005`, `0007`, `0009`, `0010` | Les décisions de Fieldproof sur les workers, la synchronisation hors ligne, l'hébergement et le radar. **À lire pour le contexte.** |
