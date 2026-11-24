# Prompt de démarrage : session cloud Guis

Copier le bloc ci-dessous dans une nouvelle session ouverte sur le dépôt `2guntan/guis`.

---

```text
Tu développes Guis de bout en bout : une app Android de collecte des champs, un tableau de bord web et un suivi satellite.
Premier usage : les champs de pomme de terre des producteurs d'une coopérative partenaire.

Lis NOTE-CADRAGE.md (tout y est : données, suivi satellite, architecture sur un VPS Contabo en Docker Compose)
et reference/fieldproof/README.md (le code à reprendre de Fieldproof, fichier par fichier).

1. Les points du §7 sont déjà tranchés. Construis dans cet ordre : app de collecte, puis tableau de bord, puis satellite.
   Stack : Flutter (Android), Next.js (tableau de bord et API REST de l'app), PostgreSQL et PostGIS,
   worker Python, Caddy, le tout dans un docker-compose.yml prêt pour le VPS. Une CI GitHub Actions
   construit l'APK.

Règles :
- reference/fieldproof/ se copie, ne se modifie pas. Chaque copie est notée dans PROVENANCE.md.
  Remplace la couche Supabase de Fieldproof par l'API de l'app web.
- Dépôt public : aucun secret ni donnée réelle de producteur dans git.
- Le plus simple qui marche. Textes de l'interface en français.

Le VPS (Ubuntu 24.04) est déjà commandé. Avant de demander un accès, lance
`python3 deploy/doctor.py` : il vérifie les variables de session et la configuration privée
`~/.config/guis/deploy.env`, sans afficher l'IP ni la clé. Les variables d'une ancienne
session Claude ne persistent pas automatiquement. Si l'IP ou la clé manque encore,
demande seulement le paramètre manquant. N'écris jamais ces données dans git.
Le domaine propre est facultatif : avec une IP publique, utilise `guis.<IP>.sslip.io`.
La clé de signature de l'APK est distincte de la clé SSH et ne doit être demandée
qu'au moment de produire une version installable durablement.
```
