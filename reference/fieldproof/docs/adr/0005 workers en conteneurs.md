# ADR-0005 — Les traitements tournent dans deux conteneurs Docker portables

Statut : Accepté — 19/11/2026

## Décision
- worker-docs (Node) : rendu des documents, envoi des mails, SMS éventuels.
- worker-sat (Python) : traitements satellite (Sentinel-2, Sentinel-1), analyses rétroactives, suivi.
- Ils consomment une table de travaux alimentée par les événements de domaine en base.
- Déploiement sur une plateforme de conteneurs gérée pour le pilote (Railway ou équivalent) ; l'image tourne à l'identique sur un VPS ou un datacenter local (cohérent avec ADR-0004).
- Les pages du lien sécurisé sont servies par l'application web Next.js. Pas de fonctions Supabase (Edge Functions).

## Alternatives écartées
- Edge Functions : ne font tourner ni LibreOffice/Carbone ni le calcul raster ; enferment le traitement chez Supabase.
