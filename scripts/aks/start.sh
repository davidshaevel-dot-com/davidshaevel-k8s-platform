#!/usr/bin/env bash
# Start a stopped AKS cluster.

source "$(dirname "$0")/../config.sh"
setup_logging "aks-start"

echo "Starting AKS cluster '${AKS_CLUSTER_NAME}'..."

az aks start \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}"

echo "Cluster '${AKS_CLUSTER_NAME}' started."
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/teleport/dns.sh to update DNS (LoadBalancer IP may have changed)"
echo "  2. Wait a few minutes for DNS propagation and TLS certificate renewal"
echo "  3. Verify access at https://${TELEPORT_DOMAIN}"
