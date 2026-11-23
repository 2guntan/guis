# apps/web : tableau de bord et API de l'app Android

Next.js (App Router) + PostgreSQL/PostGIS via `pg`. Sessions par jeton opaque (`Authorization: Bearer` pour l'app, cookie `guis_session` pour le tableau de bord).

## Développement

```bash
docker run -d --name guisdb -e POSTGRES_PASSWORD=dev -e POSTGRES_DB=guis -p 5432:5432 postgis/postgis:16-3.4
export DATABASE_URL=postgres://postgres:dev@localhost:5432/guis
npm install
npm run migrate
GUIS_PASSWORD=motdepasse npm run create-user -- --phone "77 000 00 01" --name "Admin" --role admin
npm run dev
```

## Tests

Les tests parlent HTTP au serveur lancé (`GUIS_TEST_URL`, par défaut `http://localhost:3000`) et lisent la même base (`DATABASE_URL`). Ils **vident la base** : ne jamais les lancer contre la production.

```bash
npm run dev &      # ou npm start après npm run build
npm test
```

## Contrat de l'API de l'app

Toutes les réponses d'erreur ont la forme `{ "error": "message en français" }`.
- 400, 403, 404, 409, 422 : refus définitif (l'app l'affiche et ne réessaie pas seule) ;
- 401, 408, 429, 5xx : l'app réessaie plus tard.

| Méthode | Chemin | Rôle |
|---|---|---|
| POST | `/api/auth/login` | `{phone, password}` → `{token, user}` |
| POST | `/api/auth/logout` | révoque le jeton |
| GET | `/api/auth/me` | compte du jeton |
| GET | `/api/health` | santé (base joignable) |
| GET | `/api/app/bootstrap` | compte, listes (villages, variétés, irrigation, sources d'eau), tous les producteurs, semences et champs |
| PUT | `/api/app/producers/{id}` | upsert d'un producteur : identité, `consent_at` (obligatoire), `seeds[]` (upsert par `id`), `deleted_seed_ids[]` |
| PUT | `/api/app/fields/{id}` | upsert d'un champ : `producer_id`, `name`, `contour[]` (`lat`, `lng`, `accuracy_m`, `captured_at`), `area_declared_ha`, `sown_on`, `irrigation`, `water_source`, `photo_id`. Surface mesurée calculée par PostGIS ; contour qui se croise ou < 100 m² refusé (422) ; nouveau contour ou nouvelle date de semis → calcul satellite |
