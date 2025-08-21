# Static Rust build for 1GB RAM VPS - no runtime dependencies
FROM rust:1.75-alpine as builder

WORKDIR /app

# Install build dependencies for Alpine
RUN apk add --no-cache \
    musl-dev \
    pkgconfig \
    sqlite-dev \
    openssl-dev \
    openssl-libs-static

# Copy dependency files first for better caching
COPY Cargo.toml Cargo.lock ./

# Create dummy main.rs to build dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Build dependencies with static linking
ENV RUSTFLAGS="-C target-feature=+crt-static"
RUN cargo build --release --target x86_64-unknown-linux-musl && rm -rf src

# Copy source code
COPY src ./src

# Build the actual application with static linking
RUN cargo build --release --target x86_64-unknown-linux-musl

# Runtime stage - scratch image (no OS)
FROM scratch

# Copy binary from builder (fully static)
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/qr-api /qr-api

# Copy static files
COPY landing_page.html /index.html

EXPOSE 8080

CMD ["/qr-api"]