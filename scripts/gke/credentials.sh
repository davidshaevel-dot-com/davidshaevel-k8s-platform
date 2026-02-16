#!/usr/bin/env bash
# Fetch kubeconfig credentials for the GKE cluster.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-credentials"

echo "Fetching credentials for GKE cluster '${GKE_CLUSTER_NAME}'..."

gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}"

echo ""
echo "kubectl context set to GKE cluster '${GKE_CLUSTER_NAME}'."
echo ""
kubectl get nodes
