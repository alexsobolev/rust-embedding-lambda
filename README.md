# Embedding Lambda

A high-performance, cost-effective AWS Lambda function written in Rust that generates text embeddings using **EmbeddingGemma**.

This repository was created as a companion project for the article on implementing serverless embeddings with Rust and AWS Lambda.

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

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details (if applicable).
