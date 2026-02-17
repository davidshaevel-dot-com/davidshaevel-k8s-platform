#!/usr/bin/env bash
# Create an AKS cluster in the k8s-developer-platform-rg resource group.
# This is a one-time setup script.

source "$(dirname "$0")/../config.sh"
setup_logging "aks-create"

echo "Creating AKS cluster '${AKS_CLUSTER_NAME}' in resource group '${RESOURCE_GROUP}'..."
echo "  Location:    ${AKS_LOCATION}"
echo "  Node count:  ${AKS_NODE_COUNT}"
echo "  VM size:     ${AKS_NODE_VM_SIZE}"
echo "  Networking:  Azure CNI Overlay + Cilium"
echo ""

az aks create \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --node-count "${AKS_NODE_COUNT}" \
    --node-vm-size "${AKS_NODE_VM_SIZE}" \
    --location "${AKS_LOCATION}" \
    --network-plugin azure \
    --network-dataplane cilium \
    --network-plugin-mode overlay \
    --generate-ssh-keys \
    --output table

echo ""
echo "AKS cluster '${AKS_CLUSTER_NAME}' created successfully."
echo "Run ./scripts/aks/credentials.sh to configure kubectl access."
