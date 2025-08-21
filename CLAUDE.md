# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
This is a QR Code API service built in Go using the Gin framework. It provides QR code generation with premium features like custom colors, logos, and analytics. The project includes user management, rate limiting, and Stripe integration for subscription plans.

## Architecture
- **Backend**: Go API server (qr_api_backend.go) using Gin framework
- **Database**: SQLite for user data and QR code metadata 
- **Cache**: Redis for usage tracking and rate limiting
- **Frontend**: Single HTML landing page with embedded JavaScript
- **Payment**: Stripe integration for subscription management
- **Deployment**: Docker-based with nginx reverse proxy

## Core Components

### API Structure (qr_api_backend.go)
- Main application struct (`App`) manages database, Redis, and rate limiters
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
# Build the Go application
go build -o qr-api qr_api_backend.go

# Run locally (requires Redis and SQLite)
./qr-api

# Using Docker (recommended)
docker-compose up -d
```

### Dependencies
The project uses these key Go modules:
- `github.com/gin-gonic/gin` - Web framework
- `github.com/go-redis/redis/v8` - Redis client
- `github.com/skip2/go-qrcode` - QR code generation
- `github.com/stripe/stripe-go/v74` - Stripe payments
- `github.com/mattn/go-sqlite3` - SQLite driver
- `golang.org/x/time/rate` - Rate limiting

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