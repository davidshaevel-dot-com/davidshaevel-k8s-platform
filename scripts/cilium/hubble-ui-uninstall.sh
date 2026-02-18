#!/usr/bin/env bash
# Uninstall Hubble UI and clean up its resources.

source "$(dirname "$0")/../config.sh"
setup_logging "hubble-ui-uninstall"

SCRIPT_DIR="$(dirname "$0")"

echo "WARNING: This will uninstall Hubble UI from the cluster."
echo ""
read -r -p "Type 'hubble-ui' to confirm uninstall: " confirm

if [ "${confirm}" != "hubble-ui" ]; then
    echo "Confirmation failed. Aborting."
    exit 1
fi

echo ""
echo "Uninstalling Hubble UI..."
kubectl delete -f "${SCRIPT_DIR}/hubble-ui.yaml" --ignore-not-found=true

echo ""
echo "Verifying Hubble UI resources are removed..."
if ! kubectl wait --for=delete pod -l k8s-app=hubble-ui -n kube-system --timeout=2m; then
    echo "Warning: Hubble UI pods did not delete in time. Check manually."
fi

echo ""
echo "Hubble UI uninstalled."
