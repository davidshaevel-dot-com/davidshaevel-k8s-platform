#!/usr/bin/env bash
# Delete the GKE cluster. Cost drops to $0 after deletion.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-delete"

echo "WARNING: This will delete the GKE cluster '${GKE_CLUSTER_NAME}' in project '${GCP_PROJECT}'."
echo ""

read -r -p "Type '${GKE_CLUSTER_NAME}' to confirm deletion: " confirm
if [ "${confirm}" != "${GKE_CLUSTER_NAME}" ]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo "Deleting GKE cluster '${GKE_CLUSTER_NAME}'..."

gcloud container clusters delete "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}" \
    --quiet

echo "Cluster '${GKE_CLUSTER_NAME}' deleted. Cost is now $0."
