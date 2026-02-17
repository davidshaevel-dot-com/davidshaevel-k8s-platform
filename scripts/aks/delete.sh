#!/usr/bin/env bash
# Delete the AKS cluster. Prompts for confirmation.

source "$(dirname "$0")/../config.sh"
setup_logging "aks-delete"

echo "WARNING: This will delete the AKS cluster '${AKS_CLUSTER_NAME}' in '${RESOURCE_GROUP}'."
echo "All workloads and data on the cluster will be lost."
echo ""
read -p "Type the cluster name to confirm deletion: " confirm

if [ "${confirm}" != "${AKS_CLUSTER_NAME}" ]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo "Deleting AKS cluster '${AKS_CLUSTER_NAME}'..."

az aks delete \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --yes

echo "Cluster '${AKS_CLUSTER_NAME}' deleted."
