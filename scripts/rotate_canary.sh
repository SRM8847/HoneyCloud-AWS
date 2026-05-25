#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
TF_DIR="${REPO_ROOT}/terraform"
TFVARS="${TF_DIR}/terraform.tfvars"

echo "[1/4] Incrementing rotation counter..."
CURRENT=$(awk -F'=' '/canary_key_rotation_count/{gsub(/ /,"",$2); print $2}' "${TFVARS}")
NEW=$((CURRENT + 1))
sed -i "s/canary_key_rotation_count = ${CURRENT}/canary_key_rotation_count = ${NEW}/" "${TFVARS}"
echo "  Rotation count: ${CURRENT} -> ${NEW}"

echo "[2/4] Rebuilding Lambda package..."
bash "${REPO_ROOT}/lambda/build.sh"

echo "[3/4] Applying Terraform..."
cd "${TF_DIR}"
terraform apply -auto-approve

echo "[4/4] New canary credentials:"
echo "================================================"
echo "  Access Key ID : $(terraform output -raw canary_access_key)"
echo "  Secret Key    : $(terraform output -raw canary_secret_key)"
echo "================================================"
echo "ACTION REQUIRED: Update the GitHub Gist with new credentials."
