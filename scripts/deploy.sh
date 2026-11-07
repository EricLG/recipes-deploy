#!/bin/bash

# Script de gestion du déploiement - La Taverne de May
# NAS Ugreen DXP4800 Plus
# Usage: ./scripts/deploy.sh [commande]

set -e

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

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
        print_warning "Fichier .env manquant. Copie depuis .env.exemple..."
        if [ -f .env.exemple ]; then
            cp .env.exemple .env
            print_warning "Éditez le fichier .env avant de déployer"
            exit 1
        else
            print_error "Fichier .env.exemple introuvable"
            exit 1
        fi
    fi

    docker network inspect proxy-network > /dev/null
    docker compose config --quiet

    # Vérifier les variables critiques
    load_env
    local missing=0
    for var in MONGO_INITDB_ROOT_USERNAME MONGO_INITDB_ROOT_PASSWORD MONGO_INITDB_DATABASE JWT_SECRET; do
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
    if [ -f config/Dockerfile.backend ]; then
        cp -v config/Dockerfile.backend ../recipes-back/Dockerfile
        print_success "Dockerfile.backend → recipes-back/Dockerfile"
    else
        print_error "Dockerfile.backend introuvable"
        exit 1
    fi

    # Dockerfile frontend
    if [ -f config/Dockerfile.frontend ]; then
        cp -v config/Dockerfile.frontend ../recipes-front/Dockerfile
        print_success "Dockerfile.frontend → recipes-front/Dockerfile"
    else
        print_error "Dockerfile.frontend introuvable"
        exit 1
    fi

    # Configuration Nginx (HTTP simple — SSL géré par Nginx Proxy Manager)
    if [ -f config/nginx.conf ]; then
        cp -v config/nginx.conf ../recipes-front/nginx.conf
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
    check_requirements
    docker compose up -d --wait --wait-timeout 180
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
    docker compose build

    print_info "Mise a jour et verification de la sante des services..."
    docker compose up -d --wait --wait-timeout 180

    print_success "Déploiement terminé!"
    status

    echo ""
    print_info "Accès à l'application:"
    IP=$(hostname -I | awk '{print $1}')
    echo -e "  Site public  : ${GREEN}https://${SUBDOMAINS:-la-taverne-de-may}.duckdns.org${NC}"
    echo -e "  Réseau local : ${GREEN}http://127.0.0.1:8080 (depuis le NAS)${NC}"
    echo -e "  Proxy Manager: ${GREEN}http://${IP}:81${NC} (infra-stack ; acces selon pare-feu)"
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
# Nettoyage (DESTRUCTIF)
# ---------------------------------------------------------------------------
clean() {
    print_warning "⚠️  ATTENTION : Cette opération supprime les conteneurs ET VOLUMES recipes."
    print_warning "Toutes les données (MongoDB, uploads) seront PERDUES définitivement."
    print_info "Pensez à faire un backup d'abord : ./scripts/deploy.sh backup"
    echo ""
    read -p "Êtes-vous sûr de vouloir continuer? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Opération annulée"
        exit 0
    fi

    docker compose down -v

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
  ./scripts/deploy.sh [commande] [options]

${YELLOW}Commandes:${NC}
  ${BLUE}deploy${NC}         Déployer/redéployer l'application (build + up)
  ${BLUE}start${NC}          Démarrer les services
  ${BLUE}stop${NC}           Arrêter les services
  ${BLUE}restart${NC} [svc]  Redémarrer tous les services ou un service spécifique
  ${BLUE}status${NC}         Afficher le statut des conteneurs
  ${BLUE}logs${NC} [service] Afficher les logs (tous ou service spécifique)
  ${BLUE}backup${NC}         Créer un backup MongoDB + images
  ${BLUE}restore${NC} <file> Restaurer MongoDB et images (backup.sh)
  ${BLUE}clean${NC}          ⚠️  Nettoyer conteneurs et volumes recipes (données perdues)
  ${BLUE}help${NC}           Afficher cette aide

${YELLOW}Exemples:${NC}
  ./scripts/deploy.sh deploy               # Déployer l'application
  ./scripts/deploy.sh logs backend         # Logs du backend
  ./scripts/deploy.sh restart frontend     # Redémarrer le frontend
  ./scripts/deploy.sh backup               # Créer un backup
  ./scripts/deploy.sh restore ../backups/recipes_backup_*.tar.gz

${YELLOW}Services disponibles:${NC}
  - mongodb             (Base de données)
  - backend             (API NestJS)
  - frontend            (Application Angular)

${YELLOW}Accès:${NC}
  Site public   : https://la-taverne-de-may.duckdns.org
  Admin NPM     : http://<ip-nas>:81  (infra-stack)
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
    backup)   bash ./scripts/backup.sh create ;;
    restore)  bash ./scripts/backup.sh restore "${2:-}" ;;
    clean)    clean ;;
    help|--help|-h|"") help ;;
    *)
        print_error "Commande inconnue: $1"
        echo ""
        help
        exit 1
        ;;
esac
