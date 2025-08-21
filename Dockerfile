# Dockerfile para desenvolvimento local
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Instalar dependências do sistema
RUN apk add --no-cache git gcc musl-dev sqlite-dev

# Copiar arquivos de módulo Go
COPY go.mod ./
RUN go mod download

# Copiar código fonte
COPY . .

# Build da aplicação
RUN CGO_ENABLED=1 GOOS=linux go build \
    -ldflags="-w -s" \
    -a -installsuffix cgo \
    -o main ./qr_api_backend.go

# Estágio final - imagem mínima
FROM alpine:latest

# Configurar mirror brasileiro e instalar dependências
RUN echo "https://mirror.ufro.cl/alpine/v3.22/main" > /etc/apk/repositories && \
    echo "https://mirror.ufro.cl/alpine/v3.22/community" >> /etc/apk/repositories && \
    apk update && \
    apk --no-cache add ca-certificates sqlite tzdata wget

# Criar usuário não-root
RUN addgroup -g 1001 -S app && \
    adduser -S -D -H -u 1001 -h /app -s /sbin/nologin -G app -g app app

WORKDIR /app

# Copiar binário
COPY --from=builder /app/main .
COPY --from=builder /app/landing_page.html ./index.html

# Criar diretórios necessários
RUN mkdir -p data logs && chown -R app:app /app

# Mudar para usuário não-root
USER app

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1

CMD ["./main"]