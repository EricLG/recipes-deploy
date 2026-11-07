#!/bin/bash
# Sauvegarde applicative : MongoDB et volume uploads, sans secrets ni infra.
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

BACKUP_DIR="$(cd .. && pwd)/backups"

log() { printf '%s\n' "$*" >&2; }
die() { log "Erreur : $*"; exit 1; }
work=''
resume_backend=0
resume_frontend=0
restoring=0
cleanup() {
    local code=$?
    trap - EXIT
    if (( restoring && code != 0 )); then
        log 'Restauration interrompue : services laisses arretes. Corriger puis relancer restore.'
    else
        if (( resume_backend )); then
            docker compose start backend >&2 || code=1
        fi
        if (( resume_frontend )); then
            docker compose start frontend >&2 || code=1
        fi
    fi
    if [[ -n "$work" ]]; then rm -rf -- "$work"; fi
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mongo() {
    docker compose exec -T mongodb sh -eu -c '
        exec "$@" --username "$MONGO_INITDB_ROOT_USERNAME" \
            --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin
    ' sh "$@"
}
database() {
    docker compose exec -T mongodb sh -eu -c 'printf "%s" "$MONGO_INITDB_DATABASE"'
}
uploads() {
    # Le service fournit son image et son volume ; aucun npm/start applicatif.
    docker compose run --rm -T --no-deps --user 0 --entrypoint sh backend -eu -c "$1"
}
stop_writers() {
    if docker compose ps --status running --services | grep -qx backend; then
        resume_backend=1
        docker compose stop backend >&2
    fi
}
verify() {
    local archive=$1 members expected
    [[ -f "$archive" ]] || die "Archive introuvable : $archive"
    members=$(tar -tzf "$archive")
    expected=$(printf '%s\n' SHA256SUMS database format mongodb.gz uploads.tar.gz | sort)
    [[ "$(printf '%s\n' "$members" | sort)" == "$expected" ]] || die 'Contenu ou format d archive inconnu (anciennes sauvegardes MongoDB non prises en charge).'
    # Extraire uniquement le contenu de fichiers nommes, jamais leurs chemins.
    for member in format database mongodb.gz uploads.tar.gz SHA256SUMS; do
        tar -xOzf "$archive" "$member" > "$work/$member"
    done
    [[ "$(cat "$work/format")" == recipes-backup-v1 ]] || die 'Version inconnue.'
    # Comparer les checksums recalcules : ne pas interpreter des chemins fournis par l archive.
    (cd "$work"; sha256sum format database mongodb.gz uploads.tar.gz) > "$work/actual"
    cmp -s "$work/actual" "$work/SHA256SUMS" || die 'Sommes de controle invalides.'
    gzip -t "$work/mongodb.gz"
    tar -tzf "$work/uploads.tar.gz" > "$work/paths"
    while IFS= read -r path; do
        [[ "$path" == ./ || "$path" == ./* ]] || die 'Chemin uploads invalide.'
        [[ "/$path/" != *'/../'* ]] || die 'Chemin uploads hors volume.'
    done < "$work/paths"
    # Les images sont des fichiers ordinaires : refuser liens et fichiers speciaux.
    tar -tvzf "$work/uploads.tar.gz" > "$work/types"
    if grep -q '^[^-d]' "$work/types"; then die 'Liens ou fichiers speciaux interdits dans uploads.'; fi
    log 'Archive verifiee (integrite et structure).'
}
create() {
    local name destination
    name="recipes_backup_$(date -u +%Y%m%d_%H%M%S)_$$.tar.gz"
    destination="$BACKUP_DIR/$name"
    database > "$work/database"
    [[ -s "$work/database" ]] || die 'Nom de base absent.'
    printf 'recipes-backup-v1\n' > "$work/format"
    stop_writers
    log 'Sauvegarde MongoDB et images...'
    docker compose exec -T mongodb sh -eu -c '
        exec mongodump --username "$MONGO_INITDB_ROOT_USERNAME" \
          --password "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin \
          --db "$MONGO_INITDB_DATABASE" --archive --gzip
    ' > "$work/mongodb.gz"
    uploads 'cd /app/uploads; tar -czf - .' > "$work/uploads.tar.gz"
    (cd "$work"; sha256sum format database mongodb.gz uploads.tar.gz) > "$work/SHA256SUMS"
    tar -czf "$work/archive.tar.gz" -C "$work" format database mongodb.gz uploads.tar.gz SHA256SUMS
    verify "$work/archive.tar.gz"
    # Publication uniquement apres succes, sur le meme systeme de fichiers.
    mv -- "$work/archive.tar.gz" "$destination"
    log 'Sauvegarde terminee. Aucune ancienne archive supprimee automatiquement.'
    printf '%s\n' "$destination"
}
restore() {
    local answer target
    verify "$1"
    target=$(database)
    [[ -n "$target" && "$(cat "$work/database")" == "$target" ]] || die 'La base cible differe de celle de l archive.'
    log "ATTENTION : remplacement de la base $target ET de toutes les images."
    read -r -p 'Saisir RESTORE pour confirmer : ' answer
    [[ "$answer" == RESTORE ]] || die 'Restauration annulee.'
    stop_writers
    if docker compose ps --status running --services | grep -qx frontend; then
        resume_frontend=1
        docker compose stop frontend >&2
    fi
    restoring=1
    # Un remplacement exact doit aussi supprimer les collections absentes du dump.
    mongo mongosh --quiet --eval 'if (db.getSiblingDB(process.env.MONGO_INITDB_DATABASE).dropDatabase().ok !== 1) quit(1)' >&2
    mongo mongorestore --archive --gzip --stopOnError < "$work/mongodb.gz"
    uploads 'cd /app/uploads; find . -mindepth 1 -maxdepth 1 -exec rm -rf -- {} \;; tar -xzf -; chown -R 1001:1001 .' < "$work/uploads.tar.gz"
    restoring=0
    log 'Base et images restaurees. Verifier ensuite les healthchecks et le site.'
}

case "${1:-help}" in
    help|--help|-h)
        echo 'Usage : bash scripts/backup.sh create | verify <archive> | list | restore <archive>'
        exit 0 ;;
    create|verify|restore|list) ;;
    *) die 'Commande inconnue.' ;;
esac
for tool in docker tar gzip sha256sum flock cmp; do
    command -v "$tool" > /dev/null || die "Commande manquante : $tool"
done
mkdir -p "$BACKUP_DIR"
exec 9>"$BACKUP_DIR/.backup.lock"
flock -n 9 || die 'Une sauvegarde ou restauration est deja en cours.'
work=$(mktemp -d "$BACKUP_DIR/.work.XXXXXXXX")
case "$1" in
    create) create ;;
    verify) verify "${2:?Fournir une archive}" ;;
    restore) restore "${2:?Fournir une archive}" ;;
    list) find "$BACKUP_DIR" -maxdepth 1 -type f -name 'recipes_backup_*.tar.gz' -print | sort -r ;;
esac
