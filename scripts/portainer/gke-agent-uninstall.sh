#!/usr/bin/env bash
# Remove Portainer Agent from the GKE cluster.

source "$(dirname "$0")/../config.sh"
setup_logging "portainer-gke-agent-uninstall"

# Ensure kubectl context is pointing to GKE.
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ "${CURRENT_CONTEXT}" != *"${GKE_CLUSTER_NAME}"* ]]; then
    echo "Switching kubectl context to GKE cluster..."
    gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
        --project="${GCP_PROJECT}" \
        --zone="${GKE_ZONE}"
fi

echo "Uninstalling Portainer Agent from GKE cluster '${GKE_CLUSTER_NAME}'..."

kubectl delete -f "${PORTAINER_AGENT_MANIFEST}" --ignore-not-found=true

echo ""
echo "Portainer Agent uninstalled from GKE."
echo "Remember to remove the GKE environment from the Portainer UI."
