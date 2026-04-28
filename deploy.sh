#!/bin/bash

# Script de gestion du déploiement - La Taverne de May
# NAS Ugreen DXP4800 Plus
# Usage: ./deploy.sh [commande]

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}ℹ ${NC}$1"; }
print_success() { echo -e "${GREEN}✓ ${NC}$1"; }
print_warning() { echo -e "${YELLOW}⚠ ${NC}$1"; }
print_error()   { echo -e "${RED}✗ ${NC}$1"; }

# ---------------------------------------------------------------------------
# Chargement sécurisé du .env (gère les espaces, guillemets, commentaires)
# ---------------------------------------------------------------------------
load_env() {
    if [ ! -f .env ]; then
        print_error "Fichier .env introuvable"
        exit 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        # Ignorer les lignes vides et les commentaires
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        # Exporter uniquement les lignes KEY=VALUE
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
            export "${line?}"
        fi
    done < .env
}

# ---------------------------------------------------------------------------
# Vérification des prérequis
# ---------------------------------------------------------------------------
check_requirements() {
    print_info "Vérification des prérequis..."

    if ! command -v docker &> /dev/null; then
        print_error "Docker n'est pas installé"
        exit 1
    fi

    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose v2 introuvable"
        exit 1
    fi

    if [ ! -f .env ]; then
        print_warning "Fichier .env manquant. Copie depuis .env.example..."
        if [ -f .env.example ]; then
            cp .env.example .env
            print_warning "Éditez le fichier .env avant de déployer"
            exit 1
        else
            print_error "Fichier .env.example introuvable"
            exit 1
        fi
    fi

    # Vérifier les variables critiques
    load_env
    local missing=0
    for var in MONGO_INITDB_ROOT_USERNAME MONGO_INITDB_ROOT_PASSWORD MONGO_INITDB_DATABASE JWT_SECRET DUCKDNS_TOKEN; do
        if [ -z "${!var}" ]; then
            print_error "Variable manquante dans .env : $var"
            missing=1
        fi
    done
    [ $missing -eq 1 ] && exit 1

    print_success "Tous les prérequis sont satisfaits"
}

# ---------------------------------------------------------------------------
# Préparation des fichiers de build
# ---------------------------------------------------------------------------
prepare_build_files() {
    print_info "Préparation des fichiers de build..."

    CURRENT_DIR=$(basename "$PWD")
    if [ "$CURRENT_DIR" != "recipes-deploy" ]; then
        print_error "Ce script doit être exécuté depuis le dossier recipes-deploy"
        print_info "Dossier actuel: $PWD"
        exit 1
    fi

    # Dockerfile backend
    if [ -f Dockerfile.backend ]; then
        cp -v Dockerfile.backend ../recipes-back/Dockerfile
        print_success "Dockerfile.backend → recipes-back/Dockerfile"
    else
        print_error "Dockerfile.backend introuvable"
        exit 1
    fi

    # Dockerfile frontend
    if [ -f Dockerfile.frontend ]; then
        cp -v Dockerfile.frontend ../recipes-front/Dockerfile
        print_success "Dockerfile.frontend → recipes-front/Dockerfile"
    else
        print_error "Dockerfile.frontend introuvable"
        exit 1
    fi

    # Configuration Nginx (HTTP simple — SSL géré par Nginx Proxy Manager)
    if [ -f nginx.conf ]; then
        cp -v nginx.conf ../recipes-front/nginx.conf
        print_success "nginx.conf → recipes-front/nginx.conf"
    else
        print_error "nginx.conf introuvable (le fichier nginx-ssl.conf n'est plus utilisé)"
        exit 1
    fi

    # Vérifications finales
    local ok=1
    [ -f ../recipes-back/Dockerfile ]    || { print_error "recipes-back/Dockerfile manquant";    ok=0; }
    [ -f ../recipes-front/Dockerfile ]   || { print_error "recipes-front/Dockerfile manquant";   ok=0; }
    [ -f ../recipes-front/nginx.conf ]   || { print_error "recipes-front/nginx.conf manquant";   ok=0; }
    [ $ok -eq 0 ] && exit 1

    print_success "Fichiers de build préparés"
}

# ---------------------------------------------------------------------------
# Statut
# ---------------------------------------------------------------------------
status() {
    print_info "Statut des conteneurs:"
    docker compose ps
    echo ""
    print_info "Utilisation des ressources:"
    docker stats --no-stream
}

# ---------------------------------------------------------------------------
# Démarrer
# ---------------------------------------------------------------------------
start() {
    print_info "Démarrage des services..."
    docker compose up -d
    print_success "Services démarrés"
    sleep 3
    status
}

# ---------------------------------------------------------------------------
# Arrêter
# ---------------------------------------------------------------------------
stop() {
    print_info "Arrêt des services..."
    docker compose down
    print_success "Services arrêtés"
}

# ---------------------------------------------------------------------------
# Déploiement complet
# ---------------------------------------------------------------------------
deploy() {
    print_info "Déploiement de l'application..."
    check_requirements
    prepare_build_files

    print_info "Build des images Docker..."
    docker compose build --no-cache

    print_info "Arrêt des anciens conteneurs..."
    docker compose down

    print_info "Démarrage des nouveaux conteneurs..."
    docker compose up -d

    print_info "Attente du démarrage des services (15s)..."
    sleep 15

    print_success "Déploiement terminé!"
    status

    echo ""
    print_info "Accès à l'application:"
    IP=$(hostname -I | awk '{print $1}')
    echo -e "  Site public  : ${GREEN}https://${SUBDOMAINS:-la-taverne-de-may}.duckdns.org${NC}"
    echo -e "  Réseau local : ${GREEN}http://${IP}:8080${NC}"
    echo -e "  Proxy Manager: ${GREEN}http://${IP}:81${NC} (admin NPM — local uniquement)"
    echo -e "  Backend      : ${GREEN}(accessible via /api uniquement)${NC}"
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
logs() {
    if [ -z "$1" ]; then
        docker compose logs -f --tail=100
    else
        docker compose logs -f --tail=100 "$1"
    fi
}

# ---------------------------------------------------------------------------
# Redémarrer
# ---------------------------------------------------------------------------
restart() {
    if [ -z "$1" ]; then
        print_info "Redémarrage de tous les services..."
        docker compose restart
    else
        print_info "Redémarrage du service $1..."
        docker compose restart "$1"
    fi
    print_success "Redémarrage terminé"
}

# ---------------------------------------------------------------------------
# Backup MongoDB
# ---------------------------------------------------------------------------
backup() {
    print_info "Création d'un backup MongoDB..."
    load_env

    BACKUP_DIR="./backups"
    mkdir -p "$BACKUP_DIR"

    DATE=$(date +%Y%m%d_%H%M%S)
    BACKUP_NAME="mongodb_backup_$DATE"

    print_info "Dump de la base '${MONGO_INITDB_DATABASE}' en cours..."

    docker exec app-mongodb mongodump \
        --username "${MONGO_INITDB_ROOT_USERNAME}" \
        --password "${MONGO_INITDB_ROOT_PASSWORD}" \
        --authenticationDatabase admin \
        --db="${MONGO_INITDB_DATABASE}" \
        --out "/tmp/${BACKUP_NAME}"

    docker cp "app-mongodb:/tmp/${BACKUP_NAME}" "${BACKUP_DIR}/"

    # Nettoyage dans le conteneur
    docker exec app-mongodb rm -rf "/tmp/${BACKUP_NAME}"

    # Compression locale
    tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -C "${BACKUP_DIR}" "${BACKUP_NAME}"
    rm -rf "${BACKUP_DIR:?}/${BACKUP_NAME}"

    print_success "Backup créé : ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

    # Garder uniquement les 7 derniers backups
    local count
    count=$(ls "${BACKUP_DIR}"/mongodb_backup_*.tar.gz 2>/dev/null | wc -l)
    if [ "$count" -gt 7 ]; then
        ls -t "${BACKUP_DIR}"/mongodb_backup_*.tar.gz | tail -n +8 | xargs -r rm -f
        print_info "Anciens backups nettoyés (conservation des 7 derniers)"
    fi
}

# ---------------------------------------------------------------------------
# Restauration MongoDB
# ---------------------------------------------------------------------------
restore() {
    if [ -z "$1" ]; then
        print_error "Usage: ./deploy.sh restore <fichier_backup.tar.gz>"
        exit 1
    fi

    if [ ! -f "$1" ]; then
        print_error "Fichier $1 introuvable"
        exit 1
    fi

    load_env

    print_warning "ATTENTION: Cette opération va écraser la base de données actuelle !"
    read -p "Voulez-vous continuer? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Opération annulée"
        exit 0
    fi

    print_info "Restauration de $1..."

    TEMP_DIR=$(mktemp -d)
    tar -xzf "$1" -C "$TEMP_DIR"

    BACKUP_NAME=$(basename "$1" .tar.gz)
    docker cp "${TEMP_DIR}/${BACKUP_NAME}" "app-mongodb:/tmp/"

    docker exec app-mongodb mongorestore \
        --username "${MONGO_INITDB_ROOT_USERNAME}" \
        --password "${MONGO_INITDB_ROOT_PASSWORD}" \
        --authenticationDatabase admin \
        --drop \
        "/tmp/${BACKUP_NAME}"

    # Nettoyage
    docker exec app-mongodb rm -rf "/tmp/${BACKUP_NAME}"
    rm -rf "$TEMP_DIR"

    print_success "Restauration terminée"
}

# ---------------------------------------------------------------------------
# Nettoyage (DESTRUCTIF)
# ---------------------------------------------------------------------------
clean() {
    print_warning "⚠️  ATTENTION : Cette opération supprime les conteneurs, images ET VOLUMES."
    print_warning "Toutes les données (MongoDB, uploads) seront PERDUES définitivement."
    print_info "Pensez à faire un backup d'abord : ./deploy.sh backup"
    echo ""
    read -p "Êtes-vous sûr de vouloir continuer? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Opération annulée"
        exit 0
    fi

    docker compose down -v
    docker system prune -a -f

    print_success "Nettoyage terminé"
}

# ---------------------------------------------------------------------------
# Aide
# ---------------------------------------------------------------------------
help() {
    cat << EOF
${GREEN}Script de déploiement — La Taverne de May${NC}
NAS Ugreen DXP4800 Plus

${YELLOW}Usage:${NC}
  ./deploy.sh [commande] [options]

${YELLOW}Commandes:${NC}
  ${BLUE}deploy${NC}         Déployer/redéployer l'application (build + up)
  ${BLUE}start${NC}          Démarrer les services
  ${BLUE}stop${NC}           Arrêter les services
  ${BLUE}restart${NC} [svc]  Redémarrer tous les services ou un service spécifique
  ${BLUE}status${NC}         Afficher le statut des conteneurs
  ${BLUE}logs${NC} [service] Afficher les logs (tous ou service spécifique)
  ${BLUE}backup${NC}         Créer un backup MongoDB
  ${BLUE}restore${NC} <file> Restaurer MongoDB depuis un backup
  ${BLUE}clean${NC}          ⚠️  Nettoyer conteneurs, images ET volumes (données perdues)
  ${BLUE}help${NC}           Afficher cette aide

${YELLOW}Exemples:${NC}
  ./deploy.sh deploy               # Déployer l'application
  ./deploy.sh logs backend         # Logs du backend
  ./deploy.sh restart frontend     # Redémarrer le frontend
  ./deploy.sh backup               # Créer un backup
  ./deploy.sh restore backups/mongodb_backup_20240215_120000.tar.gz

${YELLOW}Services disponibles:${NC}
  - duckdns             (Mise à jour IP dynamique)
  - nginx-proxy-manager (Reverse proxy + SSL Let's Encrypt)
  - mongodb             (Base de données)
  - backend             (API NestJS)
  - frontend            (Application Angular)

${YELLOW}Accès:${NC}
  Site public   : https://la-taverne-de-may.duckdns.org
  Admin NPM     : http://<ip-nas>:81  (réseau local uniquement)
EOF
}

# ---------------------------------------------------------------------------
# Point d'entrée
# ---------------------------------------------------------------------------
case "$1" in
    deploy)   deploy ;;
    start)    start ;;
    stop)     stop ;;
    restart)  restart "$2" ;;
    status)   status ;;
    logs)     logs "$2" ;;
    backup)   backup ;;
    restore)  restore "$2" ;;
    clean)    clean ;;
    help|--help|-h|"") help ;;
    *)
        print_error "Commande inconnue: $1"
        echo ""
        help
        exit 1
        ;;
esac
