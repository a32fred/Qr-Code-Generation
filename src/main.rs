mod models;
mod handlers;
mod database;
mod qr_service;
mod auth;
mod redis_client;

use axum::{
    routing::{get, post},
    Router,
    middleware,
};
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;
use std::sync::Arc;
use sqlx::SqlitePool;
use redis::Client as RedisClient;

pub struct AppState {
    pub db: SqlitePool,
    pub redis: RedisClient,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Load environment variables
    dotenvy::dotenv().ok();

    // Initialize database
    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "sqlite:///app/data/qrapi.db".to_string());
    
    let db = SqlitePool::connect(&database_url).await?;
    database::migrate(&db).await?;

    // Initialize Redis
    let redis_url = std::env::var("REDIS_URL")
        .unwrap_or_else(|_| "redis://redis:6379/0".to_string());
    let redis = RedisClient::open(redis_url)?;

    // Create app state
    let state = Arc::new(AppState { db, redis });

    // Configure CORS
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    // Build the router
    let app = Router::new()
        .route("/", get(handlers::handle_home))
        .route("/api/register", post(handlers::handle_register))
        .route("/api/generate", post(handlers::handle_generate))
        .route("/api/usage", get(handlers::handle_usage))
        .route("/api/webhook/stripe", post(handlers::handle_stripe_webhook))
        .route("/qr/:id", get(handlers::handle_qr_view))
        .route("/analytics/:id", get(handlers::handle_analytics))
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Start server
    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let addr = format!("0.0.0.0:{}", port);
    
    tracing::info!("🦀 QR API Server starting on {}", addr);
    
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}