use serde_json::{json, Value};

use crate::time_utils::now_iso8601;

pub fn entity_id(city_fragment: &str) -> String {
    format!("urn:ngsi-ld:WeatherObserved:{city_fragment}")
}

pub fn build_entity(city_fragment: &str, lat: f64, lon: f64, temp: f64, humidity: f64) -> Value {
    json!({
        "id": entity_id(city_fragment),
        "type": "WeatherObserved",
        "@context": [
            "https://uri.etsi.org/ngsi-ld/v1/ngsi-ld-core-context.jsonld",
            "https://smartdatamodels.org/context.jsonld"
        ],
        "location": {
            "type": "GeoProperty",
            "value": {
                "type": "Point",
                "coordinates": [lon, lat]
            }
        },
        "temperature": {
            "type": "Property",
            "value": temp,
            "unitCode": "CEL",
            "observedAt": now_iso8601()
        },
        "relativeHumidity": {
            "type": "Property",
            "value": humidity,
            "observedAt": now_iso8601()
        },
        "dateObserved": {
            "type": "Property",
            "value": {
                "@type": "DateTime",
                "@value": now_iso8601()
            }
        }
    })
}

pub fn build_update_attrs(lat: f64, lon: f64, temp: f64, humidity: f64) -> Value {
    json!({
        "location": {
            "type": "GeoProperty",
            "value": {
                "type": "Point",
                "coordinates": [lon, lat]
            }
        },
        "temperature": {
            "type": "Property",
            "value": temp,
            "unitCode": "CEL",
            "observedAt": now_iso8601()
        },
        "relativeHumidity": {
            "type": "Property",
            "value": humidity,
            "observedAt": now_iso8601()
        },
        "dateObserved": {
            "type": "Property",
            "value": {
                "@type": "DateTime",
                "@value": now_iso8601()
            }
        }
    })
}
