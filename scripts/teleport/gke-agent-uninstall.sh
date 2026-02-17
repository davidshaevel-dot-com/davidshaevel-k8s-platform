#!/usr/bin/env bash
# Remove the Teleport kube agent from the GKE cluster.

source "$(dirname "$0")/../config.sh"
setup_logging "teleport-gke-agent-uninstall"

TELEPORT_NAMESPACE="teleport-cluster"

# Ensure kubectl context is pointing to GKE.
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ "${CURRENT_CONTEXT}" != *"${GKE_CLUSTER_NAME}"* ]]; then
    echo "Switching kubectl context to GKE cluster..."
    gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
        --project="${GCP_PROJECT}" \
        --zone="${GKE_ZONE}"
fi

echo "Uninstalling Teleport kube agent from GKE cluster '${GKE_CLUSTER_NAME}'..."

if helm status teleport-agent -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    helm uninstall teleport-agent -n "${TELEPORT_NAMESPACE}"
    echo "Teleport agent uninstalled from GKE."
else
    echo "Teleport agent Helm release not found on GKE."
fi

echo ""
echo "Cleaning up namespace..."
kubectl delete namespace "${TELEPORT_NAMESPACE}" --ignore-not-found=true

echo ""
echo "Teleport agent removed from GKE."
echo "The cluster may take a few minutes to disappear from 'tctl kube ls'."
