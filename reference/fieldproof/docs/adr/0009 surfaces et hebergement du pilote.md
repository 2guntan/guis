# ADR-0009 — Surfaces et hébergement du pilote : web complet + app Flutter, Netlify, Railway

Statut : Accepté — 20/11/2026 (décisions prises par délégation du porteur, nuit du 19 au 20/11)

## Contexte
Le porteur a demandé une application fonctionnelle au réveil et délégué les décisions. L'ADR-0007 prévoit l'app agent en Flutter hors ligne ; les formulaires officiels PAMECAS et le service de mail ne sont pas encore disponibles.

## Décision
- **Deux surfaces pour l'agent terrain** : l'app Flutter (Android, hors ligne, ADR-0007) et la même collecte dans l'app web, adaptée au téléphone. Le web sert de repli tant que l'APK n'est pas installé sur les téléphones du pilote ; les deux écrivent par les mêmes RPC (`dossier.save_draft`, `register_document`, `record_consent`, `submit_file`), donc les mêmes règles.
- **App web Next.js** (superviseur, agent, pages du lien sécurisé) sur **Netlify**, équipe ibriz.
- **Workers** (worker-docs Node, worker-sat Python) en conteneurs Docker sur **Railway** (ADR-0005).
- **Formulaires du prêteur** : en attendant les modèles officiels PAMECAS, worker-docs produit un formulaire **provisoire** marqué comme tel, derrière l'interface d'adaptateur de rendu (ADR-0006). La configuration PAMECAS en base est elle aussi marquée provisoire.
- **Mails** : sans clé de service d'envoi, l'envoi est journalisé (`logged_only`) et le superviseur copie le lien sécurisé affiché. Le passage à l'envoi réel demande seulement `RESEND_API_KEY` et `MAIL_FROM` sur worker-docs, avec le domaine propre (ADR-0008).
- **Analyse rétroactive** : Sentinel-2 L2A via Microsoft Planetary Computer (accès anonyme, sans compte) ; Sentinel-1 pour l'hivernage en Casamance reste à faire.
- Données de démonstration uniquement dans le bac à sable `FIELDPROOF-QA`.

## Conséquences
- Plan Supabase Free : pas de sauvegarde, mise en pause après inactivité. Passage en Pro avant la première vraie collecte.
- Avant la première collecte réelle : modèles officiels PAMECAS dans `config.templates` et `config.mapping`, liste des caisses et adresses dans `dossier.branch_routes`, adresse centrale, texte de consentement validé (version dans `consent_notice_version`), service de mail.
