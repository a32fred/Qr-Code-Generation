use axum::{
    extract::{Path, State, Query},
    http::{StatusCode, HeaderMap},
    response::Json,
    middleware::Next,
    extract::Request,
    response::Response,
};
use serde_json::{json, Value};
use std::sync::Arc;
use uuid::Uuid;
use chrono::Utc;

use crate::{
    models::*,
    AppState,
    database,
    qr_service,
    auth,
    redis_client,
};

pub async fn handle_home() -> Json<HomeResponse> {
    Json(HomeResponse {
        service: "QR Code API".to_string(),
        version: "1.0".to_string(),
        docs: "https://qrapi.dev/docs".to_string(),
        pricing: json!({
            "free": "100 QRs/month",
            "starter": "$5/month - 2,500 QRs",
            "pro": "$15/month - 10,000 QRs + features",
            "business": "$50/month - 100,000 QRs + everything"
        }),
    })
}

pub async fn handle_register(
    State(state): State<Arc<AppState>>,
) -> Result<Json<RegistrationResponse>, StatusCode> {
    let api_key = auth::generate_api_key();
    
    // Create user in database
    match database::create_user(&state.db, &api_key).await {
        Ok(_) => {
            Ok(Json(RegistrationResponse {
                api_key,
                plan: "free".to_string(),
                limit: 100,
                message: "Welcome! You have 100 free QR codes per month.".to_string(),
            }))
        }
        Err(_) => Err(StatusCode::INTERNAL_SERVER_ERROR),
    }
}

pub async fn handle_generate(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(req): Json<QRRequest>,
) -> Result<Json<QRResponse>, StatusCode> {
    // Extract API key from headers
    let api_key = headers
        .get("X-API-Key")
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    // Get user from database
    let user = database::get_user_by_api_key(&state.db, api_key)
        .await
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    // Check usage limits
    let usage = redis_client::get_monthly_usage(&state.redis, user.id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let limit = get_plan_limit(&user.plan);
    if usage >= limit {
        return Err(StatusCode::TOO_MANY_REQUESTS);
    }

    // Generate QR code
    let qr_id = Uuid::new_v4().to_string();
    let qr_image = qr_service::generate_qr(&req, &user.plan)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Save to database
    database::create_qr_code(&state.db, &qr_id, user.id, &req.data)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Increment usage
    redis_client::increment_usage(&state.redis, user.id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Get base URL from environment
    let base_url = std::env::var("BASE_URL")
        .unwrap_or_else(|_| "http://localhost:8080".to_string());

    Ok(Json(QRResponse {
        qr_code: base64::encode(qr_image),
        qr_url: format!("{}/qr/{}", base_url, qr_id),
        analytics: format!("{}/analytics/{}", base_url, qr_id),
    }))
}

pub async fn handle_usage(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<UsageResponse>, StatusCode> {
    let api_key = headers
        .get("X-API-Key")
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let user = database::get_user_by_api_key(&state.db, api_key)
        .await
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let usage = redis_client::get_monthly_usage(&state.redis, user.id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let limit = get_plan_limit(&user.plan);

    Ok(Json(UsageResponse {
        plan: user.plan,
        usage,
        limit,
        remaining: limit - usage,
        reset_date: get_next_month_first(),
    }))
}

pub async fn handle_qr_view(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<Value>, StatusCode> {
    // Increment scan count
    database::increment_scan_count(&state.db, &id)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    // Get QR data
    let data = database::get_qr_data(&state.db, &id)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    // If it's a URL, return redirect instruction
    if data.starts_with("http") {
        Ok(Json(json!({ "redirect": data })))
    } else {
        Ok(Json(json!({ "data": data })))
    }
}

pub async fn handle_analytics(
    State(state): State<Arc<AppState>>,
    Path(id): Path<String>,
) -> Result<Json<AnalyticsResponse>, StatusCode> {
    let analytics = database::get_qr_analytics(&state.db, &id)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    Ok(Json(analytics))
}

pub async fn handle_stripe_webhook(
    Json(payload): Json<Value>,
) -> Json<Value> {
    // TODO: Implement Stripe webhook handling
    tracing::info!("Received Stripe webhook: {:?}", payload);
    Json(json!({ "received": true }))
}

fn get_next_month_first() -> chrono::DateTime<Utc> {
    let now = Utc::now();
    let year = if now.month() == 12 { now.year() + 1 } else { now.year() };
    let month = if now.month() == 12 { 1 } else { now.month() + 1 };
    
    chrono::Utc.with_ymd_and_hms(year, month, 1, 0, 0, 0).unwrap()
}