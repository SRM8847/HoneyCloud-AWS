#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENRICHMENT_DIR="${SCRIPT_DIR}/enrichment"
OUTPUT_ZIP="${SCRIPT_DIR}/enrichment.zip"

cd "${ENRICHMENT_DIR}"
rm -rf package/
mkdir -p package/

# --break-system-packages required on Ubuntu 24.04 (PEP 668)
pip install -r requirements.txt -t ./package/ --quiet --break-system-packages

cp -r enrichers/ handler.py ./package/

cd package/
zip -r "${OUTPUT_ZIP}" . \
    --exclude "*.pyc" \
    --exclude "*/__pycache__/*"

echo "Built: $(du -sh "${OUTPUT_ZIP}")"
