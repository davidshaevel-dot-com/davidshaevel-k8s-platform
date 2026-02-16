#!/usr/bin/env bash
# Fetch AKS cluster credentials and configure kubectl.

source "$(dirname "$0")/../config.sh"
setup_logging "aks-credentials"

echo "Fetching credentials for cluster '${AKS_CLUSTER_NAME}'..."

az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing

echo ""
echo "kubectl configured. Verifying access..."
echo ""

echo "=== Nodes ==="
kubectl get nodes -o wide

echo ""
echo "=== Storage Classes ==="
kubectl get sc
