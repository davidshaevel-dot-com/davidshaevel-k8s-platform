#!/usr/bin/env bash
# Create a GKE cluster in the configured GCP project.
# Enables the GKE API if not already enabled.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-create"

if [[ "${CI:-}" != "true" ]]; then
    echo "Enabling GKE API on project '${GCP_PROJECT}'..."
    gcloud services enable container.googleapis.com --project="${GCP_PROJECT}" --quiet
fi

echo ""
echo "Creating GKE cluster '${GKE_CLUSTER_NAME}' in project '${GCP_PROJECT}'..."
echo "  Zone:         ${GKE_ZONE}"
echo "  Node count:   ${GKE_NODE_COUNT}"
echo "  Machine type: ${GKE_MACHINE_TYPE}"
echo ""

gcloud container clusters create "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}" \
    --num-nodes="${GKE_NODE_COUNT}" \
    --machine-type="${GKE_MACHINE_TYPE}"

echo ""
echo "GKE cluster '${GKE_CLUSTER_NAME}' created successfully."
echo "Run ./scripts/gke/credentials.sh to configure kubectl access."
