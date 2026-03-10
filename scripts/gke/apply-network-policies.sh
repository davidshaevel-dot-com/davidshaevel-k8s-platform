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

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Applying GKE network policies..."
kubectl apply -f "${REPO_ROOT}/manifests/cilium/gke-namespace-isolation.yaml"

echo ""
echo "Network policies:"
kubectl get networkpolicies -n davidshaevel-website
# CiliumNetworkPolicy CRDs are only available on AKS (ACNS). Skip on GKE.
if kubectl api-resources --api-group=cilium.io 2>/dev/null | grep -q ciliumnetworkpolicies; then
    kubectl get ciliumnetworkpolicies -n davidshaevel-website
fi

# Switch back to AKS context.
echo ""
echo "Switching back to AKS context..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing
