#!/usr/bin/env bash
# Apply namespace isolation network policies and show active policies.

source "$(dirname "$0")/../config.sh"
setup_logging "cilium-apply-policies"

MANIFEST_DIR="$(dirname "$0")/../../manifests/cilium"

# Verify target namespaces exist before applying policies.
for ns in portainer teleport-cluster; do
    if ! kubectl get namespace "${ns}" &>/dev/null; then
        echo "ERROR: Namespace '${ns}' does not exist."
        echo "Install the namespace workloads first."
        exit 1
    fi
done

# Remove stale allow-dns CiliumNetworkPolicies if present.
# These were removed because any CiliumNetworkPolicy egress rule triggers
# Cilium's implicit default-deny for all other egress.
for ns in portainer teleport-cluster; do
    kubectl delete ciliumnetworkpolicy allow-dns -n "${ns}" --ignore-not-found=true 2>/dev/null
done

echo "Applying namespace isolation policies..."
echo "  Manifest: ${MANIFEST_DIR}/namespace-isolation.yaml"
echo ""

kubectl apply -f "${MANIFEST_DIR}/namespace-isolation.yaml"

echo ""
echo "=== NetworkPolicies (default deny) ==="
kubectl get networkpolicies -A

echo ""
echo "=== CiliumNetworkPolicies (allow rules) ==="
kubectl get ciliumnetworkpolicies -A
