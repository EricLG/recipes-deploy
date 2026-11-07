# Deployment recipes sur le NAS

La stack contient MongoDB, le backend NestJS et le frontend Nginx/Angular.
DuckDNS et Nginx Proxy Manager sont geres par `infra-stack`.

Voir [GUIDE_DEPLOIEMENT.md](GUIDE_DEPLOIEMENT.md) pour la migration et les commandes.
Voir [BACKUPS.md](BACKUPS.md) pour sauvegarder et restaurer MongoDB et les images.

Architecture : proxy partage -> recipes-frontend:80 -> backend:3000 -> mongodb:27017.
Le frontend rejoint le reseau externe `proxy-network` avec l'alias `recipes-frontend`.
`app-network` relie le frontend au backend ; `backend-network` est interne et relie
le backend a MongoDB. Le port 8080 est accessible uniquement depuis le NAS.

Le dossier de travail reste `/volume1/docker/apps/recipes/recipes-deploy` :
conserver ce nom de projet pour reutiliser les volumes existants.

## Contextes de build Docker

`config/dockerignore` est le modele commun copie par `scripts/deploy.sh` dans
`recipes-back/.dockerignore` et `recipes-front/.dockerignore` avant les builds.
Il exclut notamment les dependances locales, builds precedents, caches, fichiers
`.env`, historique Git, uploads et sauvegardes. Les sources, assets et fichiers
de verrouillage npm restent disponibles pour construire les images.
Ainsi `COPY . .` du frontend ne remplace pas les dependances Linux installees
dans l'image par celles du poste Windows.

Le Dockerfile backend cree `/app/uploads/recipes` vide et accessible a son
utilisateur applicatif. Les images proviennent exclusivement du volume uploads
en production ; reconstruire l'image ne copie ni ne supprime les images du NAS.
Un volume deja existant conserve son contenu et ses permissions.

Utiliser `bash scripts/deploy.sh deploy` pour preparer les contextes puis construire.
Si les builds sont lances manuellement, copier d'abord les deux Dockerfiles,
`nginx.conf` et les deux `.dockerignore` comme le fait `prepare_build_files`.

Verification sans Docker : `bash scripts/tests/build-files.test.sh`.
La construction effective et les healthchecks restent a valider sur le NAS.
