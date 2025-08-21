# QR Code API - Makefile para desenvolvimento local
.PHONY: help build up down restart logs clean test health backup dev-deps

# Variáveis
COMPOSE=docker compose
SERVICE_API=qr-api
SERVICE_REDIS=redis

# Help
help: ## Mostra este help
	@echo "QR Code API - Comandos disponíveis:"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Desenvolvimento
build: ## Build das imagens Docker
	$(COMPOSE) build

up: ## Sobe todos os serviços
	$(COMPOSE) up -d
	@echo "✅ Serviços iniciados!"
	@echo "🌐 API: http://localhost:8080"
	@echo "🔴 Redis: localhost:6379"

down: ## Para todos os serviços
	$(COMPOSE) down

restart: ## Reinicia todos os serviços
	$(COMPOSE) restart

restart-api: ## Reinicia apenas a API
	$(COMPOSE) restart $(SERVICE_API)

restart-redis: ## Reinicia apenas o Redis
	$(COMPOSE) restart $(SERVICE_REDIS)

# Logs
logs: ## Mostra logs de todos os serviços
	$(COMPOSE) logs -f

logs-api: ## Mostra logs apenas da API
	$(COMPOSE) logs -f $(SERVICE_API)

logs-redis: ## Mostra logs apenas do Redis
	$(COMPOSE) logs -f $(SERVICE_REDIS)

# Desenvolvimento e debug
dev: ## Modo desenvolvimento com rebuild automático
	$(COMPOSE) up --build

shell: ## Acessa shell do container da API
	$(COMPOSE) exec $(SERVICE_API) /bin/sh

shell-redis: ## Acessa CLI do Redis
	$(COMPOSE) exec $(SERVICE_REDIS) redis-cli

# Limpeza
clean: ## Remove containers, volumes e imagens
	$(COMPOSE) down -v --rmi all
	docker system prune -f

clean-data: ## Remove apenas os dados (cuidado!)
	$(COMPOSE) down -v
	sudo rm -rf ./data/*
	@echo "⚠️ Dados removidos!"

# Status e monitoramento
status: ## Mostra status dos serviços
	$(COMPOSE) ps

health: ## Verifica health dos serviços
	@echo "🔍 Verificando health dos serviços..."
	@curl -f http://localhost:8080/ > /dev/null 2>&1 && echo "✅ API OK" || echo "❌ API com problema"
	@$(COMPOSE) exec $(SERVICE_REDIS) redis-cli ping > /dev/null 2>&1 && echo "✅ Redis OK" || echo "❌ Redis com problema"

stats: ## Mostra estatísticas dos containers
	docker stats --no-stream

# Backup e restore
backup: ## Faz backup do banco de dados
	@mkdir -p ./backups
	@BACKUP_FILE="./backups/qrapi_backup_$$(date +%Y%m%d_%H%M%S).db" && \
	$(COMPOSE) exec $(SERVICE_API) cp /app/data/qrapi.db /tmp/backup.db && \
	docker cp qr-api-app:/tmp/backup.db $$BACKUP_FILE && \
	echo "✅ Backup salvo em: $$BACKUP_FILE"

# Testes
test-api: ## Testa se a API está respondendo
	@echo "🧪 Testando API..."
	@curl -s http://localhost:8080/ | jq . || echo "❌ API não está respondendo"

test-register: ## Testa criação de usuário
	@echo "🧪 Testando registro de usuário..."
	@curl -s -X POST http://localhost:8080/api/register | jq . || echo "❌ Registro não funcionou"

test-redis: ## Testa conexão com Redis
	@echo "🧪 Testando Redis..."
	@$(COMPOSE) exec $(SERVICE_REDIS) redis-cli ping

# Utilitários
deps-check: ## Verifica dependências necessárias
	@echo "🔍 Verificando dependências..."
	@command -v docker > /dev/null || (echo "❌ Docker não encontrado" && exit 1)
	@command -v docker-compose > /dev/null || command -v docker > /dev/null || (echo "❌ Docker Compose não encontrado" && exit 1)
	@command -v curl > /dev/null || echo "⚠️ curl não encontrado (recomendado para testes)"
	@command -v jq > /dev/null || echo "⚠️ jq não encontrado (recomendado para testes)"
	@echo "✅ Dependências verificadas!"

setup: deps-check ## Setup inicial do projeto
	@echo "🚀 Configurando projeto..."
	@mkdir -p data logs backups nginx/logs
	@touch data/.gitkeep logs/.gitkeep
	@echo "✅ Diretórios criados!"
	@echo "📝 Configure suas chaves do Stripe no arquivo .env"
	@echo "🏃 Execute 'make up' para iniciar os serviços"

# Desenvolvimento avançado
watch: ## Monitora mudanças e rebuilda automaticamente (requer inotify-tools)
	@echo "👀 Monitorando mudanças no código..."
	@while inotifywait -e modify *.go; do \
		echo "🔄 Arquivo modificado, fazendo rebuild..."; \
		make restart-api; \
		echo "✅ Rebuild concluído!"; \
	done

# Nginx (opcional)
nginx-up: ## Sobe nginx para ambiente de produção local
	$(COMPOSE) --profile production up nginx -d

nginx-down: ## Para nginx
	$(COMPOSE) stop nginx

nginx-logs: ## Mostra logs do nginx
	$(COMPOSE) logs -f nginx

# Informações
info: ## Mostra informações do ambiente
	@echo "📋 QR Code API - Informações do Ambiente"
	@echo "========================================"
	@echo "🐳 Docker version: $$(docker --version)"
	@echo "🐙 Docker Compose version: $$(docker compose version)"
	@echo "📂 Diretório atual: $$(pwd)"
	@echo "🔧 Arquivos de configuração:"
	@ls -la | grep -E "\.(yml|yaml|env|conf)$$" || echo "  Nenhum encontrado"
	@echo ""
	@echo "🌐 URLs disponíveis:"
	@echo "  API: http://localhost:8080"
	@echo "  Health: http://localhost:8080/"
	@echo "  Docs: http://localhost:8080/docs"
	@echo ""

# Quick start
quick-start: setup up health ## Setup rápido e inicialização
	@echo ""
	@echo "🎉 QR Code API está rodando!"
	@echo "🌐 Acesse: http://localhost:8080"
	@echo ""
	@echo "📝 Próximos passos:"
	@echo "  1. Configure suas chaves do Stripe no .env"
	@echo "  2. Teste a API: make test-api"
	@echo "  3. Monitore logs: make logs"