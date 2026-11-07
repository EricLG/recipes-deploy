# recipes-deploy

Configuration Docker et outils de deploiement, sauvegarde et restauration de
recipes. La stack applicative comprend Angular/Nginx, NestJS et MongoDB ;
le reverse proxy HTTPS et DuckDNS sont geres par infra-stack.

## Documentation

- [Architecture et organisation](docs/architecture.md)
- [Deploiement sur le NAS et migration reseau](docs/GUIDE_DEPLOIEMENT.md)
- [Sauvegarde et restauration sur le NAS](docs/BACKUPS.md)
- [Restauration de la base et des images en local](docs/RESTORE_LOCAL.md)

## Outils

- `scripts/deploy.sh` : gestion des services et deploiement.
- `scripts/backup.sh` : sauvegarde et restauration completes sur le NAS.
- `scripts/restore-local.py` : restauration dans le MongoDB local et recipes-back/uploads.
- `scripts/src/local-mongo.cjs` : helper interne du script de restauration locale.

Les secrets `.env`, les archives et les donnees de recuperation de `../backups/`
restent exclus de Git. Les commandes et prerequis sont detailles dans la documentation.

## Organisation

- `docker-compose.yml` : orchestration des services, conservee a la racine.
- `config/` : Dockerfiles backend/frontend, configuration Nginx et modele dockerignore.
- `scripts/` : scripts de gestion, restauration locale et leurs tests dans `tests/`.
- `docs/` : documentation.
- `../backups/` : archives et recuperations locales, hors du depot Git.

Depuis la racine recipes-deploy : `bash scripts/deploy.sh deploy` ou
`bash scripts/backup.sh create`. Le deploiement copie les fichiers de `config/`
dans les contextes de build voisins avant construction des images.
Les fichiers caches `.env`, `.env.exemple`, `.gitignore` et `.gitattributes`
restent a la racine ; ne pas deplacer le `.env` du NAS lors de la mise a jour.

Structure du workspace :

```text
recipes/
  recipes-back/
  recipes-front/
  recipes-deploy/
  backups/
```
