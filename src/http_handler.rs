use crate::embedder::{Embedder, VALID_DIMENSIONS};
use crate::error::EmbedError;
use lambda_http::{Body, Error, Request, Response};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use tracing::{error, info, warn};

/// Maximum input text length in characters
/// Prevents OOM from extremely long inputs
const MAX_TEXT_LENGTH: usize = 100_000;

/// Incoming request payload
#[derive(Deserialize)]
struct EmbedRequest {
    /// The text to embed
    text: String,
    /// Output dimension: 768, 512, 256, or 128 (default: 768)
    #[serde(default = "default_size")]
    size: usize,
}

fn default_size() -> usize {
    768
}

/// Response payload containing the embedding vector
#[derive(Serialize)]
struct EmbedResponse {
    /// The embedding vector
    embedding: Vec<f32>,
    /// Dimension of the embedding
    size: usize,
}

/// Error response payload
#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

/// Lambda handler function.
///
/// Receives an HTTP request with JSON body, generates an embedding,
/// and returns it as a JSON response.
pub async fn function_handler(
    embedder: Arc<Mutex<Embedder>>,
    event: Request,
) -> Result<Response<Body>, Error> {
    // Parse the JSON request body
    let body = event.body();
    let request: EmbedRequest = match serde_json::from_slice(body) {
        Ok(req) => req,
        Err(e) => {
            return Ok(error_response(400, &format!("Invalid JSON: {}", e)));
        }
    };

    // Validate the size parameter
    if !VALID_DIMENSIONS.contains(&request.size) {
        return Ok(error_response(
            400,
            &format!(
                "Invalid size: {}. Must be one of: {:?}",
                request.size, VALID_DIMENSIONS
            ),
        ));
    }

    // Validate text is not empty
    if request.text.is_empty() {
        let err = EmbedError::EmptyInput;
        warn!("Empty text input");
        return Ok(error_from_embed_error(&err));
    }

    // Validate text length to prevent OOM
    if request.text.len() > MAX_TEXT_LENGTH {
        let err = EmbedError::TextTooLong {
            got: request.text.len(),
            max: MAX_TEXT_LENGTH,
        };
        warn!("Text too long: {} chars", request.text.len());
        return Ok(error_from_embed_error(&err));
    }

    // Generate the embedding
    // Mutex required: ONNX Runtime Rust bindings need &mut for session.run()
    // Lambda processes one request at a time per container, so no contention
    let embedding = {
        // Safe mutex handling - recover from poisoned state
        let mut embedder = match embedder.lock() {
            Ok(guard) => guard,
            Err(poisoned) => {
                warn!("Mutex was poisoned, recovering...");
                poisoned.into_inner()
            }
        };

        match embedder.embed(&request.text, request.size) {
            Ok(emb) => {
                info!(
                    text_len = request.text.len(),
                    embedding_size = request.size,
                    "Embedding generated successfully"
                );
                emb
            }
            Err(e) => {
                error!("Embedding generation failed: {}", e);
                return Ok(error_from_embed_error(&e));
            }
        }
    };

    // Build the JSON response
    let response = EmbedResponse {
        size: embedding.len(),
        embedding,
    };
    let response_json = serde_json::to_string(&response)?;

    let resp = Response::builder()
        .status(200)
        .header("content-type", "application/json")
        .body(response_json.into())
        .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;

    Ok(resp)
}

/// Helper function to create error responses from EmbedError
fn error_from_embed_error(err: &EmbedError) -> Response<Body> {
    let status = err.status_code();
    let message = err.user_message();

    error_response(status, &message)
}

/// Helper function to create error responses
fn error_response(status: u16, message: &str) -> Response<Body> {
    let body = serde_json::to_string(&ErrorResponse {
        error: message.to_string(),
    })
    .unwrap_or_else(|_| r#"{"error":"Unknown error"}"#.to_string());

    // Safe response building with fallback
    Response::builder()
        .status(status)
        .header("content-type", "application/json")
        .body(body.into())
        .unwrap_or_else(|e| {
            error!("Failed to build error response: {}", e);
            // Absolute fallback - plain text error
            Response::builder()
                .status(500)
                .body(Body::from(r#"{"error":"Internal server error"}"#))
                .unwrap()
        })
}
