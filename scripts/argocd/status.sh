#!/usr/bin/env bash
# Show Argo CD deployment status.

source "$(dirname "$0")/../config.sh"
setup_logging "argocd-status"

ARGOCD_NAMESPACE="argocd"

if ! helm status argocd -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
    echo "Argo CD Helm release 'argocd' not found in namespace '${ARGOCD_NAMESPACE}'."
    echo "Run ./scripts/argocd/install.sh to install it."
    exit 1
fi

echo "=== Helm Release ==="
helm status argocd -n "${ARGOCD_NAMESPACE}"

echo ""
echo "=== Pods ==="
kubectl get pods -n "${ARGOCD_NAMESPACE}"

echo ""
echo "=== Services ==="
kubectl get svc -n "${ARGOCD_NAMESPACE}"

echo ""
echo "=== Argo CD Applications ==="
kubectl get applications -n "${ARGOCD_NAMESPACE}" 2>/dev/null || echo "  No applications found."

echo ""
echo "=== Access ==="
echo "  Via Teleport: https://${TELEPORT_DOMAIN} -> argocd app"
