mod config;
mod entity;
mod phoenix;
mod time_utils;
mod weather;

use std::{env, time::Duration};

use anyhow::{anyhow, Context, Result};
use config::AppConfig;
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use tokio::time::{interval, sleep};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, info, warn};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            env::var("RUST_LOG")
                .unwrap_or_else(|_| "plugin=info,tokio_tungstenite=warn".into()),
        )
        .init();

    let cfg = AppConfig::from_env().expect("required env vars are missing");
    let ws_url = cfg.ws_url();

    info!(
        plugin_id = cfg.plugin_id,
        city = cfg.city_name,
        "Plugin starting → {}/websocket",
        cfg.ws_base.trim_end_matches('/')
    );

    loop {
        match run_session(&cfg, &ws_url).await {
            Ok(()) => {
                info!(plugin_id = cfg.plugin_id, "Disconnected cleanly, reconnecting in 5 s");
                sleep(Duration::from_secs(5)).await;
            }
            Err(e) => {
                warn!(plugin_id = cfg.plugin_id, error = %e, "Session error, reconnecting in 10 s");
                sleep(Duration::from_secs(10)).await;
            }
        }
    }
}

async fn run_session(cfg: &AppConfig, ws_url: &str) -> Result<()> {
    let http_client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(20))
        .build()
        .context("failed to build HTTP client")?;

    let (ws, _resp) = connect_async(ws_url)
        .await
        .context("WebSocket connect failed")?;
    info!(plugin_id = cfg.plugin_id, "WebSocket connected");

    let (mut sink, mut stream) = ws.split();
    let join_ref = phoenix::next_ref();
    let topic = format!("plugin:{}", cfg.plugin_id);

    sink.send(phoenix::phx_msg(
        Some(&join_ref),
        &join_ref,
        &topic,
        "phx_join",
        json!({}),
    ))
    .await
    .context("send phx_join")?;

    if !phoenix::await_join_reply(&mut stream, &topic).await? {
        return Err(anyhow!("Channel join rejected by server"));
    }
    info!(plugin_id = cfg.plugin_id, "Joined channel {topic}");

    sink.send(phoenix::phx_msg(
        None,
        &phoenix::next_ref(),
        &topic,
        "register",
        json!({ "entity_type_uri": "WeatherObserved" }),
    ))
    .await
    .context("send register")?;
    info!(plugin_id = cfg.plugin_id, "Registered as WeatherObserved");

    let city_fragment = cfg.city_urn_fragment();
    let eid = entity::entity_id(&city_fragment);

    let first_sample = weather::fetch_current_weather(&http_client, cfg.lat, cfg.lon).await?;
    let create_ref = phoenix::next_ref();
    sink.send(phoenix::phx_msg(
        None,
        &create_ref,
        &topic,
        "entity_create",
        json!({
            "request_id": create_ref,
            "entity": entity::build_entity(&city_fragment, cfg.lat, cfg.lon, first_sample.temp(), first_sample.hum())
        }),
    ))
    .await
    .context("send entity_create")?;

    info!(
        plugin_id = cfg.plugin_id,
        city = cfg.city_name,
        entity_id = eid,
        temp = first_sample.temp(),
        humidity = first_sample.hum(),
        "Initial entity created"
    );

    let mut update_tick = interval(Duration::from_secs(600));
    let mut hb_tick = interval(Duration::from_secs(30));
    update_tick.tick().await;

    loop {
        tokio::select! {
            frame = stream.next() => {
                match frame {
                    Some(Ok(Message::Text(text))) => phoenix::on_inbound(&text, &cfg.plugin_id),
                    Some(Ok(Message::Close(_))) | None => {
                        info!(plugin_id = cfg.plugin_id, "Server closed connection");
                        return Ok(());
                    }
                    Some(Ok(_)) => {}
                    Some(Err(e)) => return Err(e.into()),
                }
            }

            _ = update_tick.tick() => {
                match weather::fetch_current_weather(&http_client, cfg.lat, cfg.lon).await {
                    Ok(sample) => {
                        let upd_ref = phoenix::next_ref();
                        sink.send(phoenix::phx_msg(
                            None,
                            &upd_ref,
                            &topic,
                            "entity_update",
                            json!({
                                "request_id": upd_ref,
                                "entity_id": eid,
                                "attrs": entity::build_update_attrs(cfg.lat, cfg.lon, sample.temp(), sample.hum())
                            }),
                        ))
                        .await
                        .context("send entity_update")?;
                        info!(plugin_id = cfg.plugin_id, city = cfg.city_name, temp = sample.temp(), humidity = sample.hum(), "Published update from api.met.no");
                    }
                    Err(e) => {
                        warn!(plugin_id = cfg.plugin_id, error = %e, "Skipping update because weather fetch failed");
                    }
                }
            }

            _ = hb_tick.tick() => {
                sink.send(phoenix::phx_msg(None, &phoenix::next_ref(), "phoenix", "heartbeat", json!({})))
                    .await
                    .context("send heartbeat")?;
                debug!(plugin_id = cfg.plugin_id, "Heartbeat sent");
            }
        }
    }
}
