#!/bin/bash
set -e

# Simple benchmark script using cargo lambda invoke
# Tests different embedding sizes and text lengths

# Test data files
mkdir -p /tmp/benchmark_data

# Create test payloads
cat > /tmp/benchmark_data/short_256.json << 'EOF'
{"text": "Rust on AWS Lambda is fast", "size": 256}
EOF

cat > /tmp/benchmark_data/medium_256.json << 'EOF'
{"text": "Rust on AWS Lambda provides excellent performance for machine learning workloads. The combination of Rust's zero-cost abstractions and AWS Lambda's serverless architecture creates a powerful platform for deploying ML models. This text is designed to test medium-length input processing and tokenization performance.", "size": 256}
EOF

cat > /tmp/benchmark_data/long_768.json << 'EOF'
{"text": "Rust on AWS Lambda provides excellent performance for machine learning workloads. The combination of Rust's zero-cost abstractions and AWS Lambda's serverless architecture creates a powerful platform for deploying ML models. ONNX Runtime enables efficient inference with optimized operators for ARM64 Graviton processors. Matryoshka representation learning allows flexible embedding dimensions, supporting 128, 256, 512, and 768-dimensional vectors from a single model. The quantized model reduces memory footprint while maintaining high accuracy. Mean pooling over token embeddings creates document-level representations. L2 normalization enables efficient cosine similarity computation through dot products. This longer text tests the system's ability to handle more complex tokenization and inference scenarios with hundreds of tokens.", "size": 768}
EOF

echo "========================================="
echo "Embedding Lambda Simple Benchmark"
echo "========================================="
echo ""

# Function to run benchmark
run_test() {
    local test_file=$1
    local test_name=$2
    local runs=5

    echo "Testing: $test_name"
    echo "  Running $runs iterations..."

    local times=()
    for i in $(seq 1 $runs); do
        local start=$(gdate +%s%3N 2>/dev/null || date +%s%3N)
        cargo lambda invoke --data-file "$test_file" > /dev/null 2>&1
        local end=$(gdate +%s%3N 2>/dev/null || date +%s%3N)
        local duration=$((end - start))
        times+=($duration)
        echo "    Run $i: ${duration}ms"
    done

    # Calculate average
    local sum=0
    for time in "${times[@]}"; do
        sum=$((sum + time))
    done
    local avg=$((sum / ${#times[@]}))

    echo "  Average: ${avg}ms"
    echo ""
}

echo "Building release binary..."
cargo build --release

echo ""
echo "Running benchmarks..."
echo ""

run_test "/tmp/benchmark_data/short_256.json" "Short text, 256 dims"
run_test "/tmp/benchmark_data/medium_256.json" "Medium text, 256 dims"
run_test "/tmp/benchmark_data/long_768.json" "Long text, 768 dims"

echo "========================================="
echo "Benchmark Complete!"
echo "========================================="
