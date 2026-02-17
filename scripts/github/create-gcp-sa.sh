#!/usr/bin/env bash
# Create a GCP service account for GitHub Actions.
# The SA gets roles/container.admin on the project for GKE cluster management.
#
# Output: Writes the SA key JSON to gcp-sa-key.json (gitignored).
# This file is used by configure-secrets.sh to set the GCP_CREDENTIALS_JSON secret.
#
# Prerequisites:
#   - gcloud CLI installed and authenticated
#   - GCP_PROJECT set in .envrc or environment
#
# Usage: ./scripts/github/create-gcp-sa.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source .envrc for GCP_PROJECT
if [ -f "${REPO_ROOT}/.envrc" ]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.envrc"
fi

GCP_PROJECT="${GCP_PROJECT:?Set GCP_PROJECT in .envrc or environment}"
SA_NAME="github-portainer"
SA_EMAIL="${SA_NAME}@${GCP_PROJECT}.iam.gserviceaccount.com"
OUTPUT_FILE="${SCRIPT_DIR}/gcp-sa-key.json"

echo "Creating GCP service account '${SA_NAME}'..."
echo "  Project: ${GCP_PROJECT}"
echo ""

# Create service account (ignore error if it already exists)
gcloud iam service-accounts create "${SA_NAME}" \
    --project="${GCP_PROJECT}" \
    --display-name="GitHub Actions - Portainer" 2>/dev/null || echo "Service account already exists."

# Grant container.admin role (GKE cluster CRUD)
echo "Granting roles/container.admin..."
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/container.admin" \
    --condition=None \
    --quiet

# Grant iam.serviceAccountUser role (required to use default compute SA when creating GKE clusters)
echo "Granting roles/iam.serviceAccountUser..."
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None \
    --quiet

# Create key
echo ""
echo "Creating service account key..."
gcloud iam service-accounts keys create "${OUTPUT_FILE}" \
    --iam-account="${SA_EMAIL}"

echo ""
echo "Service account key written to:"
echo "  ${OUTPUT_FILE}"
echo ""
echo "IMPORTANT: This file contains secrets. It is gitignored."
echo "Save these credentials to 1Password before deleting the file."
