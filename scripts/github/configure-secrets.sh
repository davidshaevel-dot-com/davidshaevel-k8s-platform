#!/usr/bin/env bash
# Configure all required GitHub Actions secrets for davidshaevel-k8s-platform.
#
# Reads values from:
#   - .envrc (AZURE_SUBSCRIPTION, GCP_PROJECT, CLOUDFLARE_*, TELEPORT_*, PORTAINER_*)
#   - scripts/github/azure-sp.json (created by create-azure-sp.sh)
#   - scripts/github/gcp-sa-key.json (created by create-gcp-sa.sh)
#
# Prerequisites:
#   - gh CLI installed and authenticated
#   - .envrc configured with all environment variables
#   - azure-sp.json exists (run create-azure-sp.sh first)
#   - gcp-sa-key.json exists (run create-gcp-sa.sh first)
#
# Usage: ./scripts/github/configure-secrets.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO="davidshaevel-dot-com/davidshaevel-k8s-platform"

# Source .envrc
if [ -f "${REPO_ROOT}/.envrc" ]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.envrc"
else
    echo "Error: .envrc not found at ${REPO_ROOT}/.envrc"
    exit 1
fi

# Validate required env vars
AZURE_SUBSCRIPTION="${AZURE_SUBSCRIPTION:?Set AZURE_SUBSCRIPTION in .envrc}"
GCP_PROJECT="${GCP_PROJECT:?Set GCP_PROJECT in .envrc}"
CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN in .envrc}"
CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:?Set CLOUDFLARE_ZONE_ID in .envrc}"
TELEPORT_ACME_EMAIL="${TELEPORT_ACME_EMAIL:?Set TELEPORT_ACME_EMAIL in .envrc}"
PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:?Set PORTAINER_ADMIN_PASSWORD in .envrc}"

# Validate credential files
AZURE_SP_FILE="${SCRIPT_DIR}/azure-sp.json"
GCP_SA_FILE="${SCRIPT_DIR}/gcp-sa-key.json"

if [ ! -f "${AZURE_SP_FILE}" ]; then
    echo "Error: ${AZURE_SP_FILE} not found."
    echo "Run ./scripts/github/create-azure-sp.sh first."
    exit 1
fi

if [ ! -f "${GCP_SA_FILE}" ]; then
    echo "Error: ${GCP_SA_FILE} not found."
    echo "Run ./scripts/github/create-gcp-sa.sh first."
    exit 1
fi

echo "Configuring GitHub secrets for ${REPO}..."
echo ""

# Set secrets
echo "  [1/8] AZURE_CREDENTIALS"
gh secret set AZURE_CREDENTIALS --repo "${REPO}" < "${AZURE_SP_FILE}"

echo "  [2/8] AZURE_SUBSCRIPTION"
echo "${AZURE_SUBSCRIPTION}" | gh secret set AZURE_SUBSCRIPTION --repo "${REPO}"

echo "  [3/8] GCP_CREDENTIALS_JSON"
gh secret set GCP_CREDENTIALS_JSON --repo "${REPO}" < "${GCP_SA_FILE}"

echo "  [4/8] GCP_PROJECT"
echo "${GCP_PROJECT}" | gh secret set GCP_PROJECT --repo "${REPO}"

echo "  [5/8] CLOUDFLARE_API_TOKEN"
echo "${CLOUDFLARE_API_TOKEN}" | gh secret set CLOUDFLARE_API_TOKEN --repo "${REPO}"

echo "  [6/8] CLOUDFLARE_ZONE_ID"
echo "${CLOUDFLARE_ZONE_ID}" | gh secret set CLOUDFLARE_ZONE_ID --repo "${REPO}"

echo "  [7/8] TELEPORT_ACME_EMAIL"
echo "${TELEPORT_ACME_EMAIL}" | gh secret set TELEPORT_ACME_EMAIL --repo "${REPO}"

echo "  [8/8] PORTAINER_ADMIN_PASSWORD"
echo "${PORTAINER_ADMIN_PASSWORD}" | gh secret set PORTAINER_ADMIN_PASSWORD --repo "${REPO}"

echo ""
echo "All 8 secrets configured."
echo ""
echo "Verify with: gh secret list --repo ${REPO}"
echo ""
echo "========================================"
echo "  REMINDER: Save to 1Password"
echo "========================================"
echo ""
echo "Create a 1Password item 'davidshaevel-k8s-platform GitHub Actions' with:"
echo "  - AZURE_CREDENTIALS: contents of ${AZURE_SP_FILE}"
echo "  - AZURE_SUBSCRIPTION: ${AZURE_SUBSCRIPTION}"
echo "  - GCP_CREDENTIALS_JSON: contents of ${GCP_SA_FILE}"
echo "  - GCP_PROJECT: ${GCP_PROJECT}"
echo "  - CLOUDFLARE_API_TOKEN: (from .envrc)"
echo "  - CLOUDFLARE_ZONE_ID: ${CLOUDFLARE_ZONE_ID}"
echo "  - TELEPORT_ACME_EMAIL: ${TELEPORT_ACME_EMAIL}"
echo "  - PORTAINER_ADMIN_PASSWORD: (from .envrc)"
echo ""
echo "After saving to 1Password, delete the credential files:"
echo "  rm ${AZURE_SP_FILE} ${GCP_SA_FILE}"
