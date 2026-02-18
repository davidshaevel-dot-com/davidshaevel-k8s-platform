#!/usr/bin/env bash
# Install Hubble UI for network flow visualization.
# Requires: ACNS enabled (hubble-relay must be running).
#
# Hubble UI is not deployed by ACNS and must be installed separately.
# This applies the hubble-ui.yaml manifest to deploy the UI in kube-system.
#
# Access the UI via port-forward:
#   kubectl -n kube-system port-forward svc/hubble-ui 12000:80
#   Open http://localhost:12000
#
# Reference: https://azure-samples.github.io/aks-labs/docs/networking/acns-lab/

source "$(dirname "$0")/../config.sh"
setup_logging "hubble-ui-install"

SCRIPT_DIR="$(dirname "$0")"

# Verify hubble-relay is running before installing UI.
if ! kubectl get pods -n kube-system -l k8s-app=hubble-relay --no-headers 2>/dev/null | grep -q "Running"; then
    echo "ERROR: hubble-relay is not running."
    echo "Enable Hubble first: ./scripts/cilium/hubble-enable.sh"
    exit 1
fi

echo "Installing Hubble UI in kube-system namespace..."
echo ""

kubectl apply -f "${SCRIPT_DIR}/hubble-ui.yaml"

echo ""
echo "Waiting for Hubble UI pods to be ready..."
kubectl rollout status deployment/hubble-ui -n kube-system --timeout=3m

echo ""
echo "=== Hubble UI Pods ==="
kubectl get pods -n kube-system -l k8s-app=hubble-ui -o wide

echo ""
echo "=== Hubble UI Service ==="
kubectl get svc -n kube-system hubble-ui

echo ""
echo "Hubble UI installed."
echo ""
echo "To access the Hubble UI:"
echo "  kubectl -n kube-system port-forward svc/hubble-ui 12000:80"
echo "  Open http://localhost:12000"
