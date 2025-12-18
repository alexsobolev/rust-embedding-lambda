pub mod embedder;
pub mod error;
pub mod http_handler;

use embedder::Embedder;
use http_handler::function_handler;
use lambda_http::{run, service_fn, tracing, Error};
use std::sync::{Arc, Mutex};

#[tokio::main]
async fn main() -> Result<(), Error> {
    // Initialize ONNX Runtime global environment and keep it in memory for program lifetime
    // This must be called before creating any sessions to register the DefaultLogger
    // The environment remains active for the entire program execution
    ort::init().with_name("embedding-lambda").commit()?;

    // Initialize tracing for CloudWatch logs
    tracing::init_default_subscriber();

    // Initialize the Embedder once during cold start.
    // This loads the ONNX model and tokenizer into memory.
    let embedder = Embedder::new("model/model_quantized.onnx", "model/tokenizer.json")
        .map_err(|e| {
            tracing::error!("Failed to initialize embedder: {}", e);
            Box::new(e) as Box<dyn std::error::Error + Send + Sync>
        })?;

    // Wrap in Arc<Mutex> to share across handler invocations
    // Mutex required: ONNX Runtime Rust bindings need &mut for session.run()
    let embedder = Arc::new(Mutex::new(embedder));

    // Start the Lambda runtime.
    // Each incoming request will clone the Arc and call function_handler.
    run(service_fn(move |event| {
        let embedder = embedder.clone();
        function_handler(embedder, event)
    }))
    .await
}
