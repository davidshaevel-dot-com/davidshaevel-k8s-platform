#!/usr/bin/env bash
# Create an Azure service principal for GitHub Actions.
# The SP gets Contributor role scoped to:
#   - k8s-developer-platform-rg (AKS cluster, DNS zone)
#   - MC_k8s-developer-platform-rg_k8s-developer-platform-aks_eastus (AKS-managed infra: public IPs, etc.)
#
# Output: Writes the SP credentials JSON to azure-sp.json (gitignored).
# This file is used by configure-secrets.sh to set the AZURE_CREDENTIALS secret.
#
# Prerequisites:
#   - az CLI installed and logged in
#   - AZURE_SUBSCRIPTION set in .envrc or environment
#
# Usage: ./scripts/github/create-azure-sp.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source .envrc for AZURE_SUBSCRIPTION
if [ -f "${REPO_ROOT}/.envrc" ]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.envrc"
fi

AZURE_SUBSCRIPTION="${AZURE_SUBSCRIPTION:?Set AZURE_SUBSCRIPTION in .envrc or environment}"
RESOURCE_GROUP="k8s-developer-platform-rg"
MC_RESOURCE_GROUP="MC_k8s-developer-platform-rg_k8s-developer-platform-aks_eastus"
SP_NAME="github-k8s-platform"
OUTPUT_FILE="${SCRIPT_DIR}/azure-sp.json"

echo "Creating Azure service principal '${SP_NAME}'..."
echo "  Subscription: ${AZURE_SUBSCRIPTION}"
echo "  Scope: ${RESOURCE_GROUP}, ${MC_RESOURCE_GROUP}"
echo ""

# Get subscription ID
SUB_ID=$(az account show --subscription "${AZURE_SUBSCRIPTION}" --query id -o tsv)

az ad sp create-for-rbac \
    --name "${SP_NAME}" \
    --role contributor \
    --scopes "/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}" \
              "/subscriptions/${SUB_ID}/resourceGroups/${MC_RESOURCE_GROUP}" \
    --json-auth > "${OUTPUT_FILE}"

echo ""
echo "Service principal created. Credentials written to:"
echo "  ${OUTPUT_FILE}"
echo ""
echo "IMPORTANT: This file contains secrets. It is gitignored."
echo "Save these credentials to 1Password before deleting the file."
