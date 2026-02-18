#!/usr/bin/env bash
# Show Cilium and Hubble status: pods, relay, UI, and CiliumNetworkPolicies.
# Cilium is Azure-managed (runs in kube-system, not installed via Helm by us).

source "$(dirname "$0")/../config.sh"
setup_logging "cilium-status"

echo "=== Cilium Pods ==="
kubectl get pods -n kube-system -l k8s-app=cilium -o wide

echo ""
echo "=== Cilium Config (Hubble settings) ==="
kubectl get cm -n kube-system cilium-config -o yaml 2>/dev/null \
    | grep -E "enable-hubble|hubble" || echo "  (no hubble settings found)"

echo ""
echo "=== Hubble Relay ==="
RELAY_PODS=$(kubectl get pods -n kube-system -l k8s-app=hubble-relay -o wide 2>/dev/null)
if [ -n "${RELAY_PODS}" ]; then
    echo "${RELAY_PODS}"
else
    echo "  (no hubble-relay pods found)"
fi

echo ""
echo "=== Hubble UI ==="
UI_PODS=$(kubectl get pods -n kube-system -l k8s-app=hubble-ui -o wide 2>/dev/null)
if [ -n "${UI_PODS}" ]; then
    echo "${UI_PODS}"
else
    echo "  (no hubble-ui pods found)"
fi

echo ""
echo "=== Hubble Services ==="
HUBBLE_SVCS=$(kubectl get svc -n kube-system -l "k8s-app in (hubble-relay, hubble-ui)" 2>/dev/null)
if [ -n "${HUBBLE_SVCS}" ]; then
    echo "${HUBBLE_SVCS}"
else
    echo "  (no hubble services found)"
fi

echo ""
echo "=== CiliumNetworkPolicies ==="
kubectl get ciliumnetworkpolicies -A 2>/dev/null || echo "  (none found)"

echo ""
echo "=== CiliumClusterwideNetworkPolicies ==="
kubectl get ciliumclusterwidenetworkpolicies -A 2>/dev/null || echo "  (none found)"

echo ""
echo "=== Azure ACNS Status ==="
ACNS_STATUS=$(az aks show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --query "networkProfile.advancedNetworking" \
    -o json 2>/dev/null)
if [ "${ACNS_STATUS}" = "null" ] || [ -z "${ACNS_STATUS}" ]; then
    echo "  Advanced Container Networking Services (ACNS): NOT ENABLED"
    echo "  Run ./scripts/cilium/hubble-enable.sh to enable Hubble via ACNS."
else
    echo "  Advanced Container Networking Services (ACNS): ENABLED"
    echo "  ${ACNS_STATUS}"
fi
