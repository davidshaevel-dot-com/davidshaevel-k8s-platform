#!/usr/bin/env bash
# Detach ACR from AKS and delete the Azure Container Registry.
# Prompts for confirmation before deleting.
#
# Usage: ./scripts/acr/delete.sh

source "$(dirname "$0")/../config.sh"
setup_logging "acr-delete"

echo "WARNING: This will delete the Azure Container Registry '${ACR_NAME}'."
echo "All container images stored in the registry will be permanently lost."
echo ""
read -p "Type the registry name to confirm deletion: " confirm

if [ "${confirm}" != "${ACR_NAME}" ]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo ""
echo "Detaching ACR from AKS cluster '${AKS_CLUSTER_NAME}'..."

az aks update \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --detach-acr "${ACR_NAME}" \
    --output table

echo ""
echo "Deleting ACR '${ACR_NAME}'..."

az acr delete \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${ACR_NAME}" \
    --yes

echo ""
echo "ACR '${ACR_NAME}' deleted."
