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
echo "Verifying Hubble UI removed..."
kubectl get pods -n kube-system -l k8s-app=hubble-ui 2>/dev/null || true

echo ""
echo "Hubble UI uninstalled."
