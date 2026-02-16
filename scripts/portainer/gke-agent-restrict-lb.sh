#!/usr/bin/env bash
# Restrict the GKE Portainer Agent LoadBalancer to accept traffic only from the AKS egress IP.
# This runs AFTER agent registration so Portainer can initially reach the agent during setup.
#
# GKE auto-creates firewall rules for LoadBalancer services that allow 0.0.0.0/0.
# Setting loadBalancerSourceRanges overrides that to only the AKS egress IP.
#
# Prerequisites:
#   - GKE Portainer Agent installed with LoadBalancer
#   - AKS credentials configured (for egress IP lookup)
#   - GKE credentials configured (for kubectl patch)
#
# Usage: ./scripts/portainer/gke-agent-restrict-lb.sh

source "$(dirname "$0")/../config.sh"
setup_logging "portainer-gke-agent-restrict-lb"

echo "Getting AKS egress IP for LoadBalancer source restriction..."
AKS_EGRESS_ID=$(az aks show \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --query "networkProfile.loadBalancerProfile.effectiveOutboundIPs[0].id" \
    --output tsv)
AKS_PUBLIC_IP=$(az network public-ip show --ids "${AKS_EGRESS_ID}" --query "ipAddress" --output tsv)

if [ -z "${AKS_PUBLIC_IP}" ]; then
    echo "Warning: Could not determine AKS egress IP. LoadBalancer will accept all traffic."
    exit 0
fi

# Ensure kubectl context is pointing to GKE.
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ "${CURRENT_CONTEXT}" != *"${GKE_CLUSTER_NAME}"* ]]; then
    echo "Switching kubectl context to GKE cluster..."
    gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
        --project="${GCP_PROJECT}" \
        --zone="${GKE_ZONE}"
fi

echo "Restricting LoadBalancer to AKS egress IP: ${AKS_PUBLIC_IP}/32"
kubectl patch svc portainer-agent -n portainer --type='merge' \
    -p "{\"spec\":{\"loadBalancerSourceRanges\":[\"${AKS_PUBLIC_IP}/32\"]}}"

echo "LoadBalancer source restriction applied."
