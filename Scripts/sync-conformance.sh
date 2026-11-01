#!/usr/bin/env bash
# Copies the host API conformance cases from ahoge-extension into the test bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Tests/AhogeTests/Resources
curl -fsSL https://raw.githubusercontent.com/QuackyPROG/ahoge-extension/main/runtime/host-api-conformance.json \
  -o Tests/AhogeTests/Resources/host-api-conformance.json
echo "synced $(grep -c '"name"' Tests/AhogeTests/Resources/host-api-conformance.json) named cases"
