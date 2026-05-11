use std::env;

use anyhow::{Context, Result};

#[derive(Clone, Debug)]
pub struct AppConfig {
    pub plugin_id: String,
    pub token: String,
    pub ws_base: String,
    pub city_name: String,
    pub lat: f64,
    pub lon: f64,
}

impl AppConfig {
    pub fn from_env() -> Result<Self> {
        let plugin_id = env::var("PLUGIN_ID").context("PLUGIN_ID env var required")?;
        let token = env::var("PLUGIN_TOKEN").context("PLUGIN_TOKEN env var required")?;
        let ws_base = env::var("IOT_AGENT_WS_URL").context("IOT_AGENT_WS_URL env var required")?;

        let city_name = env::var("CITY_NAME").unwrap_or_else(|_| "Braunschweig".to_string());
        let lat = env::var("CITY_LAT")
            .ok()
            .and_then(|v| v.parse::<f64>().ok())
            .unwrap_or(52.2689);
        let lon = env::var("CITY_LON")
            .ok()
            .and_then(|v| v.parse::<f64>().ok())
            .unwrap_or(10.5268);

        Ok(Self {
            plugin_id,
            token,
            ws_base,
            city_name,
            lat,
            lon,
        })
    }

    pub fn ws_url(&self) -> String {
        let base = self.ws_base.trim_end_matches('/');
        format!("{base}/websocket?vsn=2.0.0&token={}", self.token)
    }

    pub fn city_urn_fragment(&self) -> String {
        self.city_name
            .chars()
            .map(|c| {
                if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                    c
                } else if c.is_whitespace() {
                    '-'
                } else {
                    '_'
                }
            })
            .collect()
    }
}
