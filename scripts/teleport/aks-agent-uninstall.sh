#!/usr/bin/env bash
# Uninstall the teleport-kube-agent and restore Portainer's public LoadBalancer.

source "$(dirname "$0")/../config.sh"
setup_logging "teleport-agent-uninstall"

TELEPORT_NAMESPACE="teleport-cluster"

echo "WARNING: This will uninstall the Teleport agent."
echo "Portainer will be restored to a public LoadBalancer."
echo ""

read -r -p "Type 'agent' to confirm: " confirm
if [ "${confirm}" != "agent" ]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo "Uninstalling teleport-agent..."
if helm status teleport-agent -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    helm uninstall teleport-agent -n "${TELEPORT_NAMESPACE}"
else
    echo "Teleport agent Helm release not found, skipping."
fi

echo ""
echo "Restoring Portainer to LoadBalancer..."
helm upgrade portainer portainer/portainer \
    -n portainer \
    --reuse-values \
    --set service.type=LoadBalancer \
    --wait

echo ""
echo "Portainer service:"
kubectl get svc -n portainer
echo ""
echo "Teleport agent uninstalled. Portainer is publicly accessible again."
