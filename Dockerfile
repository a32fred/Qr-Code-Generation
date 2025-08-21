# Rust optimized Dockerfile for 1GB RAM VPS
FROM rust:1.75-slim as builder

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files first for better caching
COPY Cargo.toml Cargo.lock ./

# Create dummy main.rs to build dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Build dependencies (this layer will be cached)
RUN cargo build --release --locked && rm -rf src

# Copy source code
COPY src ./src

# Build the actual application
RUN cargo build --release --locked

# Runtime stage - minimal image
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

# Create app user
RUN useradd -r -s /bin/false -m -d /app qrapi

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/target/release/qr-api ./qr-api

# Copy static files
COPY landing_page.html ./index.html

# Create directories and set permissions
RUN mkdir -p data logs && \
    chown -R qrapi:qrapi /app

USER qrapi

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

CMD ["./qr-api"]