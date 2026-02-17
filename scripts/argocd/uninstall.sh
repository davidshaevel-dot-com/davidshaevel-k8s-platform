#!/usr/bin/env bash
# Uninstall Argo CD and clean up resources.

source "$(dirname "$0")/../config.sh"
setup_logging "argocd-uninstall"

ARGOCD_NAMESPACE="argocd"

echo "WARNING: This will uninstall Argo CD from the cluster."
echo "All Argo CD applications and configuration will be lost."
echo ""
read -r -p "Type 'argocd' to confirm uninstall: " confirm

if [ "${confirm}" != "argocd" ]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo "Uninstalling Argo CD..."
if helm status argocd -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
    helm uninstall argocd -n "${ARGOCD_NAMESPACE}" --wait
else
    echo "Argo CD Helm release not found, skipping uninstall."
fi

echo ""
echo "Deleting namespace '${ARGOCD_NAMESPACE}'..."
kubectl delete namespace "${ARGOCD_NAMESPACE}" --ignore-not-found=true

echo ""
echo "Argo CD uninstalled."
echo ""
echo "NOTE: If Argo CD was registered in Teleport, update the Teleport agent"
echo "to remove the argocd app entry."
