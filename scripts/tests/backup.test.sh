#!/bin/bash
# Tests sans Docker : vrais tar/gzip/checksums, services simules.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/images" "$fixture/project/scripts"
cp "$root/backup.sh" "$fixture/project/scripts/backup.sh"
printf image > "$fixture/images/photo.png"
export fixture
flock() { return 0; }
docker() {
    printf '%s\n' "$*" >> "$fixture/calls"
    case "$*" in
        'compose ps --status running --services') printf 'backend\nfrontend\n' ;;
        'compose exec -T mongodb sh -eu -c printf'* ) printf recipes ;;
        *mongodump*)
            if [[ "${FAIL_DUMP:-0}" == 1 ]]; then return 1; fi
            printf 'simulated mongo dump' | gzip ;;
        *mongorestore*)
            if [[ "${FAIL_RESTORE:-0}" == 1 ]]; then return 1; fi
            cat > "$fixture/restored.dump" ;;
        'compose run '*tar\ -czf*) tar -czf - -C "$fixture/images" . ;;
        'compose run '*tar\ -xzf*) cat > "$fixture/restored.images" ;;
    esac
}
export -f docker flock
archive=$(bash "$fixture/project/scripts/backup.sh" create)
[[ -f "$archive" ]]
grep -q 'compose start backend' "$fixture/calls"
bash "$fixture/project/scripts/backup.sh" verify "$archive"
printf 'RESTORE\n' | bash "$fixture/project/scripts/backup.sh" restore "$archive"
gzip -dc "$fixture/restored.dump" | grep -q 'simulated mongo dump'
tar -xOzf "$fixture/restored.images" ./photo.png | grep -q image
grep -q 'compose start frontend' "$fixture/calls"
before=$(wc -l < "$fixture/calls")
if printf 'NO\n' | bash "$fixture/project/scripts/backup.sh" restore "$archive"; then exit 1; fi
! tail -n +"$((before + 1))" "$fixture/calls" | grep -q 'compose stop'
: > "$fixture/calls"
if FAIL_DUMP=1 bash "$fixture/project/scripts/backup.sh" create; then exit 1; fi
grep -q 'compose start backend' "$fixture/calls"
[[ $(find "$fixture/backups" -name 'recipes_backup_*.tar.gz' | wc -l) == 1 ]]
: > "$fixture/calls"
if printf 'RESTORE\n' | FAIL_RESTORE=1 bash "$fixture/project/scripts/backup.sh" restore "$archive"; then exit 1; fi
! grep -q 'compose start' "$fixture/calls"
printf broken > "$fixture/broken.tar.gz"
if bash "$fixture/project/scripts/backup.sh" verify "$fixture/broken.tar.gz"; then exit 1; fi
echo 'PASS: creation, verification, restauration, annulation, echec dump et corruption'
