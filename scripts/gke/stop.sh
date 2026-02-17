#!/usr/bin/env bash
# Stop (delete) the GKE cluster. GKE does not support stop/start like AKS,
# so this deletes the cluster. Use gke/start.sh to rebuild from scratch.
# Unlike gke/delete.sh, this script skips the interactive confirmation prompt
# so it can be called non-interactively (e.g., from Claude Code).

source "$(dirname "$0")/../config.sh"
setup_logging "gke-stop"

echo "GKE does not support stop/start. This will DELETE the cluster."
echo "Use ./scripts/gke/start.sh to rebuild it later."
echo ""
echo "Deleting GKE cluster '${GKE_CLUSTER_NAME}'..."

gcloud container clusters delete "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}" \
    --quiet

echo "Cluster '${GKE_CLUSTER_NAME}' deleted. Cost is now $0."
