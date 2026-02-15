# 🚀 Guide de Déploiement MEAN Stack sur Ugreen DXP4800 Plus

Guide complet pour déployer votre application MongoDB + NestJS + Angular sur votre NAS Ugreen en réseau local.

---

## 📋 Prérequis

✅ NAS Ugreen DXP4800 Plus avec:
- Docker et Docker Compose installés
- Accès SSH activé
- Au moins 2 GB de RAM disponible
- 5-10 GB d'espace disque libre

---

## 📁 Structure du Projet

Organisez votre projet comme suit sur votre NAS:

```
/volume1/docker/mon-app/
├── docker-compose.yml
├── .env
├── backend/
│   ├── Dockerfile
│   ├── src/
│   ├── package.json
│   └── tsconfig.json
└── frontend/
    ├── Dockerfile
    ├── nginx.conf
    ├── src/
    ├── angular.json
    └── package.json
```

---

## 🔧 Étape 1: Préparation du NAS

### 1.1 Connexion SSH à votre NAS

```bash
# Remplacez par l'IP de votre NAS
ssh admin@192.168.1.XXX
```

### 1.2 Créer le répertoire de travail

```bash
# Créer le dossier principal
mkdir -p /volume1/docker/mon-app
cd /volume1/docker/mon-app

# Créer les sous-dossiers
mkdir -p backend frontend
```

### 1.3 Vérifier que Docker fonctionne

```bash
docker --version
docker compose --version

# Vérifier l'état de Docker
docker ps
```

---

## 📦 Étape 2: Transfert des Fichiers

### Option A: Via SCP (depuis votre machine locale)

```bash
# Depuis votre ordinateur, transférer le backend
scp -r ./backend/* admin@192.168.1.XXX:/volume1/docker/mon-app/backend/

# Transférer le frontend
scp -r ./frontend/* admin@192.168.1.XXX:/volume1/docker/mon-app/frontend/

# Transférer les fichiers de configuration
scp docker-compose.yml admin@192.168.1.XXX:/volume1/docker/mon-app/
scp .env admin@192.168.1.XXX:/volume1/docker/mon-app/
```

### Option B: Via SFTP ou interface web Ugreen

Utilisez l'interface File Manager d'Ugreen pour uploader vos dossiers.

### Option C: Via Git (recommandé)

```bash
# Sur le NAS
cd /volume1/docker/mon-app
git clone https://github.com/votre-repo/votre-app.git .
```

---

## ⚙️ Étape 3: Configuration

### 3.1 Configurer les variables d'environnement

```bash
cd /volume1/docker/mon-app

# Copier le fichier exemple
cp .env.example .env

# Éditer avec votre éditeur préféré
nano .env
# ou
vi .env
```

**Points importants à modifier dans .env:**

1. **Trouvez l'IP de votre NAS:**
   ```bash
   ip addr show | grep "inet " | grep -v 127.0.0.1
   ```

2. **Modifiez les valeurs suivantes:**
   - `MONGO_INITDB_ROOT_PASSWORD`: Choisissez un mot de passe sécurisé
   - `JWT_SECRET`: Générez une clé secrète (minimum 32 caractères)
   - `CORS_ORIGIN`: Remplacez `192.168.1.XXX` par l'IP réelle de votre NAS
   - `API_URL`: Idem

**Exemple avec IP 192.168.1.50:**
```env
CORS_ORIGIN=http://192.168.1.50:4200
API_URL=http://192.168.1.50:3000
```

### 3.2 Placer les Dockerfiles

```bash
# Copier le Dockerfile du backend
cp Dockerfile.backend backend/Dockerfile

# Copier le Dockerfile du frontend
cp Dockerfile.frontend frontend/Dockerfile

# Copier la config Nginx
cp nginx.conf frontend/nginx.conf
```

---

## 🏗️ Étape 4: Adaptation du Code

### 4.1 Backend NestJS - Ajouter un endpoint de health check

Créez ou modifiez `backend/src/health/health.controller.ts`:

```typescript
import { Controller, Get } from '@nestjs/common';

@Controller('health')
export class HealthController {
  @Get()
  check() {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
    };
  }
}
```

### 4.2 Frontend Angular - Configuration de l'API

Modifiez `frontend/src/environments/environment.prod.ts`:

```typescript
export const environment = {
  production: true,
  apiUrl: 'http://192.168.1.XXX:3000', // Remplacez par l'IP de votre NAS
};
```

### 4.3 Vérifier angular.json

Dans `frontend/angular.json`, assurez-vous que le chemin de build est correct:

```json
{
  "projects": {
    "votre-app": {
      "architect": {
        "build": {
          "options": {
            "outputPath": "dist/browser"
          }
        }
      }
    }
  }
}
```

---

## 🚀 Étape 5: Déploiement

### 5.1 Build et lancement des conteneurs

```bash
cd /volume1/docker/mon-app

# Build et démarrer tous les services
docker compose up -d --build
```

### 5.2 Vérifier le statut des conteneurs

```bash
# Voir tous les conteneurs
docker compose ps

# Voir les logs en temps réel
docker compose logs -f

# Logs d'un service spécifique
docker compose logs -f backend
docker compose logs -f frontend
docker compose logs -f mongodb
```

### 5.3 Vérifier la santé des services

```bash
# Vérifier MongoDB
docker exec -it app-mongodb mongosh -u admin -p changeme_secure_password --authenticationDatabase admin

# Vérifier le backend
curl http://localhost:3000/health

# Vérifier le frontend
curl http://localhost:4200
```

---

## 🌐 Étape 6: Accès depuis le Réseau Local

### 6.1 Accéder à l'application

Depuis n'importe quel appareil de votre réseau local:

- **Frontend Angular:** `http://192.168.1.XXX:4200`
- **Backend API:** `http://192.168.1.XXX:3000`
- **API Docs (si Swagger):** `http://192.168.1.XXX:3000/api`

### 6.2 Tester depuis votre navigateur

Ouvrez votre navigateur et allez sur `http://IP_DE_VOTRE_NAS:4200`

---

## 🔒 Étape 7: Sécurité et Optimisations

### 7.1 Firewall du NAS

Si votre NAS a un firewall, ouvrez les ports:
- Port 4200 (Frontend)
- Port 3000 (Backend)

### 7.2 Configuration de redémarrage automatique

Les conteneurs sont déjà configurés avec `restart: unless-stopped`, ils redémarreront automatiquement au redémarrage du NAS.

### 7.3 Backups MongoDB

Créez un script de backup automatique:

```bash
# Créer un script de backup
nano /volume1/docker/mon-app/backup-mongo.sh
```

Contenu du script:

```bash
#!/bin/bash
BACKUP_DIR="/volume1/backups/mongodb"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

docker exec app-mongodb mongodump \
  --username admin \
  --password changeme_secure_password \
  --authenticationDatabase admin \
  --out /tmp/backup

docker cp app-mongodb:/tmp/backup $BACKUP_DIR/backup_$DATE

# Garder seulement les 7 derniers backups
ls -t $BACKUP_DIR/backup_* | tail -n +8 | xargs rm -rf

echo "Backup completed: $BACKUP_DIR/backup_$DATE"
```

Rendre exécutable et ajouter au cron:

```bash
chmod +x /volume1/docker/mon-app/backup-mongo.sh

# Ajouter au crontab (backup quotidien à 2h du matin)
crontab -e
# Ajouter: 0 2 * * * /volume1/docker/mon-app/backup-mongo.sh
```

---

## 🛠️ Commandes Utiles

### Gestion des conteneurs

```bash
# Arrêter tous les services
docker compose down

# Redémarrer tous les services
docker compose restart

# Reconstruire un service spécifique
docker compose up -d --build backend

# Voir les ressources utilisées
docker stats

# Nettoyer les images non utilisées
docker system prune -a
```

### Débogage

```bash
# Entrer dans un conteneur
docker exec -it app-backend sh
docker exec -it app-frontend sh

# Voir les logs détaillés
docker compose logs --tail=100 -f backend

# Inspecter un conteneur
docker inspect app-backend
```

### Mise à jour de l'application

```bash
# Pull les derniers changements (si Git)
git pull origin main

# Rebuild et redéployer
docker compose down
docker compose up -d --build

# Ou rebuild seulement le service modifié
docker compose up -d --build --no-deps backend
```

---

## 🐛 Troubleshooting

### Problème: Le backend ne peut pas se connecter à MongoDB

**Solution:**
```bash
# Vérifier que MongoDB est en bonne santé
docker compose ps mongodb

# Vérifier les logs MongoDB
docker compose logs mongodb

# Vérifier la connexion réseau
docker exec -it app-backend ping mongodb
```

### Problème: Le frontend ne peut pas appeler le backend

**Solution:**
1. Vérifier CORS dans le backend NestJS (`main.ts`):
   ```typescript
   app.enableCors({
     origin: process.env.CORS_ORIGIN || 'http://192.168.1.XXX:4200',
     credentials: true,
   });
   ```

2. Vérifier l'URL de l'API dans Angular
3. Vérifier les logs du navigateur (Console F12)

### Problème: "Cannot find module" lors du build

**Solution:**
```bash
# Supprimer node_modules et rebuild
docker compose down
rm -rf backend/node_modules frontend/node_modules
docker compose up -d --build
```

### Problème: Port déjà utilisé

**Solution:**
```bash
# Trouver quel processus utilise le port
netstat -tuln | grep :4200

# Changer le port dans docker-compose.yml
# Par exemple: "8080:80" au lieu de "4200:80"
```

---

## 📊 Monitoring

### Vérifier l'utilisation des ressources

```bash
# Voir l'utilisation CPU/RAM de chaque conteneur
docker stats --no-stream

# Voir l'espace disque utilisé
docker system df
```

### Logs centralisés

```bash
# Tous les logs dans un seul flux
docker compose logs -f --tail=50

# Filtrer par niveau de log
docker compose logs | grep ERROR
```

---

## 🎯 Prochaines Étapes (Optionnel)

### 1. Ajouter un reverse proxy (Traefik/Nginx)

Pour avoir un seul point d'entrée avec SSL.

### 2. Configurer un nom de domaine local

Utiliser votre router pour créer une entrée DNS locale (ex: `mon-app.local`)

### 3. Ajouter SSL/TLS

Générer des certificats auto-signés pour HTTPS en local.

### 4. Mettre en place un CI/CD

Automatiser le déploiement avec GitHub Actions ou GitLab CI.

---

## 📞 Besoin d'Aide?

Si vous rencontrez des problèmes:

1. Vérifiez les logs: `docker compose logs -f`
2. Vérifiez l'état des conteneurs: `docker compose ps`
3. Vérifiez la configuration réseau: `docker network inspect mon-app_app-network`
4. Consultez la documentation officielle de votre stack

---

## ✅ Checklist de Déploiement

- [ ] Docker et Docker Compose installés sur le NAS
- [ ] Projet transféré sur le NAS
- [ ] Fichier `.env` configuré avec la bonne IP
- [ ] Dockerfiles placés dans les bons dossiers
- [ ] `docker compose up -d --build` exécuté avec succès
- [ ] Tous les conteneurs sont "Up" (vérifier avec `docker compose ps`)
- [ ] Health checks passent (vérifier les logs)
- [ ] Frontend accessible sur `http://IP_NAS:4200`
- [ ] Backend accessible sur `http://IP_NAS:3000`
- [ ] Communication frontend ↔ backend fonctionne

---

**Bon déploiement! 🎉**

*N'hésitez pas à revenir vers moi si vous avez besoin d'ajustements ou si vous rencontrez des problèmes.*
