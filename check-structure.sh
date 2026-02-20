#!/bin/bash

# Script de vérification de la structure du projet
# À exécuter depuis recipes-deploy

echo "🔍 Vérification de la structure du projet"
echo "=========================================="
echo ""

# Couleurs
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Vérifier le dossier actuel
CURRENT_DIR=$(basename "$PWD")
echo "📁 Dossier actuel: $PWD"

if [ "$CURRENT_DIR" != "recipes-deploy" ]; then
    echo -e "${RED}❌ Ce script doit être exécuté depuis recipes-deploy${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Dossier correct${NC}"
echo ""

# Vérifier la structure
echo "📂 Structure des dossiers:"
echo ""

if [ -d "../recipes-back" ]; then
    echo -e "${GREEN}  ✓ ../recipes-back${NC}"
else
    echo -e "${RED}  ✗ ../recipes-back (manquant)${NC}"
fi

if [ -d "../recipes-front" ]; then
    echo -e "${GREEN}  ✓ ../recipes-front${NC}"
else
    echo -e "${RED}  ✗ ../recipes-front (manquant)${NC}"
fi

echo ""
echo "📄 Fichiers dans recipes-deploy:"
echo ""

FILES=(
    "docker-compose.yml"
    "Dockerfile.backend"
    "Dockerfile.frontend"
    "nginx-ssl.conf"
    "deploy.sh"
    ".env"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}  ✓ $file${NC}"
    else
        echo -e "${RED}  ✗ $file (manquant)${NC}"
    fi
done

echo ""
echo "📄 Fichiers après copie (recipes-back):"
echo ""

if [ -f "../recipes-back/Dockerfile" ]; then
    echo -e "${GREEN}  ✓ recipes-back/Dockerfile${NC}"
else
    echo -e "${YELLOW}  ⊘ recipes-back/Dockerfile (sera copié au deploy)${NC}"
fi

echo ""
echo "📄 Fichiers après copie (recipes-front):"
echo ""

if [ -f "../recipes-front/Dockerfile" ]; then
    echo -e "${GREEN}  ✓ recipes-front/Dockerfile${NC}"
else
    echo -e "${YELLOW}  ⊘ recipes-front/Dockerfile (sera copié au deploy)${NC}"
fi

if [ -f "../recipes-front/nginx-ssl.conf" ]; then
    echo -e "${GREEN}  ✓ recipes-front/nginx-ssl.conf${NC}"
else
    echo -e "${YELLOW}  ⊘ recipes-front/nginx-ssl.conf (sera copié au deploy)${NC}"
fi

echo ""
echo "🔗 Chemins dans docker-compose.yml:"
echo ""

if [ -f "docker-compose.yml" ]; then
    echo "  Backend context:"
    grep -A 2 "backend:" docker-compose.yml | grep "context:" || echo "    (non trouvé)"
    
    echo ""
    echo "  Frontend context:"
    grep -A 2 "frontend:" docker-compose.yml | grep "context:" || echo "    (non trouvé)"
fi

echo ""
echo "=========================================="
echo ""

# Test de copie
echo "🧪 Test de copie des Dockerfiles:"
echo ""

read -p "Voulez-vous tester la copie des fichiers ? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Copie de Dockerfile.backend..."
    cp -v Dockerfile.backend ../recipes-back/Dockerfile
    
    echo ""
    echo "Copie de Dockerfile.frontend..."
    cp -v Dockerfile.frontend ../recipes-front/Dockerfile
    
    echo ""
    echo "Copie de nginx-ssl.conf..."
    cp -v nginx-ssl.conf ../recipes-front/nginx-ssl.conf
    
    echo ""
    echo -e "${GREEN}✅ Copie terminée${NC}"
    
    echo ""
    echo "Vérification:"
    ls -lh ../recipes-back/Dockerfile
    ls -lh ../recipes-front/Dockerfile
    ls -lh ../recipes-front/nginx-ssl.conf
fi

echo ""
echo "✅ Vérification terminée"
