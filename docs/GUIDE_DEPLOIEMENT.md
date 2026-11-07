# Deploiement et migration vers infra-stack

## Prerequis

Docker Compose v2 avec `up --wait` et `--wait-timeout`, reseau externe
`proxy-network` deja present, infra-stack en fonctionnement.
Les depots `recipes-back`, `recipes-front` et `recipes-deploy` sont voisins dans
`/volume1/docker/apps/recipes`. Les scripts necessitent Bash.

Pour une nouvelle installation : copier `.env.exemple` vers `.env` et remplacer
toutes les valeurs de demonstration. Ne jamais versionner `.env`.
DuckDNS, TLS et les regles publiques appartiennent a infra-stack.
Le backend ecoute toujours sur 3000, comme le proxy interne et son healthcheck.

## Migration du NAS existant

1. Avant de remplacer les fichiers, sauvegarder le Compose et la configuration
   actuelle hors du depot. Executer `./scripts/deploy.sh backup` avec le script existant.
   Sauvegarder aussi le volume uploads et la configuration infra-stack avec les
   outils habituels du NAS : la commande backup ne couvre que MongoDB.
2. Transferer les fichiers modifies de recipes-deploy, sans remplacer `.env`,
   sans supprimer `backups`, `ssl` ni aucun volume. Ne pas changer le nom du
   dossier recipes-deploy ni utiliser un autre nom de projet Compose.
3. Depuis le NAS :

   ```bash
   cd /volume1/docker/apps/recipes/recipes-deploy
   docker network inspect proxy-network > /dev/null
   docker compose config --quiet
   docker compose up -d --no-build --no-deps frontend
   docker compose ps
   ```

   Cette etape reutilise l'image existante et ajoute le frontend au reseau
   partage. Une courte interruption du frontend est possible.
4. Dans Nginx Proxy Manager, modifier uniquement la destination du domaine
   `la-taverne-de-may.duckdns.org` : HTTP, hostname `recipes-frontend`, port 80.
   Conserver le certificat et les autres options existantes.
5. Tester le site, la connexion, une recette avec image et un appel API.
   En cas de probleme, remettre temporairement le hostname `frontend` :
   l'ancien reseau est encore connecte au proxy a ce stade.
6. Apres validation, dans le Compose infra-stack, retirer `app-network` des
   reseaux du service nginx-proxy-manager et supprimer sa declaration externe
   `name: recipes-deploy_app-network`. Conserver `proxy-network` et `infra`.
   Appliquer depuis le dossier infra-stack :

   ```bash
   docker compose config --quiet
   docker compose up -d --no-deps nginx-proxy-manager
   ```

   Cette recreation interrompt brievement le proxy de toutes les applications.
   Tester ensuite recipes et les autres domaines.
7. Supprimer uniquement l'ancien DuckDNS recipes, apres verification de son
   appartenance (le label affiche doit etre `recipes-deploy`) :

   ```bash
   docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' duckdns
   docker stop duckdns
   docker rm duckdns
   ```

   Ne pas utiliser `--remove-orphans` pour cette migration. Les anciens volumes
   `npm_data` et `npm_letsencrypt` ne sont plus declares mais restent sur le NAS.
   Les conserver jusqu'a verification ; aucune suppression n'est necessaire.

## Deploiements suivants

```bash
./scripts/deploy.sh deploy
./scripts/deploy.sh status
./scripts/deploy.sh logs backend
```

Le script construit avant de mettre les services a jour, sans arreter toute la
stack. Il attend leur sante pendant au maximum 180 secondes et retourne un echec
si cette verification echoue. Cela ne remplace pas un test de connexion et des
parcours metier apres deploiement. Il ne configure pas le proxy partage.

`./scripts/deploy.sh stop` arrete la stack recipes ; `start` la redemarre.
`restart frontend` redemarre seulement le frontend.

## Sauvegardes

Voir [BACKUPS.md](BACKUPS.md) pour la sauvegarde et la restauration de MongoDB
et des images via `scripts/backup.sh`. `scripts/deploy.sh backup` et `scripts/deploy.sh restore` deleguent
au nouveau script. La synchronisation locale et infra-stack restent separees.

`./scripts/deploy.sh clean` supprime les conteneurs et volumes recipes apres confirmation.
MongoDB et images sont alors perdus. Ne pas utiliser pour une maintenance normale.
