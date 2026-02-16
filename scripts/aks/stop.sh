#!/usr/bin/env bash
# Stop the AKS cluster to save costs when not in use.

source "$(dirname "$0")/../config.sh"
setup_logging "aks-stop"

echo "Stopping AKS cluster '${AKS_CLUSTER_NAME}'..."

az aks stop \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}"

echo "Cluster '${AKS_CLUSTER_NAME}' stopped. No VM charges while stopped."
