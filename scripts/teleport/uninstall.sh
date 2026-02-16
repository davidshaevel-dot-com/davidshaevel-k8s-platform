#!/usr/bin/env bash
# Uninstall Teleport and clean up resources.

source "$(dirname "$0")/../config.sh"
setup_logging "teleport-uninstall"

TELEPORT_NAMESPACE="teleport-cluster"

echo "WARNING: This will uninstall Teleport from the cluster."
echo "All Teleport data will be lost."
echo ""

read -r -p "Type 'teleport' to confirm uninstall: " confirm
if [ "${confirm}" != "teleport" ]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo "Uninstalling Teleport..."
if helm status teleport-cluster -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    helm uninstall teleport-cluster -n "${TELEPORT_NAMESPACE}"
else
    echo "Teleport Helm release not found, skipping uninstall."
fi

echo ""
echo "Deleting namespace '${TELEPORT_NAMESPACE}'..."
kubectl delete namespace "${TELEPORT_NAMESPACE}" --ignore-not-found=true

echo ""
echo "Teleport uninstalled."
echo ""
echo "Remember to delete the DNS record:"
echo "  ./scripts/teleport/dns-delete.sh"
