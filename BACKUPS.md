# Sauvegarder la base et les images

Depuis le NAS, dans recipes-deploy :

```bash
bash backup.sh create
bash backup.sh list
bash backup.sh verify backups/recipes_backup_DATE_PID.tar.gz
bash backup.sh restore backups/recipes_backup_DATE_PID.tar.gz
```

`deploy.sh backup` et `deploy.sh restore <archive>` restent des raccourcis.
Le script utilise les identifiants deja charges dans le conteneur MongoDB :
il ne lit ni n'execute le `.env`, et ne l'inclut pas dans l'archive.
Compose, Dockerfiles et `.env.exemple` restent geres dans Git.
Les vraies valeurs doivent etre conservees separement pour reconstruire le NAS.
Infra-stack et la synchronisation locale ne sont pas traites ici.

## Creation

L'API est arretee pendant le dump et la copie du volume uploads pour empecher
les modifications entre la base et les fichiers. Le frontend reste accessible,
mais les appels API echouent temporairement. Ne pas lancer de deploiement ni
d'ecriture directe MongoDB/uploads pendant cette operation.
L'API est redemarree si elle tournait avant, meme en cas d'echec du dump.
Un arret force du script ou du NAS peut necessiter `docker compose start backend`.

Une archive contient `format`, `database`, `mongodb.gz`, `uploads.tar.gz` et
`SHA256SUMS`. Tout le volume `/app/uploads` est sauvegarde, fichiers caches inclus.
Le helper utilise l'image backend existante, sans demarrer l'application.
Le dump est limite a la base applicative ; les comptes MongoDB ne sont pas copies.
L'archive n'est publiee qu'apres verification. Un verrou empeche deux operations
simultanees lancees par ce script. Les services initialement arretes le restent.

Les archives sont privees (umask 077), non chiffrees et ignorees par Git.
Aucune retention automatique : surveiller l'espace disque, supprimer les archives
anciennes seulement apres validation et conserver une copie sur un autre support.
Prevoir l'espace pour le dump, les images compressees et l'archive finale.

## Verification et restauration

`verify` controle le format, les sommes SHA-256, gzip et les chemins/types des
fichiers uploads. Il ne prouve pas qu'un dump est restaurable : tester une vraie
restauration dans une stack isolee avec des volumes neufs et le meme nom de base.
Les checksums detectent une corruption, pas une modification malveillante :
restaurer uniquement ses propres archives de confiance.

`restore` verifie avant toute modification et exige de saisir `RESTORE`.
Le nom de base cible doit correspondre a celui de l'archive. L'API et le frontend
sont arretes pendant le remplacement exact de la base et des uploads. Les images
restaurees recoivent l'UID/GID 1001 utilises par le Dockerfile backend.
Les services auparavant actifs sont redemarres a la fin. Une restauration echouee
apres le debut des modifications les laisse arretes pour eviter d'exposer un etat
partiel : corriger la cause et relancer la restauration. Il n'y a pas de rollback
automatique ; faire une sauvegarde de l'etat actuel avant de restaurer.
Apres succes, controler `docker compose ps`, connexion, recettes et images.

Les anciennes archives `mongodb_backup_*.tar.gz` sont conservees mais refusees
par ce script : elles ne contiennent aucune image. Ne pas les renommer pour les
faire passer pour des sauvegardes completes. Le script de synchro locale existant
devra etre adapte separement au nouveau format.

Prerequis : Bash, Docker Compose v2, images backend et MongoDB deja presentes,
GNU tar, gzip, sha256sum, cmp et flock (util-linux sur le NAS).
