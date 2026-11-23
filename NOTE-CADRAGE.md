# Guis — note de cadrage

Version 0.2 du 23/11/2026.

**Guis** (du wolof *gis*, « voir ») : application générique de collecte et de suivi satellite des champs. Premier usage : la campagne de pomme de terre d'une coopérative partenaire.

## 1. Objectif

Une coopérative partenaire distribue en ce moment des semences de pomme de terre à ses producteurs. Il faut :

1. **Identifier sur le terrain les champs réellement emblavés.** Pour chaque producteur, on relève qui il est, où se trouve son champ (contour GPS), sa surface et sa date de semis.
2. **Suivre ces champs par satellite** pendant la campagne, et le montrer sur un tableau de bord web.

C'est un projet **séparé de Fieldproof** : il n'y a ni prêteur, ni paquet, ni envoi, ni lien sécurisé, ni formulaire à remplir. On collecte, on cartographie, on suit. Fieldproof n'est pas modifié. On y **copie** du code, en traçant chaque copie dans un `PROVENANCE.md`, comme Fieldproof le fait déjà avec Agriva.

## 2. Périmètre minimal (V1)

| Surface | Ce qu'elle fait |
|---|---|
| **App Android** (agent de la coopérative) | Fonctionne hors ligne. Saisie du producteur, du champ (tour GPS du contour), du semis, d'une photo. Synchronisation dès qu'il y a du réseau. |
| **Tableau de bord web** (coopérative et IBRIZ) | Carte de tous les champs, liste filtrable, fiche d'un champ avec sa courbe satellite, chiffres clés, export Excel. |
| **Worker satellite** | Pour chaque champ, série NDVI Sentinel-2 depuis la date de semis, avec un statut et des alertes simples. |

Hors V1 : comptes des producteurs, SMS, rendement estimé, intrants autres que la semence, validation par un superviseur.

### Données collectées

**Producteur**
- nom, prénom, téléphone, numéro de carte de membre
- sexe, village / localité
- photo (facultative)
- consentement (une case cochée par l'agent, avec la date)

**Semences reçues**
- variété, quantité en kg, date de réception

**Champ** (un producteur peut en avoir plusieurs)
- contour GPS et surface mesurée (calculée)
- **surface emblavée déclarée** par le producteur
- date de semis
- irrigation : goutte-à-goutte, aspersion, raie, arrosoir…
- source d'eau : puits, forage, céane, bassin…
- photo géolocalisée

**Visites** (facultatives, en V1.1)
- date, stade observé, photo, remarque

La surface **mesurée** et la surface **déclarée** sont gardées toutes les deux. L'écart entre les deux est déjà un résultat utile pour la coopérative.

## 3. Ce qu'on reprend de Fieldproof, et ce qu'on change

| Brique Fieldproof | Reprise | Changement |
|---|---|---|
| `apps/agent` (Flutter) : `parcel_walk_page.dart`, `core/model/geo.dart` (surface, validité du contour), `core/photos.dart`, `core/json_store.dart`, `core/sync/outbox.dart`, `features/auth/sign_in_page.dart`, `ui/theme.dart` | **Copie** | On remplace les 9 étapes du dossier par 3 écrans : Producteur → Champ → Semis. On enlève le consentement signé, les pièces, la complétude et les statuts. |
| Synchronisation (ADR-0007) | L'idée seulement | Pas de statuts ni de verrou. L'agent écrit et le serveur fait un upsert par identifiant. Les photos montent avec reprise. |
| `db/migrations` | Modèle seulement | Un schéma **neuf et court** : `producers`, `fields`, `seed_distributions`, `ndvi_points`, `field_status`, `jobs`. Pas de `dossier`, `identity` ni `core` complet. |
| `workers/sat/sat/retro.py` : `scene_ndvi`, `select_items`, accès Planetary Computer, Dockerfile | **Copie** | On remplace l'analyse rétroactive par un **suivi depuis le semis**. La logique hivernage / contre-saison et le verdict de Fieldproof ne s'appliquent pas (voir §4). |
| `workers/sat/sat/radar.py` | Non | La pomme de terre pousse en saison sèche : le ciel est clair et Sentinel-2 suffit. |
| `apps/web` : `components/map/ParcelsMap*`, `superviseur/NdviChart.tsx`, `FilterBar.tsx`, `ui/*`, `AppHeader.tsx`, Tailwind | **Copie** | Un seul rôle, « coopérative ». On enlève tout ce qui concerne le prêteur et l'envoi. |
| `workers/docs` | Non | Le seul export est un Excel, généré directement dans le web. |

## 4. Suivi satellite de la pomme de terre

- **Campagne.** La pomme de terre se cultive en contre-saison froide et irriguée. Le semis a lieu de novembre à janvier et la récolte vers 90 à 110 jours. Les images sont claires presque tous les 5 jours.
- **Indicateur.** NDVI moyen sur le contour, à chaque image claire depuis la date de semis moins 15 jours. On le compare à une **courbe attendue en fonction du nombre de jours depuis le semis** :
  - sol nu au semis ;
  - levée vers J+20 à J+30 ;
  - pic vers J+50 à J+70 ;
  - sénescence ensuite.
- **Statuts d'un champ** : `en attente d'images` → `semé, sol nu` → `levée` → `en croissance` → `pic` → `sénescence / récolte`.
- **Alertes V1** :
  1. pas de levée à J+35 : semis non fait, échec, ou mauvais contour ;
  2. chute de NDVI de plus de 0,15 entre deux images hors fin de cycle : stress hydrique ou maladie, à vérifier ;
  3. champ déjà vert à la date de semis déclarée : date ou contour à vérifier.
- **Calcul.** Le worker recalcule tous les champs une fois par jour, plus une fois tout de suite quand un nouveau contour arrive.

**Limite à vérifier en premier.** En pomme de terre, les champs sont souvent petits. Un pixel Sentinel-2 couvre 10 m × 10 m. Un champ de 0,1 ha n'en contient que 10 environ, et un champ de 0,05 ha environ 5. Au-dessous de **0,1 ha**, le suivi est **indicatif** et doit être signalé comme tel. Il faut aussi retirer une marge de 5 m sur le bord du contour pour ne pas mesurer la bordure.

## 5. Architecture

Tout est neuf et **séparé de Fieldproof**.

- **Dépôt** : `22. Guis/`, avec `apps/agent` (Flutter), `apps/web` (Next.js), `workers/sat` (Python), `db/migrations` et `PROVENANCE.md`.
- **Supabase** : un **projet séparé**. Attention, l'offre gratuite n'autorise que 2 projets actifs par organisation.
- **Netlify** : un site séparé pour le tableau de bord.
- **Railway** : un service séparé pour le worker satellite.
- **Distribution de l'APK** : installation directe sur les téléphones des agents (fichier envoyé par WhatsApp ou par lien), sans Play Store. C'est le plus rapide.
- **Comptes** : agents et coopérative se connectent par e-mail (lien magique ou mot de passe). Les comptes sont créés à la main en V1.

## 6. Comment aller très vite

L'idée clé : **seule la collecte est urgente**. Les archives Sentinel-2 sont gratuites et conservées. Un champ relevé aujourd'hui pourra être analysé dans deux semaines **depuis sa date de semis**, sans rien perdre. Il faut donc mettre l'app dans les mains des agents d'abord, et faire le satellite ensuite.

| Jour | Livrable | Point de contrôle |
|---|---|---|
| **J1** | Dépôt créé, projet Supabase, schéma et politiques d'accès. Copie de l'app Flutter, réduite à Producteur → Champ → Semis, avec synchronisation. | Un champ saisi sur téléphone apparaît dans la base. |
| **J2** | APK signée, test sur 1 ou 2 vrais champs avec un agent, corrections. Création des comptes des agents. | **Les agents commencent la collecte.** |
| **J3** | Tableau de bord : connexion, carte, liste, fiche du champ, export Excel. | La coopérative voit ses champs. |
| **J4–J5** | Worker satellite : copie de `scene_ndvi`, suivi depuis le semis, statuts, alertes. Calcul sur tous les champs déjà collectés. Courbe dans la fiche du champ. | Courbes et alertes en ligne. |
| **Ensuite** | Visites terrain, réglage des seuils sur les premiers champs, rapport mensuel. | — |

Règles pour tenir les délais :

- **Une session de travail par surface**, dans le nouveau dossier : app (J1–J2), web (J3), satellite (J4–J5). Chacune part de cette note, jamais du dépôt Fieldproof directement.
- **Copier, puis supprimer.** On copie un fichier Fieldproof qui fonctionne, on retire ce qui ne sert pas et on note la copie dans `PROVENANCE.md`. On ne réécrit pas à partir de zéro.
- **Aucun écran de configuration.** Les listes (variétés, villages, types d'irrigation) sont des tables remplies par script.
- **Toute la saisie de l'app tient sur 3 écrans.** Un seul champ obligatoire à la fois, et la synchronisation ne bloque jamais l'agent.

## 7. À trancher avant J1

Les valeurs par défaut entre parenthèses s'appliquent si rien n'est décidé.

1. ~~Nom du projet et de l'application~~ : **Guis**, décidé le 23/11/2026. App Android « Guis », site « Guis — tableau de bord ».
2. **Coopérative, zone et villages** : par exemple Niayes, vallée du fleuve… (à renseigner).
3. **Volume** : nombre de producteurs et nombre d'agents qui collectent, pour dimensionner les comptes et le calendrier (environ 300 producteurs, 5 agents).
4. **Taille habituelle des champs.** C'est ce qui décide si le satellite est fiable (voir §4).
5. **Qui voit le tableau de bord** : la coopérative seule, ou aussi IBRIZ et un bailleur ? Chacun voit-il tout ? (coopérative et IBRIZ, tout).
6. **Un producteur peut-il avoir plusieurs champs ?** (oui)
7. **Consentement.** Une case cochée par l'agent après lecture d'un texte court suffit-elle ? Le téléphone est une donnée personnelle. Prévoir aussi la déclaration à la CDP si la coopérative ne l'a pas déjà faite (oui, la case suffit en V1).
8. **Liste des variétés distribuées et quantité par producteur.** La coopérative a-t-elle déjà un fichier de distribution à importer ? Si oui, les agents n'ont plus qu'à compléter le champ et le semis.
