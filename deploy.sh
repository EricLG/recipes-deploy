#!/bin/bash

# Script de gestion du déploiement MEAN Stack sur NAS Ugreen
# Usage: ./deploy.sh [commande]

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonction d'affichage
print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓ ${NC}$1"
}

print_warning() {
    echo -e "${YELLOW}⚠ ${NC}$1"
}

print_error() {
    echo -e "${RED}✗ ${NC}$1"
}

# Fonction pour vérifier les prérequis
check_requirements() {
    print_info "Vérification des prérequis..."

    if ! command -v docker &> /dev/null; then
        print_error "Docker n'est pas installé"
        exit 1
    fi

    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose n'est pas installé ou n'est pas la v2"
        print_info "Essayez: docker compose version"
        exit 1
    fi

    if [ ! -f .env ]; then
        print_warning "Fichier .env manquant. Copie depuis .env.example..."
        if [ -f .env.example ]; then
            cp .env.example .env
            print_warning "Veuillez éditer le fichier .env avant de déployer"
            exit 1
        else
            print_error "Fichier .env.example introuvable"
            exit 1
        fi
    fi

    print_success "Tous les prérequis sont satisfaits"
}

# Fonction pour préparer les fichiers de build
prepare_build_files() {
    print_info "Préparation des fichiers de build..."

    # Copier le Dockerfile du backend
    if [ -f Dockerfile.backend ]; then
        cp Dockerfile.backend ../recipes-back/Dockerfile
        print_success "Dockerfile.backend copié dans recipes-back/"
    else
        print_error "Dockerfile.backend introuvable"
        exit 1
    fi

    # Copier le Dockerfile du frontend
    if [ -f Dockerfile.frontend ]; then
        cp Dockerfile.frontend ../recipes-front/Dockerfile
        print_success "Dockerfile.frontend copié dans recipes-front/"
    else
        print_error "Dockerfile.frontend introuvable"
        exit 1
    fi

    # Copier la configuration Nginx
    if [ -f nginx-ssl.conf ]; then
        cp nginx-ssl.conf ../recipes-front/nginx-ssl.conf
        print_success "nginx-ssl.conf copié dans recipes-front/"
    else
        print_error "nginx-ssl.conf introuvable"
        exit 1
    fi

    print_success "Fichiers de build préparés"
}

# Fonction pour afficher le statut
status() {
    print_info "Statut des conteneurs:"
    docker compose ps
    echo ""
    print_info "Utilisation des ressources:"
    docker stats --no-stream
}

# Fonction pour démarrer les services
start() {
    print_info "Démarrage des services..."
    docker compose up -d
    print_success "Services démarrés"
    sleep 3
    status
}

# Fonction pour arrêter les services
stop() {
    print_info "Arrêt des services..."
    docker compose down
    print_success "Services arrêtés"
}

# Fonction pour rebuilder et déployer
deploy() {
    print_info "Déploiement de l'application..."
    check_requirements

    # Préparer les fichiers de build
    prepare_build_files

    print_info "Build des images Docker..."
    docker compose build --no-cache

    print_info "Arrêt des anciens conteneurs..."
    docker compose down

    print_info "Démarrage des nouveaux conteneurs..."
    docker compose up -d

    print_info "Attente du démarrage des services..."
    sleep 10

    print_success "Déploiement terminé!"
    status

    echo ""
    print_info "Accès à l'application:"
    IP=$(hostname -I | awk '{print $1}')
    echo -e "  Frontend: ${GREEN}https://${IP}:8443${NC}"
    echo -e "  Backend:  ${GREEN}(accessible via /api uniquement)${NC}"
}

# Fonction pour voir les logs
logs() {
    if [ -z "$1" ]; then
        docker compose logs -f --tail=100
    else
        docker compose logs -f --tail=100 "$1"
    fi
}

# Fonction pour redémarrer un service
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

# Fonction pour backup MongoDB
backup() {
    print_info "Création d'un backup MongoDB..."

    # Charger les variables depuis .env
    if [ ! -f .env ]; then
        print_error "Fichier .env introuvable"
        exit 1
    fi

    source .env

    BACKUP_DIR="./backups"
    mkdir -p "$BACKUP_DIR"

    DATE=$(date +%Y%m%d_%H%M%S)
    BACKUP_NAME="mongodb_backup_$DATE"

    print_info "Connexion avec l'utilisateur: ${MONGO_INITDB_ROOT_USERNAME}"

    docker exec app-mongodb mongodump \
        --username "${MONGO_INITDB_ROOT_USERNAME}" \
        --password "${MONGO_INITDB_ROOT_PASSWORD}" \
        --authenticationDatabase admin \
        --out "/tmp/$BACKUP_NAME"

    if [ $? -ne 0 ]; then
        print_error "Échec du dump MongoDB"
        exit 1
    fi

    docker cp "app-mongodb:/tmp/$BACKUP_NAME" "$BACKUP_DIR/"

    # Compression
    tar -czf "$BACKUP_DIR/$BACKUP_NAME.tar.gz" -C "$BACKUP_DIR" "$BACKUP_NAME"
    rm -rf "$BACKUP_DIR/$BACKUP_NAME"

    print_success "Backup créé: $BACKUP_DIR/$BACKUP_NAME.tar.gz"

    # Nettoyage des anciens backups (garder les 7 derniers)
    ls -t "$BACKUP_DIR"/mongodb_backup_*.tar.gz | tail -n +8 | xargs -r rm -f
}

# Fonction pour restaurer MongoDB
restore() {
    if [ -z "$1" ]; then
        print_error "Usage: ./deploy.sh restore <fichier_backup.tar.gz>"
        exit 1
    fi

    if [ ! -f "$1" ]; then
        print_error "Fichier $1 introuvable"
        exit 1
    fi

    # Charger les variables depuis .env
    if [ ! -f .env ]; then
        print_error "Fichier .env introuvable"
        exit 1
    fi

    source .env

    print_warning "ATTENTION: Cette opération va écraser la base de données actuelle"
    read -p "Voulez-vous continuer? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Opération annulée"
        exit 0
    fi

    print_info "Restauration de $1..."

    # Extraction
    TEMP_DIR=$(mktemp -d)
    tar -xzf "$1" -C "$TEMP_DIR"

    # Copie dans le conteneur
    BACKUP_NAME=$(basename "$1" .tar.gz)
    docker cp "$TEMP_DIR/$BACKUP_NAME" "app-mongodb:/tmp/"

    # Restauration
    print_info "Connexion avec l'utilisateur: ${MONGO_INITDB_ROOT_USERNAME}"

    docker exec app-mongodb mongorestore \
        --username "${MONGO_INITDB_ROOT_USERNAME}" \
        --password "${MONGO_INITDB_ROOT_PASSWORD}" \
        --authenticationDatabase admin \
        --drop \
        "/tmp/$BACKUP_NAME"

    if [ $? -ne 0 ]; then
        print_error "Échec de la restauration"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Nettoyage
    rm -rf "$TEMP_DIR"

    print_success "Restauration terminée"
}

# Fonction pour nettoyer
clean() {
    print_warning "Nettoyage des conteneurs, images et volumes inutilisés..."

    read -p "Cette opération va supprimer les données non utilisées. Continuer? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Opération annulée"
        exit 0
    fi

    docker compose down -v
    docker system prune -a -f

    print_success "Nettoyage terminé"
}

# Fonction pour afficher l'aide
help() {
    cat << EOF
${GREEN}Script de gestion du déploiement MEAN Stack${NC}

${YELLOW}Usage:${NC}
  ./deploy.sh [commande] [options]

${YELLOW}Commandes disponibles:${NC}
  ${BLUE}deploy${NC}         Déployer/redéployer l'application (build + up)
  ${BLUE}start${NC}          Démarrer les services
  ${BLUE}stop${NC}           Arrêter les services
  ${BLUE}restart${NC} [svc]  Redémarrer tous les services ou un service spécifique
  ${BLUE}status${NC}         Afficher le statut des conteneurs
  ${BLUE}logs${NC} [service] Afficher les logs (all ou service spécifique)
  ${BLUE}backup${NC}         Créer un backup de MongoDB
  ${BLUE}restore${NC} <file> Restaurer MongoDB depuis un backup
  ${BLUE}clean${NC}          Nettoyer les conteneurs et images inutilisés
  ${BLUE}help${NC}           Afficher cette aide

${YELLOW}Exemples:${NC}
  ./deploy.sh deploy           # Déployer l'application
  ./deploy.sh logs backend     # Voir les logs du backend
  ./deploy.sh restart frontend # Redémarrer le frontend
  ./deploy.sh backup           # Créer un backup
  ./deploy.sh restore backups/mongodb_backup_20240215_120000.tar.gz

${YELLOW}Services disponibles:${NC}
  - mongodb   (Base de données)
  - backend   (API NestJS)
  - frontend  (Application Angular)
EOF
}

# Menu principal
case "$1" in
    deploy)
        deploy
        ;;
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart "$2"
        ;;
    status)
        status
        ;;
    logs)
        logs "$2"
        ;;
    backup)
        backup
        ;;
    restore)
        restore "$2"
        ;;
    clean)
        clean
        ;;
    help|--help|-h|"")
        help
        ;;
    *)
        print_error "Commande inconnue: $1"
        echo ""
        help
        exit 1
        ;;
esac
