use crate::error::EmbedError;
use ort::{session::Session, value::Value};
use tokenizers::Tokenizer;

/// Valid embedding dimensions for Matryoshka truncation
pub const VALID_DIMENSIONS: [usize; 4] = [768, 512, 256, 128];

/// Maximum sequence length in tokens
/// Prevents excessive memory usage and processing time
const MAX_SEQUENCE_LENGTH: usize = 8192;

/// Handles text embedding using ONNX Runtime.
///
/// The Embedder loads an ONNX model and tokenizer, then provides
/// a simple interface to convert text into vector embeddings.
pub struct Embedder {
    session: Session,
    tokenizer: Tokenizer,
}

impl Embedder {
    /// Creates a new Embedder instance.
    ///
    /// # Arguments
    /// * `model_path` - Path to the ONNX model file (e.g., "model/model_quantized.onnx")
    /// * `tokenizer_path` - Path to the tokenizer JSON file (e.g., "model/tokenizer.json")
    ///
    /// # Note
    /// The ONNX model uses external data storage. Both `model_quantized.onnx` and
    /// `model_quantized.onnx_data` must be present in the same directory.
    /// ONNX Runtime automatically loads the external data file.
    pub fn new(
        model_path: &str,
        tokenizer_path: &str,
    ) -> Result<Self, EmbedError> {
        // Initialize ONNX Runtime session with optimization level Basic (Level 1)
        // This enables standard graph optimizations for better performance on ARM64.
        let session = Session::builder()?
            .with_optimization_level(ort::session::builder::GraphOptimizationLevel::Level1)?
            .with_intra_threads(1)? // Optimal for Q4 model: single thread reduces overhead
            .commit_from_file(model_path)?;

        // Load the Hugging Face tokenizer from JSON
        let tokenizer = Tokenizer::from_file(tokenizer_path)
            .map_err(|e| EmbedError::TokenizerLoad {
                path: tokenizer_path.to_string(),
                reason: e.to_string(),
            })?;

        Ok(Self { session, tokenizer })
    }

    /// Tokenizes input text with the document prompt format.
    ///
    /// EmbeddingGemma expects a specific prompt template:
    /// "title: none | text: {text}"
    fn tokenize(
        &self,
        text: &str,
    ) -> Result<(Vec<i64>, Vec<i64>), EmbedError> {
        // Apply the prompt template
        let formatted = format!("title: none | text: {}", text);

        // Tokenize with special tokens (e.g., [CLS], [SEP])
        let encoding = self
            .tokenizer
            .encode(formatted, true)
            .map_err(|e| EmbedError::Tokenization(e.to_string()))?;

        // Convert to i64 as required by ONNX Runtime
        let input_ids: Vec<i64> = encoding.get_ids().iter().map(|&id| id as i64).collect();
        let attention_mask: Vec<i64> = encoding
            .get_attention_mask()
            .iter()
            .map(|&m| m as i64)
            .collect();

        Ok((input_ids, attention_mask))
    }

    /// Generates an embedding vector for the given text.
    ///
    /// # Arguments
    /// * `text` - The input text to embed
    /// * `size` - Output dimension: 768, 512, 256, or 128 (Matryoshka truncation)
    ///
    /// # Returns
    /// A normalized embedding vector of the requested dimension
    pub fn embed(
        &mut self,
        text: &str,
        size: usize,
    ) -> Result<Vec<f32>, EmbedError> {
        // Validate the requested dimension
        if !VALID_DIMENSIONS.contains(&size) {
            return Err(EmbedError::InvalidDimension {
                size,
                valid: VALID_DIMENSIONS.to_vec(),
            });
        }

        // Step 1: Tokenize the input
        let (input_ids, attention_mask) = self.tokenize(text)?;
        let seq_len = input_ids.len();

        // Validate sequence length
        if seq_len > MAX_SEQUENCE_LENGTH {
            return Err(EmbedError::SequenceTooLong {
                got: seq_len,
                max: MAX_SEQUENCE_LENGTH,
            });
        }

        // Step 2: Prepare inputs as 2D tensors with shape [batch_size=1, seq_len]
        let shape = vec![1, seq_len];

        // Step 3: Run inference
        let outputs = self.session.run(ort::inputs![
            "input_ids" => Value::from_array((shape.clone(), input_ids))?,
            "attention_mask" => Value::from_array((shape, attention_mask.clone()))?,
        ])?;

        // Step 4: Extract the output tensor
        // The model outputs last_hidden_state with shape [batch_size, seq_len, hidden_dim]
        let (output_shape, output_data) = outputs[0].try_extract_tensor::<f32>()?;
        let batch_size = output_shape[0] as usize;
        let seq_len_out = output_shape[1] as usize;
        let hidden_dim = output_shape[2] as usize;

        // Convert to ArrayView3 for mean_pooling
        let output_view =
            ndarray::ArrayView3::from_shape((batch_size, seq_len_out, hidden_dim), output_data)?;

        // Step 5: Apply mean pooling over token embeddings
        let embedding = Self::mean_pooling(&output_view, &attention_mask)?;

        // Step 6: Truncate to requested dimension (Matryoshka)
        let truncated: Vec<f32> = embedding.into_iter().take(size).collect();

        // Step 7: L2 normalize the final embedding
        // Re-normalization after truncation is important for correct similarity scores
        let normalized = Self::normalize(&truncated);

        Ok(normalized)
    }

    /// Applies mean pooling to token embeddings.
    ///
    /// Mean pooling averages the embeddings of all non-padding tokens.
    /// The attention mask is used to exclude padding tokens from the average.
    /// Uses vectorized ndarray operations for optimal performance.
    fn mean_pooling(
        hidden_states: &ndarray::ArrayView3<f32>,
        attention_mask: &[i64],
    ) -> Result<Vec<f32>, EmbedError> {
        use ndarray::Axis;

        // hidden_states: [batch=1, seq_len, hidden_dim]
        // Remove batch dimension: [seq_len, hidden_dim]
        let states_2d = hidden_states.index_axis(Axis(0), 0);

        // Convert mask to f32 and create array
        let mask_f32: Vec<f32> = attention_mask.iter().map(|&x| x as f32).collect();
        let mask_1d = ndarray::Array1::from(mask_f32);

        // Count non-padding tokens (do this before consuming mask_1d)
        let count = mask_1d.sum();

        // Reshape to [seq_len, 1] for broadcasting
        let mask_col = mask_1d.insert_axis(Axis(1)); // Shape: [seq_len, 1]

        // Broadcast multiply: each token embedding is scaled by its mask value
        // This zeros out padding tokens
        let masked_states = &states_2d * &mask_col;

        // Sum along sequence axis: [seq_len, hidden_dim] -> [hidden_dim]
        let sum = masked_states.sum_axis(Axis(0));

        // Compute mean (avoid division by zero)
        let mean = if count > 0.0 { sum / count } else { sum };

        Ok(mean.to_vec())
    }

    /// Applies L2 normalization to the embedding vector.
    ///
    /// Normalized embeddings allow using dot product instead of cosine similarity,
    /// which is computationally cheaper for similarity searches.
    fn normalize(embedding: &[f32]) -> Vec<f32> {
        let norm: f32 = embedding.iter().map(|x| x * x).sum::<f32>().sqrt();

        if norm > 0.0 {
            embedding.iter().map(|x| x / norm).collect()
        } else {
            embedding.to_vec()
        }
    }
}
