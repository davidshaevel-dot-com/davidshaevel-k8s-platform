#!/usr/bin/env bash
# Show Teleport deployment status and access URL.

source "$(dirname "$0")/../config.sh"
setup_logging "teleport-status"

TELEPORT_NAMESPACE="teleport-cluster"

if ! helm status teleport-cluster -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    echo "Teleport Helm release 'teleport-cluster' not found in namespace '${TELEPORT_NAMESPACE}'."
    echo "Run ./scripts/teleport/install.sh to install it."
    exit 1
fi

echo "=== Helm Release ==="
helm status teleport-cluster -n "${TELEPORT_NAMESPACE}"
echo ""
echo "=== Pods ==="
kubectl get pods -n "${TELEPORT_NAMESPACE}"
echo ""
echo "=== Services ==="
kubectl get svc -n "${TELEPORT_NAMESPACE}"
echo ""
echo "=== Access URL ==="
EXTERNAL_IP=$(kubectl get svc teleport-cluster -n "${TELEPORT_NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "${EXTERNAL_IP}" ]; then
    echo "  https://${TELEPORT_DOMAIN}"
    echo "  LoadBalancer IP: ${EXTERNAL_IP}"
else
    echo "  LoadBalancer IP not yet assigned. Run: kubectl get svc -n ${TELEPORT_NAMESPACE} -w"
fi
