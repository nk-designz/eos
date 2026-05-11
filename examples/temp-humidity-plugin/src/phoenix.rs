use anyhow::{anyhow, Result};
use futures_util::StreamExt;
use serde_json::{json, Value};
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

pub fn phx_msg(
    join_ref: Option<&str>,
    msg_ref: &str,
    topic: &str,
    event: &str,
    payload: Value,
) -> Message {
    Message::Text(json!([join_ref, msg_ref, topic, event, payload]).to_string().into())
}

pub fn next_ref() -> String {
    Uuid::new_v4().to_string()
}

pub async fn await_join_reply(
    stream: &mut (impl StreamExt<Item = Result<Message, tokio_tungstenite::tungstenite::Error>> + Unpin),
    topic: &str,
) -> Result<bool> {
    while let Some(msg) = stream.next().await {
        let text = match msg? {
            Message::Text(t) => t,
            _ => continue,
        };
        let frame: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
        if frame.get(2).and_then(Value::as_str) == Some(topic)
            && frame.get(3).and_then(Value::as_str) == Some("phx_reply")
        {
            let status = frame
                .get(4)
                .and_then(|p| p.get("status"))
                .and_then(Value::as_str)
                .unwrap_or("");
            return Ok(status == "ok");
        }
    }
    Err(anyhow!("Connection closed before join reply"))
}

pub fn on_inbound(text: &str, plugin_id: &str) {
    let Ok(frame) = serde_json::from_str::<Value>(text) else {
        return;
    };
    let event = frame.get(3).and_then(Value::as_str).unwrap_or("");
    let payload = frame.get(4).cloned().unwrap_or(Value::Null);

    match event {
        "entity_response" => {
            let status = payload.get("status").and_then(Value::as_str).unwrap_or("?");
            let req_id = payload.get("request_id").and_then(Value::as_str).unwrap_or("?");
            if status == "ok" {
                debug!(plugin_id, req_id, "entity_response ok");
            } else {
                warn!(plugin_id, req_id, ?payload, "entity_response non-ok");
            }
        }
        "entity_changed" => {
            let eid = payload.get("entity_id").and_then(Value::as_str).unwrap_or("?");
            info!(plugin_id, entity_id = eid, "entity_changed notification received");
        }
        "error" => {
            error!(plugin_id, ?payload, "Agent error");
        }
        "welcome" => {
            let pid = payload.get("plugin_id").and_then(Value::as_str).unwrap_or("?");
            info!(plugin_id, "Welcome from agent (server plugin_id = '{pid}')");
        }
        "phx_reply" | "phx_close" => {
            debug!(event, "Phoenix control");
        }
        _ => {
            debug!(plugin_id, event, "Unknown event");
        }
    }
}
