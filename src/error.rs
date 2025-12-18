use thiserror::Error;

/// Errors that can occur during embedding generation
#[derive(Error, Debug)]
pub enum EmbedError {
    /// Invalid embedding dimension requested
    #[error("Invalid embedding size: {size}. Must be one of: {valid:?}")]
    InvalidDimension {
        size: usize,
        valid: Vec<usize>,
    },

    /// Input sequence is too long
    #[error("Tokenized sequence exceeds maximum length of {max} tokens (got {got})")]
    SequenceTooLong {
        got: usize,
        max: usize,
    },

    /// Empty text input
    #[error("Text input cannot be empty")]
    EmptyInput,

    /// Text input exceeds maximum character limit
    #[error("Text exceeds maximum length of {max} characters (got {got})")]
    TextTooLong {
        got: usize,
        max: usize,
    },

    /// Failed to load tokenizer
    #[error("Failed to load tokenizer from {path}: {reason}")]
    TokenizerLoad {
        path: String,
        reason: String,
    },

    /// Tokenization failed
    #[error("Tokenization failed: {0}")]
    Tokenization(String),

    /// ONNX Runtime error
    #[error("ONNX Runtime error: {0}")]
    OnnxRuntime(#[from] ort::Error),

    /// Array shape mismatch
    #[error("Array shape error: {0}")]
    ArrayShape(#[from] ndarray::ShapeError),

    /// Mutex poisoned (concurrent access error)
    #[error("Internal error: shared resource poisoned")]
    MutexPoisoned,

    /// Internal server error (catch-all)
    #[error("Internal server error: {0}")]
    Internal(String),
}

impl EmbedError {
    /// Returns true if this error should be reported as a client error (4xx)
    pub fn is_client_error(&self) -> bool {
        matches!(
            self,
            EmbedError::InvalidDimension { .. }
                | EmbedError::SequenceTooLong { .. }
                | EmbedError::EmptyInput
                | EmbedError::TextTooLong { .. }
        )
    }

    /// Get the HTTP status code for this error
    pub fn status_code(&self) -> u16 {
        if self.is_client_error() {
            400
        } else {
            500
        }
    }

    /// Get a user-friendly error message (sanitized for production)
    pub fn user_message(&self) -> String {
        match self {
            // Client errors - show detailed message
            EmbedError::InvalidDimension { size, valid } => {
                format!("Invalid embedding size: {}. Must be one of: {:?}", size, valid)
            }
            EmbedError::SequenceTooLong { got, max } => {
                format!("Text is too long: {} tokens (max: {})", got, max)
            }
            EmbedError::EmptyInput => "Text input cannot be empty".to_string(),
            EmbedError::TextTooLong { got, max } => {
                format!("Text is too long: {} characters (max: {})", got, max)
            }
            EmbedError::Tokenization(msg) => {
                format!("Failed to process text: {}", msg)
            }

            // Server errors - generic message in production
            _ => {
                if cfg!(debug_assertions) {
                    // Development: show full error
                    self.to_string()
                } else {
                    // Production: generic message
                    "An internal error occurred while processing your request".to_string()
                }
            }
        }
    }
}
