#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
BENCH_DIR="$(mktemp -d -t sicgo-bench)"
trap 'rm -rf "$BENCH_DIR"' EXIT
xcrun swiftc -O -parse-as-library Sources/SicGo/Drawing.swift Tests/Performance.swift -o "$BENCH_DIR/benchmark"
"$BENCH_DIR/benchmark"
