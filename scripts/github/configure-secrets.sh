#!/usr/bin/env bash
# Configure all required GitHub Actions secrets for davidshaevel-k8s-platform.
#
# Reads values from:
#   - .envrc (AZURE_SUBSCRIPTION, GCP_PROJECT, CLOUDFLARE_*, TELEPORT_*, PORTAINER_*, ACR_SP_*)
#   - scripts/github/azure-sp.json (created by create-azure-sp.sh, optional on re-run)
#   - scripts/github/gcp-sa-key.json (created by create-gcp-sa.sh, optional on re-run)
#
# Prerequisites:
#   - gh CLI installed and authenticated
#   - .envrc configured with all environment variables
#   - On first run: azure-sp.json and gcp-sa-key.json must exist
#   - On re-run: credential files are optional (existing secrets are kept)
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
ACR_SP_APP_ID="${ACR_SP_APP_ID:?Set ACR_SP_APP_ID in .envrc}"
ACR_SP_PASSWORD="${ACR_SP_PASSWORD:?Set ACR_SP_PASSWORD in .envrc}"

# Check for credential files (optional — only needed on first setup)
AZURE_SP_FILE="${SCRIPT_DIR}/azure-sp.json"
GCP_SA_FILE="${SCRIPT_DIR}/gcp-sa-key.json"
HAS_AZURE_SP=false
HAS_GCP_SA=false

if [ -f "${AZURE_SP_FILE}" ]; then
    HAS_AZURE_SP=true
fi

if [ -f "${GCP_SA_FILE}" ]; then
    HAS_GCP_SA=true
fi

echo "Configuring GitHub secrets for ${REPO}..."
echo ""

COUNT=0

# Set secrets from credential files (if present)
if [ "${HAS_AZURE_SP}" = true ]; then
    COUNT=$((COUNT + 1))
    echo "  [${COUNT}/10] AZURE_CREDENTIALS"
    gh secret set AZURE_CREDENTIALS --repo "${REPO}" < "${AZURE_SP_FILE}"
else
    echo "  [ skip ] AZURE_CREDENTIALS (azure-sp.json not found, keeping existing)"
fi

COUNT=$((COUNT + 1))
echo "  [${COUNT}/10] AZURE_SUBSCRIPTION"
echo "${AZURE_SUBSCRIPTION}" | gh secret set AZURE_SUBSCRIPTION --repo "${REPO}"

if [ "${HAS_GCP_SA}" = true ]; then
    COUNT=$((COUNT + 1))
    echo "  [${COUNT}/10] GCP_CREDENTIALS_JSON"
    gh secret set GCP_CREDENTIALS_JSON --repo "${REPO}" < "${GCP_SA_FILE}"
else
    echo "  [ skip ] GCP_CREDENTIALS_JSON (gcp-sa-key.json not found, keeping existing)"
fi

COUNT=$((COUNT + 1))
echo "  [${COUNT}/10] GCP_PROJECT"
echo "${GCP_PROJECT}" | gh secret set GCP_PROJECT --repo "${REPO}"

COUNT=$((COUNT + 1))
echo "  [${COUNT}/10] CLOUDFLARE_API_TOKEN"
echo "${CLOUDFLARE_API_TOKEN}" | gh secret set CLOUDFLARE_API_TOKEN --repo "${REPO}"

COUNT=$((COUNT + 1))
echo "  [${COUNT}/10] CLOUDFLARE_ZONE_ID"
echo "${CLOUDFLARE_ZONE_ID}" | gh secret set CLOUDFLARE_ZONE_ID --repo "${REPO}"

COUNT=$((COUNT + 1))
echo "  [${COUNT}/10] TELEPORT_ACME_EMAIL"
echo "${TELEPORT_ACME_EMAIL}" | gh secret set TELEPORT_ACME_EMAIL --repo "${REPO}"

COUNT=$((COUNT + 1))
echo "  [${COUNT}/10] PORTAINER_ADMIN_PASSWORD"
echo "${PORTAINER_ADMIN_PASSWORD}" | gh secret set PORTAINER_ADMIN_PASSWORD --repo "${REPO}"

COUNT=$((COUNT + 1))
echo "  [${COUNT}/10] ACR_SP_APP_ID"
echo "${ACR_SP_APP_ID}" | gh secret set ACR_SP_APP_ID --repo "${REPO}"

COUNT=$((COUNT + 1))
echo "  [${COUNT}/10] ACR_SP_PASSWORD"
echo "${ACR_SP_PASSWORD}" | gh secret set ACR_SP_PASSWORD --repo "${REPO}"

echo ""
echo "All secrets configured (${COUNT}/10 updated)."
echo ""
echo "Verify with: gh secret list --repo ${REPO}"
echo ""
echo "========================================"
echo "  REMINDER: Save to 1Password"
echo "========================================"
echo ""
echo "Create a 1Password item 'davidshaevel-k8s-platform GitHub Actions' with:"
if [ "${HAS_AZURE_SP}" = true ]; then
    echo "  - AZURE_CREDENTIALS: contents of ${AZURE_SP_FILE}"
fi
echo "  - AZURE_SUBSCRIPTION: ${AZURE_SUBSCRIPTION}"
if [ "${HAS_GCP_SA}" = true ]; then
    echo "  - GCP_CREDENTIALS_JSON: contents of ${GCP_SA_FILE}"
fi
echo "  - GCP_PROJECT: ${GCP_PROJECT}"
echo "  - CLOUDFLARE_API_TOKEN: (from .envrc)"
echo "  - CLOUDFLARE_ZONE_ID: ${CLOUDFLARE_ZONE_ID}"
echo "  - TELEPORT_ACME_EMAIL: ${TELEPORT_ACME_EMAIL}"
echo "  - PORTAINER_ADMIN_PASSWORD: (from .envrc)"
echo "  - ACR_SP_APP_ID: ${ACR_SP_APP_ID}"
echo "  - ACR_SP_PASSWORD: (from .envrc)"
if [ "${HAS_AZURE_SP}" = true ] || [ "${HAS_GCP_SA}" = true ]; then
    echo ""
    echo "After saving to 1Password, delete the credential files:"
    [ "${HAS_AZURE_SP}" = true ] && echo "  rm ${AZURE_SP_FILE}"
    [ "${HAS_GCP_SA}" = true ] && echo "  rm ${GCP_SA_FILE}"
fi
