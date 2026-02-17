#!/usr/bin/env bash
# Enable Hubble observability on AKS via Advanced Container Networking Services (ACNS).
#
# On AKS with Azure-managed Cilium (--network-dataplane cilium), Hubble is enabled
# through Azure's ACNS feature rather than the cilium CLI. This:
#   - Sets enable-hubble=true in the cilium-config ConfigMap
#   - Deploys hubble-relay pods in kube-system
#   - Enables network flow observability metrics
#
# Reference: https://learn.microsoft.com/en-us/azure/aks/use-advanced-container-networking-services

source "$(dirname "$0")/../config.sh"
setup_logging "hubble-enable"

# Check if ACNS is already enabled.
ACNS_STATUS=$(az aks show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --query "networkProfile.advancedNetworking.observability.enabled" \
    -o tsv 2>/dev/null)

if [ "${ACNS_STATUS}" = "true" ]; then
    echo "Hubble is already enabled via ACNS."
    echo ""
    kubectl get pods -n kube-system -l k8s-app=hubble-relay -o wide
    exit 0
fi

echo "Enabling Advanced Container Networking Services (ACNS) on AKS..."
echo "  Resource group:  ${RESOURCE_GROUP}"
echo "  Cluster:         ${AKS_CLUSTER_NAME}"
echo ""
echo "This enables Hubble observability (network flow visibility) on Azure-managed Cilium."
echo "The operation may take several minutes."
echo ""

az aks update \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --enable-acns

echo ""
echo "ACNS enabled. Waiting for Hubble relay pods to be ready..."
echo ""

# Wait for hubble-relay pods to appear and become ready.
for i in $(seq 1 30); do
    if kubectl get pods -n kube-system -l k8s-app=hubble-relay --no-headers 2>/dev/null | grep -q "Running"; then
        break
    fi
    echo "  Waiting for hubble-relay pods... (attempt ${i}/30)"
    sleep 10
done

if ! kubectl get pods -n kube-system -l k8s-app=hubble-relay --no-headers 2>/dev/null | grep -q "Running"; then
    echo "WARNING: hubble-relay pods not running after 5 minutes."
    echo "Check status manually: kubectl get pods -n kube-system -l k8s-app=hubble-relay"
fi

echo ""
echo "=== Hubble Relay Pods ==="
kubectl get pods -n kube-system -l k8s-app=hubble-relay -o wide

echo ""
echo "=== Cilium Config (Hubble) ==="
kubectl get cm -n kube-system cilium-config -o yaml | grep -E "enable-hubble" || echo "  (enable-hubble not found)"

echo ""
echo "Hubble is enabled. Next steps:"
echo "  - Install Hubble UI:  ./scripts/cilium/hubble-ui-install.sh"
echo "  - Check full status:  ./scripts/cilium/status.sh"
