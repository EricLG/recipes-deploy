#!/bin/bash
# Verifier les copies dans des projets temporaires, sans Docker ni donnees reelles.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/recipes-deploy/scripts" "$fixture/recipes-deploy/config" \
    "$fixture/recipes-back" "$fixture/recipes-front"
cp "$root"/config/{Dockerfile.backend,Dockerfile.frontend,nginx.conf,dockerignore} "$fixture/recipes-deploy/config/"
# Charger uniquement les definitions, sans lancer de deploiement.
sed '/^case "\$1" in/,$d' "$root/scripts/deploy.sh" > "$fixture/recipes-deploy/scripts/prepare.sh"
printf '\nprepare_build_files\n' >> "$fixture/recipes-deploy/scripts/prepare.sh"
bash "$fixture/recipes-deploy/scripts/prepare.sh"
cmp "$root/config/dockerignore" "$fixture/recipes-back/.dockerignore"
cmp "$root/config/dockerignore" "$fixture/recipes-front/.dockerignore"
cmp "$root/config/Dockerfile.backend" "$fixture/recipes-back/Dockerfile"
cmp "$root/config/Dockerfile.frontend" "$fixture/recipes-front/Dockerfile"
cmp "$root/config/nginx.conf" "$fixture/recipes-front/nginx.conf"
echo 'PASS: configuration des deux contextes de build'
