# 🚀 Déploiement Rapide - MEAN Stack sur NAS Ugreen

## Quick Start (5 minutes)

### 1️⃣ Préparer votre NAS

```bash
# Se connecter en SSH
ssh admin@IP_DE_VOTRE_NAS

# Créer le dossier projet
mkdir -p /volume1/docker/mon-app
cd /volume1/docker/mon-app
```

### 2️⃣ Transférer les fichiers

**Depuis votre ordinateur:**

```bash
# Copier tous les fichiers vers le NAS
scp -r * admin@IP_DE_VOTRE_NAS:/volume1/docker/mon-app/
```

### 3️⃣ Configurer

**Sur le NAS:**

```bash
cd /volume1/docker/mon-app

# Copier la configuration
cp .env.example .env

# Trouver l'IP du NAS
ip addr show | grep "inet "

# Éditer .env et remplacer 192.168.1.XXX par votre IP
nano .env
```

### 4️⃣ Placer les Dockerfiles

```bash
# Backend
cp Dockerfile.backend backend/Dockerfile

# Frontend
cp Dockerfile.frontend frontend/Dockerfile
cp nginx-ssl.conf frontend/nginx-ssl.conf
```

### 5️⃣ Déployer

```bash
# Rendre le script exécutable
chmod +x deploy.sh

# Lancer le déploiement
./deploy.sh deploy
```

### ✅ Vérifier

Ouvrez votre navigateur:
- Frontend: `http://IP_DE_VOTRE_NAS:4200`
- Backend: `http://IP_DE_VOTRE_NAS:3000/health`

---

## 📚 Fichiers Fournis

- `docker-compose.yml` - Orchestration des services
- `Dockerfile.backend` - Image Docker pour NestJS
- `Dockerfile.frontend` - Image Docker pour Angular
- `nginx-ssl.conf` - Configuration serveur web
- `.env.example` - Template de configuration
- `deploy.sh` - Script de gestion
- `GUIDE_DEPLOIEMENT.md` - Guide complet détaillé

---

## 🛠️ Commandes Utiles

```bash
./deploy.sh status      # Voir l'état des services
./deploy.sh logs        # Voir tous les logs
./deploy.sh logs backend # Logs du backend uniquement
./deploy.sh restart     # Redémarrer tous les services
./deploy.sh backup      # Backup MongoDB
./deploy.sh stop        # Arrêter l'application
./deploy.sh help        # Aide complète
```

---

## 🆘 Problèmes Courants

**Les conteneurs ne démarrent pas?**
```bash
docker compose logs -f
```

**Port déjà utilisé?**
Modifiez les ports dans `docker-compose.yml`:
```yaml
ports:
  - "8080:80"  # Au lieu de 4200:80
```

**Erreur de connexion MongoDB?**
Vérifiez le mot de passe dans `.env` et `docker-compose.yml`

---

## 📖 Documentation Complète

Pour plus de détails, consultez `GUIDE_DEPLOIEMENT.md`

**Bonne mise en production! 🎉**
