#!/usr/bin/env bash
# Disable Hubble observability by disabling Advanced Container Networking Services (ACNS).
#
# This removes Hubble relay pods and disables network flow observability.
# Hubble UI should be uninstalled first (./scripts/cilium/hubble-ui-uninstall.sh).
#
# Reference: https://learn.microsoft.com/en-us/azure/aks/use-advanced-container-networking-services

source "$(dirname "$0")/../config.sh"
setup_logging "hubble-disable"

echo "WARNING: This will disable Advanced Container Networking Services (ACNS)."
echo "  - Hubble relay will be removed"
echo "  - Network flow observability will be disabled"
echo "  - Hubble UI will stop working (uninstall it first if installed)"
echo ""
read -r -p "Type 'hubble' to confirm: " confirm

if [ "${confirm}" != "hubble" ]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo ""
echo "Disabling ACNS on AKS..."
echo "  Resource group:  ${RESOURCE_GROUP}"
echo "  Cluster:         ${AKS_CLUSTER_NAME}"
echo ""

az aks update \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --disable-acns

echo ""
echo "ACNS disabled. Hubble relay pods will be removed."
echo ""

echo "=== Cilium Config (Hubble) ==="
kubectl get cm -n kube-system cilium-config -o yaml | grep -E "enable-hubble"

echo ""
echo "Hubble is disabled."
