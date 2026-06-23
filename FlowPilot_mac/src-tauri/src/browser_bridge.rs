use serde::Deserialize;
use std::io::Read;
use std::sync::{Arc, Mutex};
use std::thread;

use crate::storage::repository::Repository;

const BRIDGE_HEADER_NAME: &str = "x-flowpilot-bridge";
const BRIDGE_HEADER_VALUE: &str = "flowpilot-browser-bridge-v1";
const MAX_BROWSER_EVENT_BODY_BYTES: usize = 16 * 1024;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BrowserEventDraft {
    pub domain: String,
    pub url: Option<String>,
    pub title: String,
}

pub fn start_browser_bridge(repository: Arc<Mutex<Repository>>) -> anyhow::Result<()> {
    let server = tiny_http::Server::http("127.0.0.1:17321")
        .map_err(|err| anyhow::anyhow!("browser bridge failed to bind: {err}"))?;
    thread::spawn(move || {
        for mut request in server.incoming_requests() {
            if request.url() != "/browser-event" {
                let _ = request.respond(tiny_http::Response::empty(404));
                continue;
            }

            if request.method() != &tiny_http::Method::Post {
                let _ = request.respond(tiny_http::Response::empty(405));
                continue;
            }

            if validate_bridge_headers(request.headers()).is_err() {
                let _ = request.respond(tiny_http::Response::empty(403));
                continue;
            }

            let response = match read_capped_body(request.as_reader()) {
                Ok(body) => match serde_json::from_str::<BrowserEventDraft>(&body) {
                    Ok(draft) => match repository.lock() {
                        Ok(repo) => match repo.save_browser_event(draft) {
                            Ok(_) => tiny_http::Response::empty(204),
                            Err(_) => tiny_http::Response::empty(500),
                        },
                        Err(_) => tiny_http::Response::empty(500),
                    },
                    Err(_) => tiny_http::Response::empty(400),
                },
                Err(BodyReadError::TooLarge) => tiny_http::Response::empty(413),
                Err(_) => tiny_http::Response::empty(400),
            };
            let _ = request.respond(response);
        }
    });
    Ok(())
}

#[derive(Debug, PartialEq)]
enum HeaderValidationError {
    MissingOrInvalid,
}

#[derive(Debug, PartialEq)]
enum BodyReadError {
    Io,
    InvalidUtf8,
    TooLarge,
}

fn validate_bridge_headers(headers: &[tiny_http::Header]) -> Result<(), HeaderValidationError> {
    let has_json_content_type = headers.iter().any(|header| {
        header.field.equiv("content-type")
            && header
                .value
                .as_str()
                .split(';')
                .next()
                .map(|value| value.trim().eq_ignore_ascii_case("application/json"))
                .unwrap_or(false)
    });
    let has_bridge_header = headers.iter().any(|header| {
        header.field.equiv(BRIDGE_HEADER_NAME) && header.value.as_str() == BRIDGE_HEADER_VALUE
    });

    if has_json_content_type && has_bridge_header {
        Ok(())
    } else {
        Err(HeaderValidationError::MissingOrInvalid)
    }
}

fn read_capped_body(reader: impl Read) -> Result<String, BodyReadError> {
    let mut body = Vec::new();
    reader
        .take((MAX_BROWSER_EVENT_BODY_BYTES + 1) as u64)
        .read_to_end(&mut body)
        .map_err(|_| BodyReadError::Io)?;

    if body.len() > MAX_BROWSER_EVENT_BODY_BYTES {
        return Err(BodyReadError::TooLarge);
    }

    String::from_utf8(body).map_err(|_| BodyReadError::InvalidUtf8)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tiny_http::Header;

    #[test]
    fn rejects_missing_bridge_header() {
        let headers = vec![Header::from_bytes("content-type", "application/json").unwrap()];

        assert!(validate_bridge_headers(&headers).is_err());
    }

    #[test]
    fn rejects_oversized_body() {
        let body = vec![b'a'; MAX_BROWSER_EVENT_BODY_BYTES + 1];

        let error = read_capped_body(&body[..]).expect_err("oversized body should be rejected");

        assert_eq!(error, BodyReadError::TooLarge);
    }
}
