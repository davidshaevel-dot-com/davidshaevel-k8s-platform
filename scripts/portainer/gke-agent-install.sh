#!/usr/bin/env bash
# Install Portainer Agent on the GKE cluster via kubectl manifest.
# The agent runs with a LoadBalancer so the AKS-hosted Portainer server can connect to it.
# Reference: https://docs.portainer.io/admin/environments/add/kubernetes/agent

source "$(dirname "$0")/../config.sh"
setup_logging "portainer-gke-agent-install"

# Ensure kubectl context is pointing to GKE.
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ "${CURRENT_CONTEXT}" != *"${GKE_CLUSTER_NAME}"* ]]; then
    echo "Switching kubectl context to GKE cluster..."
    gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
        --project="${GCP_PROJECT}" \
        --zone="${GKE_ZONE}"
fi

echo "Installing Portainer Agent on GKE cluster '${GKE_CLUSTER_NAME}'..."
echo ""

kubectl apply -f "${PORTAINER_AGENT_MANIFEST}"

echo ""
echo "Waiting for agent deployment to be ready..."
kubectl rollout status deployment/portainer-agent -n portainer --timeout=2m

echo ""
echo "Waiting for LoadBalancer external IP..."
if kubectl wait -n portainer --for=jsonpath='{.status.loadBalancer.ingress}' service/portainer-agent --timeout=3m; then
    AGENT_IP=$(kubectl get svc portainer-agent -n portainer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo ""
    echo "Portainer Agent LoadBalancer IP: ${AGENT_IP}"
    echo ""
    echo "Next steps:"
    echo "  1. In the Portainer UI, go to Environments > Add Environment"
    echo "  2. Select 'Agent' and enter: ${AGENT_IP}:9001"
    echo "  3. Name it 'GKE'"
else
    echo "LoadBalancer IP not assigned after 3 minutes."
    echo "Run: kubectl get svc -n portainer -w"
fi
