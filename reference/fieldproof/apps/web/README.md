# `apps/web` — application web Fieldproof

Next.js 15 (App Router), TypeScript, Tailwind, `@supabase/ssr`. Trois surfaces :

- **Agent terrain** (`/agent`) : repli web de l'application Flutter, pensé pour le téléphone.
- **Superviseur** (`/superviseur`) : vérification, renvoi, envoi au prêteur, suivi des retours.
- **Prêteur** (`/l/<jeton>`) : pages du lien sécurisé, sans compte.

Toute écriture passe par les RPC de la base (`db/migrations`, contrat) ; la RLS décide de ce que chacun lit.

## Lancer en local

```bash
cd apps/web
npm install
cp .env.local.example .env.local   # puis renseigner les valeurs
npm run dev                        # http://localhost:3000
```

Vérifications : `npm run lint`, `npm run typecheck`, `npm run build`.
Pour construire sans gêner un `npm run dev` en cours : `NEXT_DIST_DIR=.next-build npm run build`.

## Variables d'environnement

| Variable | Usage |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | URL du projet Supabase (publique). |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Clé anon (publique) : navigateur, serveur, pages du lien sécurisé. |
| `SUPABASE_SERVICE_ROLE_KEY` | **Serveur uniquement.** Signe l'URL de 60 s d'un téléchargement du prêteur (`/l/<jeton>/doc/<id>`) et lit l'état de génération (`/l/<jeton>/etat`). Jamais exposée au navigateur. |
| `NEXT_PUBLIC_APP_URL` | URL publique, pour construire le lien sécurisé affiché au superviseur. Production : `https://fieldproof-sn.netlify.app` ; local : `http://localhost:3000`. |

## Routes

| Route | Rôle | Contenu |
|---|---|---|
| `/login` | public | Connexion e-mail / mot de passe. |
| `/` | connecté | Redirige selon le rôle (`core.my_memberships()`). |
| `/agent` | `field_agent` | Mes dossiers : statut, motif de renvoi, paquets. |
| `/agent/dossier/nouveau` | `field_agent` | Crée le brouillon (UUID générés sur l'appareil). |
| `/agent/dossier/<id>?etape=…` | `field_agent` | Parcours guidé : Client, Adresse, Exploitation, Parcelles (marcher le contour au GPS ou placer les sommets sur l'imagerie), Besoin, Compléments (configuration prêteur), Pièces (photo, compression 1600 px, versions), Consentement (finalités, signature ou trait, photo, GPS), Récapitulatif (complétude) et Soumission. Sauvegarde automatique (`save_draft`), copie locale dans `localStorage` et reprise après coupure. |
| `/superviseur` | `field_supervisor`, `org_admin`, `platform_admin` | Tableau de bord : statuts, dossiers à vérifier, retours du prêteur, envois récents, carte des parcelles. |
| `/superviseur/dossiers` | idem | Liste filtrable (statut, agent, région, recherche nom / référence / téléphone). |
| `/superviseur/dossiers/<id>` | idem | Fiche complète : carte satellite, analyse rétroactive (verdict, saisons, NDVI), pièces, consentements, complétude, paquets, envois et journal du lien, historique. Actions : renvoyer (motif), choisir la caisse, envoyer (règle du paquet de crédit), révoquer un lien, retirer un consentement. |
| `/l/<jeton>` | public | Page du prêteur : paquets, documents, déclaration Reçu → Intégré (référence) / Rejeté (motif). Gère « en préparation » (rafraîchissement automatique), liens expirés, révoqués ou invalides. |
| `/l/<jeton>/doc/<id>` | public | Téléchargement journalisé (`link_document`) puis redirection vers une URL signée de 60 s. |
| `/l/<jeton>/etat` | public | État de génération des paquets (sans donnée du dossier, sans ligne de journal). |
| `/deconnexion` | connecté | Déconnexion (POST). |

## Rôles

- `field_agent` → `/agent` ; n'écrit que ses dossiers en brouillon ou renvoyés.
- `field_supervisor`, `org_admin`, `platform_admin` → `/superviseur`.
- Le prêteur n'a pas de compte : il agit uniquement par le lien sécurisé.

Comptes de démonstration (bac à sable FIELDPROOF-QA, données fictives) : voir `.demo-accounts.local.md` à la racine du dépôt (non commité).

## Déploiement Netlify

`netlify.toml` (base `apps/web`, `@netlify/plugin-nextjs`). Déclarer les quatre variables ci-dessus dans Netlify ; `SUPABASE_SERVICE_ROLE_KEY` en variable serveur seulement.

## Limites connues

- Hors ligne : la saisie et le brouillon sont gardés sur l'appareil et renvoyés au retour du réseau ; les photos, elles, doivent être prises avec du réseau (pas de file d'envoi des pièces sur le web, c'est le rôle de l'app Flutter).
- Le lien sécurisé n'est affiché qu'une fois, à l'envoi (le jeton n'est pas stocké en clair). S'il est perdu et que le mail n'est pas parti, révoquer puis renvoyer.
