use anyhow::{anyhow, Context, Result};
use reqwest::header::USER_AGENT;
use serde_json::Value;

const MET_USER_AGENT: &str = "eos-weather-plugin/0.1 (+https://eos.nk-desig.nz)";

pub struct WeatherSample {
    pub temperature_c: f64,
    pub humidity_ratio: f64,
}

impl WeatherSample {
    pub fn temp(&self) -> f64 {
        (self.temperature_c * 100.0).round() / 100.0
    }

    pub fn hum(&self) -> f64 {
        (self.humidity_ratio * 1000.0).round() / 1000.0
    }
}

pub async fn fetch_current_weather(client: &reqwest::Client, lat: f64, lon: f64) -> Result<WeatherSample> {
    let url = format!(
        "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat={lat}&lon={lon}"
    );

    let response = client
        .get(url)
        .header(USER_AGENT, MET_USER_AGENT)
        .send()
        .await
        .context("request to api.met.no failed")?
        .error_for_status()
        .context("api.met.no returned non-success status")?;

    let body: Value = response
        .json()
        .await
        .context("failed to parse api.met.no response JSON")?;

    let details = body
        .get("properties")
        .and_then(|p| p.get("timeseries"))
        .and_then(Value::as_array)
        .and_then(|series| series.first())
        .and_then(|item| item.get("data"))
        .and_then(|data| data.get("instant"))
        .and_then(|instant| instant.get("details"))
        .ok_or_else(|| anyhow!("api.met.no response missing properties.timeseries[0].data.instant.details"))?;

    let temperature_c = details
        .get("air_temperature")
        .and_then(Value::as_f64)
        .ok_or_else(|| anyhow!("api.met.no response missing air_temperature"))?;

    let humidity_percent = details
        .get("relative_humidity")
        .and_then(Value::as_f64)
        .ok_or_else(|| anyhow!("api.met.no response missing relative_humidity"))?;

    Ok(WeatherSample {
        temperature_c,
        humidity_ratio: (humidity_percent / 100.0).clamp(0.0, 1.0),
    })
}
