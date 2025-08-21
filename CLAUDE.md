# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
This is a QR Code API service built in Rust using the Axum framework. It provides QR code generation with premium features like custom colors, logos, and analytics. The project includes user management, rate limiting, and Stripe integration for subscription plans.

## Architecture
- **Backend**: Rust API server using Axum framework (async/await)
- **Database**: SQLite with SQLx for type-safe queries
- **Cache**: Redis for usage tracking and rate limiting
- **Frontend**: Single HTML landing page with embedded JavaScript
- **Payment**: Stripe integration for subscription management
- **Deployment**: Docker-based with nginx reverse proxy, optimized for 1GB RAM

## Core Components

### API Structure (Rust modules)
- **main.rs**: Application setup with Axum router and shared state
- **handlers.rs**: HTTP request handlers for all endpoints
- **models.rs**: Data structures with Serde serialization
- **database.rs**: SQLite operations with SQLx for type safety
- **AppState**: Shared state managing SQLite pool and Redis client
- User management with API key authentication via `X-API-Key` header
- Tiered pricing plans: free (100), starter (2500), pro (10000), business (100000) QR codes/month
- Premium features gated by plan level (custom colors for Pro+, logos for Pro+)

### Database Schema
- `users` table: id, api_key, plan, stripe_customer_id, created_at
- `qr_codes` table: id, user_id, data, scans, created_at

### Key Endpoints
- `POST /api/register` - Create new user and API key
- `POST /api/generate` - Generate QR code (requires auth)
- `GET /api/usage` - Check current usage limits
- `GET /qr/:id` - View/redirect QR code and track scans
- `GET /analytics/:id` - Get scan analytics

## Development Commands

### Building and Running
```bash
# Build the Rust application
cargo build --release

# Run locally (requires Redis and SQLite)
./target/release/qr-api

# Using Docker (recommended)
docker-compose up -d
```

### Dependencies
The project uses these key Rust crates:
- `axum` - Modern async web framework
- `tokio` - Async runtime
- `sqlx` - Async SQL toolkit with compile-time checked queries
- `redis` - Redis client with async support
- `qrcode` - QR code generation
- `serde` - Serialization framework
- `stripe-rust` - Stripe API integration

### Environment Variables
Required environment variables (typically in .env file):
- `STRIPE_SECRET_KEY` - Stripe secret key for payments
- `STRIPE_WEBHOOK_SECRET` - Stripe webhook verification

## Deployment Configuration

### Docker Setup
The project includes optimized Docker configuration for low-memory VPS deployment:
- Multi-stage Docker build for minimal image size
- Memory limits: API (300-350MB), Redis (100-120MB), nginx (50MB)
- Redis configured with memory optimization (`maxmemory-policy allkeys-lru`)

### Production Scripts
- `deploy.sh` - Automated VPS setup script with system optimization
- Rate limiting via nginx (10 req/s for API, 1 req/min for registration)
- SSL/TLS termination at nginx level
- Monitoring and backup scripts included

## Security Features
- API key-based authentication with rate limiting per key
- CORS headers configured
- Input validation on QR generation requests
- Stripe webhook signature verification (placeholder)
- nginx security headers and rate limiting

## Premium Feature Gates
Features are unlocked based on user plan level:
- Free: Basic QR codes, PNG format only
- Starter+: Custom colors, multiple formats
- Pro+: Custom logos, advanced analytics
- Business: Bulk generation, webhooks, white-label

## Database Initialization
The application automatically creates required tables on startup via `initDB()` function. No manual schema setup required.