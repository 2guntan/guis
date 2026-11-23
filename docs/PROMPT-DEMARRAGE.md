# Prompt de démarrage : session cloud Guis

Copier le bloc ci-dessous dans une nouvelle session ouverte sur le dépôt `2guntan/guis`.

---

```text
Tu développes Guis de bout en bout : une app Android de collecte des champs, un tableau de bord web et un suivi satellite.
Premier usage : les champs de pomme de terre des producteurs d'une coopérative partenaire.

Lis NOTE-CADRAGE.md (tout y est : données, suivi satellite, architecture sur un VPS Contabo en Docker Compose)
et reference/fieldproof/README.md (le code à reprendre de Fieldproof, fichier par fichier).

1. Commence par un grilling court (skill mattpocock grilling) sur les points ouverts du §7 de la note,
   une question à la fois, avec une valeur par défaut. Note les réponses dans NOTE-CADRAGE.md.
2. Ensuite, construis tout, dans cet ordre : app de collecte, puis tableau de bord, puis satellite.
   Stack : Flutter (Android), Next.js (tableau de bord et API REST de l'app), PostgreSQL et PostGIS,
   worker Python, Caddy, le tout dans un docker-compose.yml prêt pour le VPS. Une CI GitHub Actions
   construit l'APK.

Règles :
- reference/fieldproof/ se copie, ne se modifie pas. Chaque copie est notée dans PROVENANCE.md.
  Remplace la couche Supabase de Fieldproof par l'API de l'app web.
- Dépôt public : aucun secret ni donnée réelle de producteur dans git.
- Le plus simple qui marche. Textes de l'interface en français.

Le VPS (Ubuntu 24.04) est déjà commandé. Je te donne son adresse IP et une clé SSH en variables de session :
GUIS_VPS_HOST, GUIS_VPS_SSH_KEY. Elles ne doivent jamais apparaître dans git.
Quand tu as besoin d'autre chose de moi (nom de domaine, clé de signature de l'APK), demande-le.
```
