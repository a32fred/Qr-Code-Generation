#!/bin/bash

# QR API - Deploy Script para Oracle VPS
# Uso: bash deploy.sh

set -e

echo "🚀 QR API - Setup Completo na Oracle VPS"
echo "========================================"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log colorido
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar se está rodando como root
if [[ $EUID -eq 0 ]]; then
   error "Este script não deve ser executado como root"
   exit 1
fi

# 1. Atualizar sistema
log "Atualizando sistema..."
sudo apt update && sudo apt upgrade -y

# 2. Instalar dependências
log "Instalando dependências..."
sudo apt install -y \
    curl \
    git \
    unzip \
    sqlite3 \
    nginx \
    certbot \
    python3-certbot-nginx \
    htop \
    iptables-persistent

# 3. Instalar Docker
if ! command -v docker &> /dev/null; then
    log "Instalando Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    
    # Instalar Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    log "Docker já está instalado"
fi

# 4. Configurar firewall
log "Configurando firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80
sudo ufw allow 443
sudo ufw --force enable

# 5. Otimizar sistema para baixa RAM
log "Otimizando sistema para baixo consumo de RAM..."

# Configurar swap (importante para 1GB RAM)
if [ ! -f /swapfile ]; then
    sudo fallocate -l 1G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# Configurar parâmetros de kernel
sudo tee -a /etc/sysctl.conf << EOF
# Otimizações para baixa RAM
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF

sudo sysctl -p

# 6. Criar estrutura do projeto
log "Criando estrutura do projeto..."
PROJECT_DIR="$HOME/qr-api"
mkdir -p $PROJECT_DIR/{ssl,data,backup}
cd $PROJECT_DIR

# 7. Configurar variáveis de ambiente
log "Configurando variáveis de ambiente..."
if [ ! -f .env ]; then
    cat > .env << EOF
# Stripe Configuration (você precisa adicionar suas chaves)
STRIPE_SECRET_KEY=sk_test_your_stripe_secret_key_here
STRIPE_WEBHOOK_SECRET=whsec_your_webhook_secret_here

# Domain Configuration
DOMAIN=your-domain.com

# Database
DATABASE_URL=sqlite:///app/data/qrapi.db

# Redis
REDIS_URL=redis://redis:6379/0
EOF
    warn "IMPORTANTE: Edite o arquivo .env com suas chaves do Stripe!"
    warn "Execute: nano $PROJECT_DIR/.env"
fi

# 8. Criar docker-compose otimizado
log "Criando docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  qr-api:
    build: .
    ports:
      - "8080:8080"
    environment:
      - STRIPE_SECRET_KEY=${STRIPE_SECRET_KEY}
      - STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET}
    volumes:
      - ./data:/app/data
    depends_on:
      - redis
    restart: unless-stopped
    mem_limit: 350m
    cpus: 0.8
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 80mb --maxmemory-policy allkeys-lru --save 60 1
    volumes:
      - redis_data:/data
    restart: unless-stopped
    mem_limit: 100m
    logging:
      driver: "json-file"
      options:
        max-size: "5m"
        max-file: "2"

volumes:
  redis_data:
EOF

# 9. Criar Dockerfile otimizado
log "Criando Dockerfile..."
cat > Dockerfile << 'EOF'
# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git gcc musl-dev sqlite-dev

# Copy go mod files first (for better caching)
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build with optimizations
RUN CGO_ENABLED=1 GOOS=linux go build \
    -ldflags="-w -s" \
    -a -installsuffix cgo \
    -o main .

# Final stage - minimal image
FROM alpine:latest

# Install runtime dependencies
RUN apk --no-cache add ca-certificates sqlite tzdata

# Create app user
RUN addgroup -g 1001 -S app && \
    adduser -S -D -H -u 1001 -h /app -s /sbin/nologin -G app -g app app

WORKDIR /app

# Copy binary
COPY --from=builder /app/main .
COPY --chown=app:app --from=builder /app/main .

# Create directories
RUN mkdir -p data && chown -R app:app /app

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

CMD ["./main"]
EOF

# 10. Criar arquivo principal do Go
if [ ! -f main.go ]; then
    log "Baixando código fonte..."
    # Aqui você colocaria o código Go que foi gerado anteriormente
    warn "Você precisa adicionar o arquivo main.go com o código da API"
    warn "Use o código gerado anteriormente"
fi

# 11. Criar arquivo go.mod
cat > go.mod << 'EOF'
module qr-api

go 1.21

require (
    github.com/gin-gonic/gin v1.9.1
    github.com/go-redis/redis/v8 v8.11.5
    github.com/mattn/go-sqlite3 v1.14.17
    github.com/skip2/go-qrcode v0.0.0-20200617195104-da1b6568686e
    github.com/stripe/stripe-go/v74 v74.30.0
    golang.org/x/time v0.3.0
)
EOF

# 12. Configurar nginx
log "Configurando nginx..."
sudo tee /etc/nginx/sites-available/qr-api << EOF
upstream qr_api {
    server 127.0.0.1:8080;
}

# Rate limiting
limit_req_zone \$binary_remote_addr zone=api:10m rate=30r/m;
limit_req_zone \$binary_remote_addr zone=register:1m rate=3r/m;

server {
    listen 80;
    server_name _;  # Aceita qualquer domínio
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # API routes with rate limiting
    location /api/register {
        limit_req zone=register burst=1 nodelay;
        proxy_pass http://qr_api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location /api/ {
        limit_req zone=api burst=10 nodelay;
        proxy_pass http://qr_api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    # All other routes
    location / {
        proxy_pass http://qr_api;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # Enable gzip
        gzip on;
        gzip_types text/plain application/json text/css application/javascript;
    }
    
    # Health check
    location /health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Ativar site
sudo ln -sf /etc/nginx/sites-available/qr-api /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

# 13. Criar scripts úteis
log "Criando scripts de gerenciamento..."

# Script de deploy
cat > deploy.sh << 'EOF'
#!/bin/bash
echo "🚀 Fazendo deploy da QR API..."
docker-compose down
docker-compose build --no-cache
docker-compose up -d
echo "✅ Deploy concluído!"
docker-compose logs -f
EOF

# Script de backup
cat > backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="./backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p $BACKUP_DIR
docker-compose exec qr-api cp -r /app/data $BACKUP_DIR/
echo "✅ Backup salvo em: $BACKUP_DIR"
EOF

# Script de monitoramento
cat > monitor.sh << 'EOF'
#!/bin/bash
echo "📊 Status da QR API"
echo "==================="
echo "🐳 Containers:"
docker-compose ps
echo ""
echo "💾 Uso de memória:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
echo ""
echo "📈 Sistema:"
free -h
echo ""
echo "🌐 Nginx status:"
sudo systemctl status nginx --no-pager -l
EOF

chmod +x *.sh

# 14. Criar arquivo index.html (landing page)
if [ ! -f index.html ]; then
    log "Criando landing page..."
    # Aqui você colocaria o HTML da landing page gerada anteriormente
    warn "Adicione o arquivo index.html com a landing page"
fi

# 15. Configurar monitoramento
log "Configurando monitoramento..."
cat > monitor_cron.sh << 'EOF'
#!/bin/bash
# Verifica se os containers estão rodando
if ! docker-compose ps | grep -q "Up"; then
    echo "⚠️ Container down, reiniciando..." | logger
    docker-compose up -d
fi

# Verifica uso de memória
MEM_USAGE=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')
if (( $(echo "$MEM_USAGE > 90" | bc -l) )); then
    echo "⚠️ Memória alta: $MEM_USAGE%" | logger
fi
EOF

chmod +x monitor_cron.sh

# Adicionar ao cron
(crontab -l 2>/dev/null; echo "*/5 * * * * $PROJECT_DIR/monitor_cron.sh") | crontab -

# 16. Configurar logrotate
sudo tee /etc/logrotate.d/qr-api << EOF
$PROJECT_DIR/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    copytruncate
}
EOF

log "✅ Setup completo!"
echo ""
echo "🎯 Próximos passos:"
echo "==================="
echo "1. Adicione o código Go (main.go) ao diretório $PROJECT_DIR"
echo "2. Configure suas chaves do Stripe no arquivo .env"
echo "3. Se você tem um domínio, configure-o no nginx"
echo "4. Execute: cd $PROJECT_DIR && ./deploy.sh"
echo ""
echo "📊 Comandos úteis:"
echo "- Monitorar: ./monitor.sh"
echo "- Backup: ./backup.sh"
echo "- Logs: docker-compose logs -f"
echo "- Restart: docker-compose restart"
echo ""
echo "🌐 Sua API estará disponível em:"
echo "- HTTP: http://seu-ip"
echo "- Docs: http://seu-ip/docs"
echo ""
echo "💡 Para SSL grátis com Let's Encrypt:"
echo "sudo certbot --nginx -d seu-dominio.com"

warn "Lembre-se de reiniciar o terminal ou fazer logout/login para usar o Docker sem sudo!"

# Mostrar informações do sistema
echo ""
log "📊 Informações do sistema:"
echo "RAM total: $(free -h | awk '/^Mem:/ {print $2}')"
echo "RAM disponível: $(free -h | awk '/^Mem:/ {print $7}')"
echo "Swap: $(free -h | awk '/^Swap:/ {print $2}')"
echo "CPU: $(nproc) cores"