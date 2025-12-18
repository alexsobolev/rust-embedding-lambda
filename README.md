# Embedding Lambda

A high-performance, cost-effective AWS Lambda function written in Rust that generates text embeddings using **EmbeddingGemma**.

This repository was created as a companion project for the article [EmbeddingGemma Inference on AWS Lambda: Rust, Quantization, and Graviton Performance](https://sobolev.substack.com/p/embeddinggemma-inference-on-aws-lambda).

## Overview

This project provides a serverless REST API for generating semantic text embeddings. By running inference locally inside AWS Lambda using ONNX Runtime, it offers a private and predictable alternative to external embedding APIs like OpenAI or Google Bedrock.

### Key Features

- **Blazing Fast**: Leverages Rust and ARM64 (Graviton2) optimizations for minimal latency and cold starts.
- **Matryoshka Representation Learning**: Supports variable embedding dimensions (128, 256, 512, or 768) without retraining.
- **Cost-Effective**: Billed per request, not per token. Significant savings for long-form content.
- **Privacy-First**: Data never leaves your AWS VPC.
- **ONNX Optimized**: Uses `ort` (ONNX Runtime) with vectorized mean pooling for efficient inference.

## Architecture

- **Runtime**: Rust 1.92+ on AWS Lambda (ARM64).
- **Core Engine**: `ort` (ONNX Runtime) bindings.
- **Model**: `EmbeddingGemma` (Quantized).
- **Format**: `provided.al2023-arm64` custom runtime via Docker container.

## Project Structure

```text
embedding-lambda/
├── src/
│   ├── main.rs          # Lambda entry point and lifecycle management
│   ├── embedder.rs      # ML inference logic and pooling
│   └── http_handler.rs  # API request/response processing
├── scripts/             # Deployment and utility scripts
├── model/               # model_quantized.onnx and tokenizer.json
└── Dockerfile           # Multi-stage ARM64 build configuration
```

## Getting Started

### Prerequisites

- [Rust](https://www.rust-lang.org/tools/install)
- [Cargo Lambda](https://www.cargo-lambda.info/guide/installation.html)
- [Docker](https://www.docker.com/)

### Model Setup

Before running or deploying, you must download the model and tokenizer files into the `model/` directory:

1.  **Download from Hugging Face**:
    Visit [onnx-community/embeddinggemma-300m-ONNX](https://huggingface.co/onnx-community/embeddinggemma-300m-ONNX) and download the following files:
    - `onnx/model_quantized.onnx` (save as `model/model_quantized.onnx`)
    - `onnx/model_quantized.onnx_data` (save as `model/model_quantized.onnx_data`)
    - `tokenizer.json` (save as `model/tokenizer.json`)

Alternatively, use `huggingface-cli`:
```bash
mkdir -p model
huggingface-cli download onnx-community/embeddinggemma-300m-ONNX onnx/model_quantized.onnx --local-dir model --local-dir-use-symlinks False
huggingface-cli download onnx-community/embeddinggemma-300m-ONNX onnx/model_quantized.onnx_data --local-dir model --local-dir-use-symlinks False
huggingface-cli download onnx-community/embeddinggemma-300m-ONNX tokenizer.json --local-dir model --local-dir-use-symlinks False
mv model/onnx/model_quantized.onnx model/ && mv model/onnx/model_quantized.onnx_data model/ && rm -rf model/onnx
```

### Local Development

1. **Start the local Lambda server**:
   ```bash
   cargo lambda watch
   ```

2. **Invoke the function**:
   ```bash
   cargo lambda invoke --data-file scripts/test_data_short.json
   ```

3. **Direct HTTP Call**:
   ```bash
   curl -X POST http://localhost:9000 \
     -H "Content-Type: application/json" \
     -d '{"text": "Rust is amazing", "size": 256}'
   ```

## Deployment

### Quick Setup

For a complete setup from scratch (IAM roles, ECR, and Lambda function), run the consolidated install script:

```bash
./scripts/install.sh
```

### Daily Deployment

To update existing code and infrastructure:
```bash
./scripts/deploy_function.sh
```

## License

This project is licensed under the MIT License.