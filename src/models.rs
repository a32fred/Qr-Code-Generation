use serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};

#[derive(Debug, Serialize, Deserialize)]
pub struct QRRequest {
    pub data: String,
    #[serde(default = "default_size")]
    pub size: u32,
    #[serde(default = "default_format")]
    pub format: String,
    #[serde(default = "default_color")]
    pub color: String,
    #[serde(default = "default_bg_color")]
    pub bg_color: String,
    #[serde(default)]
    pub logo: Option<String>, // base64 encoded
}

#[derive(Debug, Serialize)]
pub struct QRResponse {
    pub qr_code: String,    // base64 encoded
    pub qr_url: String,     // URL para download
    pub analytics: String,  // URL para analytics
}

#[derive(Debug, Serialize, Deserialize)]
pub struct User {
    pub id: i64,
    pub api_key: String,
    pub plan: String,
    pub stripe_customer_id: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct UsageResponse {
    pub plan: String,
    pub usage: i32,
    pub limit: i32,
    pub remaining: i32,
    pub reset_date: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
pub struct AnalyticsResponse {
    pub qr_id: String,
    pub total_scans: i32,
    pub created_at: DateTime<Utc>,
    pub avg_scans_per_day: f64,
}

#[derive(Debug, Serialize)]
pub struct RegistrationResponse {
    pub api_key: String,
    pub plan: String,
    pub limit: i32,
    pub message: String,
}

#[derive(Debug, Serialize)]
pub struct HomeResponse {
    pub service: String,
    pub version: String,
    pub docs: String,
    pub pricing: serde_json::Value,
}

// Default values
fn default_size() -> u32 { 256 }
fn default_format() -> String { "png".to_string() }
fn default_color() -> String { "#000000".to_string() }
fn default_bg_color() -> String { "#FFFFFF".to_string() }

// Plan limits
pub const PLAN_LIMITS: &[(&str, i32)] = &[
    ("free", 100),
    ("starter", 2500),
    ("pro", 10000),
    ("business", 100000),
];

pub fn get_plan_limit(plan: &str) -> i32 {
    PLAN_LIMITS.iter()
        .find(|(p, _)| *p == plan)
        .map(|(_, limit)| *limit)
        .unwrap_or(100)
}