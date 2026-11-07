# Deployment recipes sur le NAS

La stack contient MongoDB, le backend NestJS et le frontend Nginx/Angular.
DuckDNS et Nginx Proxy Manager sont geres par `infra-stack`.

Voir [GUIDE_DEPLOIEMENT.md](GUIDE_DEPLOIEMENT.md) pour la migration et les commandes.

Architecture : proxy partage -> recipes-frontend:80 -> backend:3000 -> mongodb:27017.
Le frontend rejoint le reseau externe `proxy-network` avec l'alias `recipes-frontend`.
`app-network` relie le frontend au backend ; `backend-network` est interne et relie
le backend a MongoDB. Le port 8080 est accessible uniquement depuis le NAS.

Le dossier de travail reste `/volume1/docker/apps/recipes/recipes-deploy` :
conserver ce nom de projet pour reutiliser les volumes existants.
