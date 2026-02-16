#!/usr/bin/env bash
# Uninstall Portainer and clean up resources.

source "$(dirname "$0")/../config.sh"
setup_logging "portainer-uninstall"

echo "WARNING: This will uninstall Portainer from the cluster."
echo "All Portainer data will be lost."
echo ""
read -r -p "Type 'portainer' to confirm uninstall: " confirm

if [ "${confirm}" != "portainer" ]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo "Uninstalling Portainer..."
if helm status portainer -n portainer >/dev/null 2>&1; then
    helm uninstall portainer -n portainer --wait
else
    echo "Portainer Helm release not found, skipping uninstall."
fi

echo ""
echo "Deleting namespace 'portainer'..."
kubectl delete namespace portainer --ignore-not-found=true

echo ""
echo "Portainer uninstalled."
