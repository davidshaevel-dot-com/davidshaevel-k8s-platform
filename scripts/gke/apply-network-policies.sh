#!/usr/bin/env bash
# Apply Cilium network policies on GKE for the davidshaevel-website namespace.
#
# This script is called by gke/start.sh on every GKE rebuild.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-apply-network-policies"

# Switch to GKE context.
echo "Switching to GKE context..."
gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}"

echo "Applying GKE network policies..."
kubectl apply -f manifests/cilium/gke-namespace-isolation.yaml

echo ""
echo "Network policies:"
kubectl get networkpolicies -n davidshaevel-website
kubectl get ciliumnetworkpolicies -n davidshaevel-website

# Switch back to AKS context.
echo ""
echo "Switching back to AKS context..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing
