# QR Code API

Uma API REST completa para geração de QR codes com funcionalidades premium como cores customizadas, logos e analytics. Construída em Go com integração Stripe para planos de assinatura.

## 🚀 Quick Start

### Pré-requisitos
- Docker e Docker Compose instalados
- Make (opcional, mas recomendado)

### Iniciando o projeto

1. **Clone e configure**:
```bash
cd QR-code_generator
cp .env.example .env  # Edite suas chaves do Stripe
```

2. **Inicie os serviços**:
```bash
# Com Make (recomendado)
make quick-start

# Ou com Docker Compose diretamente
docker compose up -d
```

3. **Verifique se está funcionando**:
```bash
# Teste a API
curl http://localhost:8080/

# Ou use o Make
make health
```

**🎉 Pronto! A API estará rodando em http://localhost:8080**

## 📋 Comandos Disponíveis

### Desenvolvimento básico
```bash
make up          # Inicia todos os serviços
make down        # Para todos os serviços  
make restart     # Reinicia todos os serviços
make logs        # Mostra logs em tempo real
make status      # Status dos containers
```

### Desenvolvimento avançado
```bash
make dev         # Modo desenvolvimento com rebuild
make shell       # Acessa container da API
make shell-redis # Acessa CLI do Redis
make clean       # Remove containers e volumes
```

### Testes e monitoramento
```bash
make test-api      # Testa se API responde
make test-register # Testa criação de usuário
make health        # Health check completo
make stats         # Estatísticas dos containers
```

### Backup e utilitários
```bash
make backup        # Backup do banco de dados
make info          # Informações do ambiente
make help          # Lista todos os comandos
```

## 🦀 Arquitetura

### Serviços
- **qr-api**: API principal em Rust (porta 8080)
- **redis**: Cache e rate limiting (porta 6379)  
- **nginx**: Reverse proxy opcional (porta 80/443)

### Estrutura de arquivos
```
QR-code_generator/
├── src/                  # Código fonte Rust
│   ├── main.rs          # Entrada principal
│   ├── handlers.rs      # Handlers HTTP
│   ├── models.rs        # Estruturas de dados
│   ├── database.rs      # Camada SQLite
│   ├── qr_service.rs    # Geração de QR codes
│   ├── redis_client.rs  # Cliente Redis
│   └── auth.rs          # Autenticação
├── Cargo.toml           # Dependências Rust
├── landing_page.html    # Página inicial
├── docker-compose.yml   # Configuração dos serviços
├── Dockerfile           # Imagem da aplicação
├── .env                 # Variáveis de ambiente
├── Makefile            # Comandos de desenvolvimento
├── data/               # Banco SQLite (criado automaticamente)
├── logs/               # Logs da aplicação  
├── backups/            # Backups do banco
└── nginx/              # Configuração do nginx
```

## 🔧 Configuração

### Variáveis de ambiente (.env)
```bash
# Stripe (obrigatório para pagamentos)
STRIPE_SECRET_KEY=sk_test_sua_chave_aqui
STRIPE_WEBHOOK_SECRET=whsec_seu_webhook_aqui

# Ambiente
GIN_MODE=debug  # ou release para produção
PORT=8080

# Database (automático)
DATABASE_URL=sqlite:///app/data/qrapi.db
```

### Chaves do Stripe
1. Crie uma conta no [Stripe](https://stripe.com)
2. Vá em **Developers > API Keys**
3. Copie a **Secret Key** para `STRIPE_SECRET_KEY`
4. Configure webhooks e copie o secret para `STRIPE_WEBHOOK_SECRET`

## 📡 Endpoints da API

### Usuários
- `POST /api/register` - Criar novo usuário e API key
- `GET /api/usage` - Verificar uso atual

### QR Codes  
- `POST /api/generate` - Gerar QR code (requer API key)
- `GET /qr/:id` - Visualizar QR code e contar scan
- `GET /analytics/:id` - Analytics do QR code

### Exemplo de uso
```bash
# 1. Registrar usuário
curl -X POST http://localhost:8080/api/register

# 2. Gerar QR code
curl -X POST http://localhost:8080/api/generate \
  -H "X-API-Key: sua_api_key_aqui" \
  -H "Content-Type: application/json" \
  -d '{
    "data": "https://github.com",
    "size": 512,
    "color": "#3B82F6",
    "bg_color": "#FFFFFF"
  }'
```

## 🎯 Planos e Recursos

| Plano | QR Codes/mês | Cores Custom | Logos | Analytics |
|-------|--------------|--------------|-------|-----------|
| Free | 100 | ❌ | ❌ | Básico |
| Starter | 2.500 | ✅ | ❌ | ✅ |
| Pro | 10.000 | ✅ | ✅ | ✅ |
| Business | 100.000 | ✅ | ✅ | ✅ |

## 🛠️ Desenvolvimento

### Estrutura do código Go
- **main()**: Inicialização da app, middleware, rotas
- **App struct**: Gerencia DB, Redis, rate limiters
- **Handlers**: Lógica de cada endpoint
- **Middleware**: Autenticação, rate limiting, CORS

### Adicionando novas funcionalidades
1. Modifique `qr_api_backend.go`
2. Rebuild e teste: `make restart-api`
3. Verifique logs: `make logs-api`

### Debugging
```bash
# Logs em tempo real
make logs

# Acesso ao container
make shell

# Stats de performance
make stats
```

## 🚀 Deploy em Produção

### VPS/Servidor
```bash
# Use o script de deploy automatizado
./deploy_script.sh

# Ou configure manualmente
docker compose --profile production up -d
```

### Variáveis para produção
```bash
GIN_MODE=release
FORCE_HTTPS=true
DOMAIN=seu-dominio.com
```

## 🔍 Troubleshooting

### Problemas comuns

**API não responde**:
```bash
make health
make logs-api
```

**Redis erro de conexão**:
```bash
make test-redis
make restart-redis
```

**Build failure**:
```bash
make clean
make build
```

**Permissões de arquivo**:
```bash
sudo chown -R $USER:$USER ./data ./logs
```

### Portas em uso
- 8080: API principal
- 6379: Redis
- 80/443: Nginx (opcional)

## 📝 Logs e Monitoramento

### Localização dos logs
- **API**: `docker compose logs qr-api`
- **Redis**: `docker compose logs redis`  
- **Nginx**: `./nginx/logs/`

### Métricas importantes
- Rate limits por API key
- Uso mensal por usuário
- Performance de geração de QR
- Scan analytics

## 🤝 Contribuindo

1. Fork o projeto
2. Crie sua feature branch
3. Commit suas mudanças
4. Push para a branch
5. Abra um Pull Request

## 📄 Licença

Este projeto está sob a licença MIT. Veja o arquivo LICENSE para mais detalhes.

## 🆘 Suporte

- 📧 Email: support@qrapi.dev
- 📚 Documentação: http://localhost:8080/docs
- 🐛 Issues: [GitHub Issues](https://github.com/seu-usuario/qr-api/issues)

---

⭐ **Dica**: Use `make help` para ver todos os comandos disponíveis!