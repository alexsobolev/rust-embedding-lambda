# Stage 1: Build the Rust binary for ARM64 using Debian Bookworm
FROM --platform=linux/arm64 rust:1.92-slim-bookworm AS builder

# Install build dependencies including lld linker for faster builds
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    lld \
    && rm -rf /var/lib/apt/lists/*

# Set ARM64 Graviton2-specific compiler optimizations
ENV RUSTFLAGS="-C target-cpu=neoverse-n1 -C target-feature=+neon"

WORKDIR /app

# Copy cargo config for ARM64 optimizations
COPY .cargo .cargo

# Copy manifests first for better layer caching
COPY Cargo.toml Cargo.lock ./

# Create a dummy main.rs to build dependencies
RUN mkdir src && \
    echo "fn main() {}" > src/main.rs && \
    cargo build --release && \
    rm -rf src

# Copy actual source code
COPY src ./src

# Build the real application
RUN touch src/main.rs && cargo build --release

# Stage 2: Download ONNX Runtime and Create Dummy Files
FROM --platform=linux/arm64 debian:bookworm-slim AS onnx-downloader

RUN apt-get update && apt-get install -y curl tar gzip && rm -rf /var/lib/apt/lists/*

# Download ONNX Runtime
ARG ORT_VERSION=1.22.0
RUN curl -L https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-linux-aarch64-${ORT_VERSION}.tgz \
    | tar xz -C /opt

# Create dummy /sys files in a temporary directory
RUN mkdir -p /tmp/fake_sys/sys/devices/system/cpu/ && \
    echo "0-1" > /tmp/fake_sys/sys/devices/system/cpu/possible && \
    echo "0-1" > /tmp/fake_sys/sys/devices/system/cpu/present

# Stage 3: Create the Lambda runtime image using Debian Bookworm
FROM --platform=linux/arm64 debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Copy ONNX Runtime library
COPY --from=onnx-downloader /opt/onnxruntime-linux-aarch64-*/lib/libonnxruntime.so* /usr/local/lib/
RUN ldconfig

# Set environment variables
ENV ORT_DYLIB_PATH=/usr/local/lib/libonnxruntime.so
ENV LAMBDA_TASK_ROOT=/var/task
ENV LAMBDA_RUNTIME_DIR=/var/runtime

# Copy dummy /sys files from downloader stage
COPY --from=onnx-downloader /tmp/fake_sys/ /

# Copy the compiled binary as bootstrap
COPY --from=builder /app/target/release/embedding-lambda /var/runtime/bootstrap

# Copy model files
COPY model/ /var/task/model/

WORKDIR /var/task

# Set the entrypoint to the bootstrap binary
ENTRYPOINT ["/var/runtime/bootstrap"]