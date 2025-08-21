# QR Code API

API REST ultra-simples para geração de QR codes com Python Flask.

## 🚀 Quick Start

### Método 1: Script automático
```bash
git clone https://github.com/a32fred/Qr-Code-Generation.git
cd Qr-Code-Generation
./run.sh
```

### Método 2: Docker
```bash
docker compose up -d
```

### Método 3: Manual
```bash
pip install -r requirements.txt
python app.py
```

**🎉 API rodando em http://localhost:5000**

## 📡 Endpoints

- `GET /` - Informações da API
- `POST /api/register` - Criar usuário e API key
- `POST /api/generate` - Gerar QR code (requer X-API-Key)
- `GET /api/usage` - Verificar uso atual
- `GET /qr/:id` - Visualizar QR code
- `GET /analytics/:id` - Analytics do QR

## 💡 Exemplo de uso

```bash
# 1. Registrar usuário
curl -X POST http://localhost:5000/api/register

# 2. Gerar QR code
curl -X POST http://localhost:5000/api/generate \
  -H "X-API-Key: sua_api_key_aqui" \
  -H "Content-Type: application/json" \
  -d '{"data": "https://github.com", "size": 256}'
```

## 🎯 Planos

| Plano | QR Codes/mês |
|-------|--------------|
| Free | 100 |
| Starter | 2.500 |
| Pro | 10.000 |
| Business | 100.000 |

## 🛠️ Tecnologias

- **Python Flask** - Framework web
- **SQLite** - Banco de dados 
- **qrcode** - Geração de QR codes
- **150 linhas** total de código

## 📁 Arquivos

- `app.py` - Aplicação principal
- `requirements.txt` - Dependências Python
- `run.sh` - Script de instalação e execução
- `docker-compose.yml` - Configuração Docker