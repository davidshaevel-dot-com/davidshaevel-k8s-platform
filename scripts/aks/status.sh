#!/usr/bin/env bash
# Show AKS cluster status and node information.

source "$(dirname "$0")/../config.sh"
setup_logging "aks-status"

echo "=== Cluster Info ==="
az aks show \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --query "{name:name, status:powerState.code, kubernetesVersion:kubernetesVersion, nodeCount:agentPoolProfiles[0].count, vmSize:agentPoolProfiles[0].vmSize, location:location}" \
    --output table

echo ""
echo "=== Node Pool ==="
az aks nodepool list \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --cluster-name "${AKS_CLUSTER_NAME}" \
    --output table
