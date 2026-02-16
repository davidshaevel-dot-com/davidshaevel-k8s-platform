#!/usr/bin/env bash
# Show Portainer deployment status and access URL.

source "$(dirname "$0")/../config.sh"
setup_logging "portainer-status"

if ! helm status portainer -n portainer >/dev/null 2>&1; then
    echo "Portainer Helm release 'portainer' not found in namespace 'portainer'."
    echo "Run ./scripts/portainer/aks-install.sh to install it."
    exit 1
fi

echo "=== Helm Release ==="
helm status portainer -n portainer

echo ""
echo "=== Pods ==="
kubectl get pods -n portainer

echo ""
echo "=== Services ==="
kubectl get svc -n portainer

echo ""
echo "=== Access URL ==="
EXTERNAL_IP=$(kubectl get svc portainer -n portainer -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "${EXTERNAL_IP}" ]; then
    echo "  https://${EXTERNAL_IP}:9443/"
else
    echo "  LoadBalancer IP not yet assigned. Run: kubectl get svc -n portainer -w"
fi
