# workers/sat : suivi satellite NDVI (Sentinel-2)

Pour chaque champ relevé, le worker lit les images Sentinel-2 L2A de Microsoft Planetary Computer (accès anonyme) depuis la date de semis moins 15 jours. Il en tire une valeur de NDVI par image claire, mesurée sur le contour moins une marge de 5 m, puis il calcule le statut du champ et ses alertes (`sat/status.py`, NOTE-CADRAGE.md §4).

- **Quand ?** Tout de suite après un nouveau contour ou une nouvelle date de semis (déclencheur en base), puis une fois par jour pour tous les champs (après `SAT_DAILY_HOUR_UTC`, 4 h par défaut). Les images déjà mesurées ne sont pas relues.
- **Statuts** : en attente d'images, semé / sol nu, levée, en croissance, pic, sénescence / récolte.
- **Alertes** : pas de levée à J+35 ; chute de NDVI de plus de 0,15 entre deux images claires avant J+80 ; champ déjà vert au semis.
- **Suivi indicatif** : champ de moins de 0,1 ha, ou marge de 5 m impossible (aucun pixel restant).
- Les seuils sont des constantes en tête de `sat/status.py`, à recalibrer sur les premiers champs.

## Essai local sur un carré, sans base

```bash
pip install -r requirements.txt
python -m sat.scenes 15.135 -16.86 2026-10-20 150   # lat, lng, date de semis, côté en mètres
```

## Tests

```bash
pip install pytest
python -m pytest -q                      # statut (fonction pure)
DATABASE_URL=postgres://… python -m pytest -q   # + worker contre PostGIS (schéma appliqué par apps/web/scripts/migrate.mjs)
```
