# Prompt de démarrage : session cloud Guis

Copier tout le bloc ci-dessous dans une nouvelle session ouverte sur le dépôt `2guntan/guis`.

---

```text
Tu travailles sur Guis (dépôt 2guntan/guis, PUBLIC). Guis est une application générique de collecte et de suivi
satellite des champs. Premier usage : une coopérative partenaire distribue en ce moment des semences de pomme de terre
à ses producteurs, et il faut relever sur le terrain les champs réellement emblavés, puis les suivre par satellite.

Lis d'abord, dans cet ordre :
1. NOTE-CADRAGE.md : objectif, périmètre V1, données, suivi satellite, architecture, plan J1 à J5, points à trancher (§7).
2. reference/fieldproof/README.md : ce qu'on reprend de Fieldproof, fichier par fichier.
3. PROVENANCE.md.

RÈGLES (non négociables)
- reference/fieldproof/ est en LECTURE SEULE. Tu y copies du code, tu n'y écris jamais. Chaque copie vers apps/,
  workers/ ou db/ ajoute une ligne à PROVENANCE.md : chemin source, commit 57ba3a7, date, modifications.
- Guis est séparé de Fieldproof. Tu n'utilises jamais les identifiants de Fieldproof (Supabase rxoddvvdjxmbvjekjedq,
  Netlify fieldproof-sn, Railway fieldproof-workers) et tu ne réutilises ni le vocabulaire prêteur / paquet / envoi /
  dossier client, ni la logique hivernage / contre-saison / verdict de l'analyse rétroactive.
- Dépôt public : aucun secret, aucune donnée réelle de producteur (nom, téléphone, carte de membre) dans git,
  pas même en fixture. Les clés passent par les variables d'environnement de la session, de GitHub Actions,
  de Netlify et de Railway. Ajoute un .gitignore dès le premier commit (.env*, env.json, *.jks, key.properties).
- Vocabulaire : celui de CONTEXT.md (que tu crées à l'étape 1). Si un terme manque, tu me poses la question.
- Les textes, libellés, commentaires et documents sont en français. Les noms de code sont en anglais.
- Des commits petits et fréquents.

ÉTAPE 1 : GRILLING (avant tout code)
Utilise le skill de grilling (mattpocock-skills:grilling ou grill-with-docs) pour m'interroger, une question à la fois,
en commençant par les 7 points ouverts du §7 de la note (zone, volume, taille des champs, accès au tableau de bord,
plusieurs champs par producteur, consentement, fichier de distribution). Continue ensuite sur ce que le grilling révèle
d'autre. À chaque question, propose une valeur par défaut. À la fin, écris :
- CONTEXT.md : glossaire de Guis (producteur, coopérative, agent, champ, contour, surface déclarée / mesurée, semis,
  distribution de semences, campagne, suivi, statut du champ, alerte…), avec les termes à éviter ;
- docs/adr/0001…: une ADR par décision structurante (séparation d'avec Fieldproof, synchronisation hors ligne simplifiée,
  suivi depuis le semis plutôt que l'analyse rétroactive, champs de petite taille et limite de 0,1 ha, APK hors Play Store) ;
- une mise à jour de NOTE-CADRAGE.md (§7 tranché).
Arrête-toi et attends mon accord avant l'étape 2.

ÉTAPE 2 : PRÉPARATION DU DÉPÔT
Structure : apps/agent (Flutter Android), apps/web (Next.js 15 + Tailwind + Supabase SSR), workers/sat (Python 3.12),
db/migrations, db/tests, docs/adr, .github/workflows.
- Copie depuis reference/fieldproof en gardant ce qui fonctionne. On copie, puis on supprime ce qui ne sert pas :
  on ne réécrit pas à partir de zéro.
  * agent : pubspec.yaml, analysis_options.yaml, android/ (paquet com.fieldproof.agent → com.guis.app, libellé « Guis »),
    lib/main.dart, lib/core/{config,json_store,photos}.dart, lib/core/model/geo.dart, lib/core/sync/outbox.dart,
    lib/features/auth/sign_in_page.dart, lib/features/editor/parcel_walk_page.dart, lib/features/editor/fields.dart,
    lib/ui/theme.dart, test/geo_test.dart, test/outbox_test.dart.
  * web : package.json, configurations (tsconfig, next, tailwind, postcss, eslint, netlify.toml), middleware.ts,
    app/{layout.tsx,globals.css,login,deconnexion}, lib/supabase/*, lib/{session,geo,map,format,utils,errors}.ts,
    components/{ui/*,map/*,AppHeader.tsx,StatusBadge.tsx}, components/superviseur/{NdviChart,FilterBar,NavLink,Gallery}.tsx
    (à ranger dans components/dashboard/).
  * sat : Dockerfile, requirements.txt (sans les dépendances du radar si elles deviennent inutiles), sat/main.py,
    et de sat/retro.py UNIQUEMENT les fonctions de lecture d'images (recherche STAC, select_items, scene_ndvi,
    masque nuages, accès Planetary Computer).
  * db : la table de travaux et claim_jobs de 0003_core_jobs.sql, simplifiées. Le reste n'est qu'un modèle.
- Retire tout ce qui concerne le prêteur, le paquet, l'envoi, la complétude, le consentement signé, les pièces
  et les statuts de dossier.
- CI GitHub Actions : flutter analyze + flutter test + construction de l'APK de release (artefact téléchargeable),
  next build + lint, tests Python, tests SQL sur un Postgres de service. L'APK se construit dans la CI : pas besoin
  du SDK Android dans la session.
- README.md à la racine : lancer, tester, déployer chaque surface.

ÉTAPE 3 : J1 de la note
Schéma Supabase neuf et court (producers, seed_distributions, fields avec geometry et surfaces déclarée / mesurée,
sowing_date, photos, jobs, ndvi_points, field_status), RLS par coopérative et rôles agent / coopérative,
RPC d'écriture idempotentes (upsert par uuid créé sur le téléphone), tests SQL. App réduite à 3 écrans :
Producteur → Champ (tour GPS) → Semis, hors ligne, synchronisée.
Point de contrôle : un champ saisi sur le téléphone apparaît dans la base.

Ce que je fais de mon côté, et que tu me demandes quand tu en as besoin :
- créer le projet Supabase Guis et te donner SUPABASE_URL et les clés en variables de session ;
- créer le site Netlify et le service Railway ;
- la clé de signature de l'APK (en secret GitHub) ;
- les premiers comptes agents.
Tu ne pousses que sur des branches. Je relis et je fusionne.
```
