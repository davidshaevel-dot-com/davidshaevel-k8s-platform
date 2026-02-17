#!/usr/bin/env bash
# Create an Azure Container Registry and attach it to the AKS cluster.
# Attaching grants AKS managed identity the AcrPull role — no image pull secrets needed.
#
# Usage: ./scripts/acr/create.sh

source "$(dirname "$0")/../config.sh"
setup_logging "acr-create"

echo "Creating Azure Container Registry '${ACR_NAME}'..."
echo "  Resource Group: ${RESOURCE_GROUP}"
echo "  Location:       ${AKS_LOCATION}"
echo "  SKU:            Basic (~\$5/month)"
echo ""

az acr create \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${ACR_NAME}" \
    --sku Basic \
    --location "${AKS_LOCATION}" \
    --output table

echo ""
echo "Attaching ACR to AKS cluster '${AKS_CLUSTER_NAME}'..."
echo "  This grants the AKS managed identity AcrPull role on the registry."
echo ""

az aks update \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --attach-acr "${ACR_NAME}" \
    --output table

echo ""
echo "ACR '${ACR_NAME}' created and attached to AKS."
echo "  Login server: ${ACR_LOGIN_SERVER}"
echo ""
echo "Verify with:"
echo "  az acr show --name ${ACR_NAME} --query '{name:name, loginServer:loginServer, sku:sku.name}' --output table"
echo "  az aks check-acr --resource-group ${RESOURCE_GROUP} --name ${AKS_CLUSTER_NAME} --acr ${ACR_LOGIN_SERVER}"
