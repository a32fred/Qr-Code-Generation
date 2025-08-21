use redis::{Client, Commands};
use chrono::Utc;

pub async fn get_monthly_usage(client: &Client, user_id: i64) -> Result<i32, redis::RedisError> {
    let mut conn = client.get_connection()?;
    let key = format!("usage:{}:{}", user_id, Utc::now().format("%Y-%m"));
    
    let usage: Option<i32> = conn.get(&key)?;
    Ok(usage.unwrap_or(0))
}

pub async fn increment_usage(client: &Client, user_id: i64) -> Result<(), redis::RedisError> {
    let mut conn = client.get_connection()?;
    let key = format!("usage:{}:{}", user_id, Utc::now().format("%Y-%m"));
    
    let _: () = conn.incr(&key, 1)?;
    let _: () = conn.expire(&key, 32 * 24 * 60 * 60)?; // Expire next month
    
    Ok(())
}