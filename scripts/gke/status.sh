#!/usr/bin/env bash
# Show GKE cluster status.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-status"

echo "=== GKE Cluster Info ==="
gcloud container clusters describe "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}" \
    --format="table(name, status, currentMasterVersion, currentNodeCount, location)" \
    2>/dev/null || echo "Cluster '${GKE_CLUSTER_NAME}' not found."

echo ""
echo "=== Node Pool ==="
gcloud container node-pools list \
    --cluster="${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}" \
    --format="table(name, config.machineType, initialNodeCount, status)" \
    2>/dev/null || echo "No node pools found."
