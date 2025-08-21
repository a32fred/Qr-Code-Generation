use sqlx::{SqlitePool, Row};
use chrono::{DateTime, Utc};
use crate::models::{User, AnalyticsResponse};

pub async fn migrate(pool: &SqlitePool) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            api_key TEXT UNIQUE NOT NULL,
            plan TEXT DEFAULT 'free',
            stripe_customer_id TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE TABLE IF NOT EXISTS qr_codes (
            id TEXT PRIMARY KEY,
            user_id INTEGER,
            data TEXT NOT NULL,
            scans INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users (id)
        );
        "#,
    )
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn create_user(pool: &SqlitePool, api_key: &str) -> Result<i64, sqlx::Error> {
    let result = sqlx::query(
        "INSERT INTO users (api_key) VALUES (?)"
    )
    .bind(api_key)
    .execute(pool)
    .await?;

    Ok(result.last_insert_rowid())
}

pub async fn get_user_by_api_key(pool: &SqlitePool, api_key: &str) -> Result<User, sqlx::Error> {
    let row = sqlx::query(
        "SELECT id, api_key, plan, stripe_customer_id, created_at FROM users WHERE api_key = ?"
    )
    .bind(api_key)
    .fetch_one(pool)
    .await?;

    Ok(User {
        id: row.get("id"),
        api_key: row.get("api_key"),
        plan: row.get("plan"),
        stripe_customer_id: row.get("stripe_customer_id"),
        created_at: row.get("created_at"),
    })
}

pub async fn create_qr_code(
    pool: &SqlitePool,
    id: &str,
    user_id: i64,
    data: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO qr_codes (id, user_id, data) VALUES (?, ?, ?)"
    )
    .bind(id)
    .bind(user_id)
    .bind(data)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn increment_scan_count(pool: &SqlitePool, id: &str) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE qr_codes SET scans = scans + 1 WHERE id = ?"
    )
    .bind(id)
    .execute(pool)
    .await?;

    Ok(())
}

pub async fn get_qr_data(pool: &SqlitePool, id: &str) -> Result<String, sqlx::Error> {
    let row = sqlx::query(
        "SELECT data FROM qr_codes WHERE id = ?"
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    Ok(row.get("data"))
}

pub async fn get_qr_analytics(pool: &SqlitePool, id: &str) -> Result<AnalyticsResponse, sqlx::Error> {
    let row = sqlx::query(
        "SELECT scans, created_at FROM qr_codes WHERE id = ?"
    )
    .bind(id)
    .fetch_one(pool)
    .await?;

    let scans: i32 = row.get("scans");
    let created_at: DateTime<Utc> = row.get("created_at");
    let days_since_creation = (Utc::now() - created_at).num_days() as f64;
    let avg_scans_per_day = if days_since_creation > 0.0 {
        scans as f64 / days_since_creation
    } else {
        scans as f64
    };

    Ok(AnalyticsResponse {
        qr_id: id.to_string(),
        total_scans: scans,
        created_at,
        avg_scans_per_day,
    })
}