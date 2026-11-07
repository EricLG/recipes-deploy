# Restauration locale

Depuis la racine du workspace (Python 3.13+, Node et dependances backend installes) :

```powershell
python recipes-deploy/scripts/restore-local.py backups/recipes_backup_DATE_PID.tar.gz --verify-only
python recipes-deploy/scripts/restore-local.py backups/recipes_backup_DATE_PID.tar.gz
```

Arreter le backend de developpement avant restauration. MongoDB local doit tourner,
et `mongodump` / `mongorestore` doivent etre dans le PATH. Le script lit uniquement
`MONGODB_URI` de `recipes-back/.env`, sans afficher ses identifiants. Il refuse une
adresse distante, une autre base que celle de l'archive et les bases systeme.
`--yes` permet de confirmer explicitement sans invite interactive.

Le format accepte est `recipes-backup-v1` produit par `recipes-deploy/scripts/backup.sh`.
Les checksums et les chemins des images sont verifies avant toute modification.
La base locale est remplacee integralement, ainsi que `recipes-back/uploads`.
Les URL `/api/uploads/recipes/...` restent identiques, utilisables par le dev local.
Les utilisateurs/mots de passe applicatifs deviennent ceux de la sauvegarde NAS.

Avant le remplacement, l'etat local est conserve dans
`backups/local-before-DATE-ID/` : dump gzip, images et compte des documents.
Ne pas supprimer ce dossier avant validation. Aucun fichier du NAS n'est modifie.
En cas d'echec apres le debut du remplacement, garder le backend arrete et relancer
la restauration apres correction. Aucun rollback automatique n'est effectue.
Pour revenir en arriere, restaurer le dump `mongodb.gz` dans la meme base locale
(apres suppression de cette base uniquement) et remettre le dossier `uploads`
de recuperation dans `recipes-back/uploads`.

Le script verifie les fichiers d'images references directement dans les recettes
et affiche le nombre de documents de chaque collection apres restauration.
Tester ensuite connexion, affichage des recettes et images dans le navigateur.
Une sauvegarde conservee sur un autre support reste necessaire.

Tests de validation du format et des chemins d'archive :

```powershell
python -m unittest discover -s recipes-deploy/scripts/tests -p test_restore_local.py
```

## Transfert depuis le NAS

Les anciens scripts de migration et de synchronisation ont ete retires.
Copier manuellement l'archive produite par `recipes-deploy/scripts/backup.sh` dans
`backups/`, puis utiliser `scripts/restore-local.py`. Le transfert SSH automatise
reste a traiter separement.

Les archives et recuperations locales sont conservees dans le dossier `backups/`
a la racine du workspace, a cote des trois depots.

`scripts/src/local-mongo.cjs` est un helper interne : il lit la configuration locale du backend,
controle la cible, supprime la base lors du remplacement et verifie les documents
et images apres restauration. Il ne doit pas etre lance directement.
