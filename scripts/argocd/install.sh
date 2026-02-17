#!/usr/bin/env bash
# Install Argo CD via Helm on the AKS control plane.
# Reference: https://argo-cd.readthedocs.io/en/stable/getting_started/

source "$(dirname "$0")/../config.sh"
setup_logging "argocd-install"

ARGOCD_NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Adding Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo ""
echo "Creating namespace '${ARGOCD_NAMESPACE}'..."
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "${ARGOCD_NAMESPACE}" pod-security.kubernetes.io/enforce=baseline --overwrite

echo ""
echo "Installing Argo CD in namespace '${ARGOCD_NAMESPACE}'..."
echo "  Service type:     ClusterIP (accessed via Teleport)"
echo "  Dex:              Disabled"
echo "  HA:               Disabled (single-node dev cluster)"
echo ""

helm upgrade --install --wait -n "${ARGOCD_NAMESPACE}" argocd argo/argo-cd \
    -f "${SCRIPT_DIR}/helm-values/argocd/values.yaml"

echo ""
echo "Waiting for Argo CD server to be ready..."
kubectl rollout status deployment/argocd-server -n "${ARGOCD_NAMESPACE}" --timeout=3m

echo ""
echo "=== Initial Admin Password ==="
ADMIN_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
if [ -n "${ADMIN_PASSWORD}" ]; then
    echo "  Username: admin"
    echo "  Password: ${ADMIN_PASSWORD}"
    echo ""
    echo "  IMPORTANT: Save this password to 1Password, then delete the secret:"
    echo "    kubectl -n ${ARGOCD_NAMESPACE} delete secret argocd-initial-admin-secret"
else
    echo "  Initial admin secret not found. Password may have already been retrieved."
fi

echo ""
echo "=== Pods ==="
kubectl get pods -n "${ARGOCD_NAMESPACE}"

echo ""
echo "=== Services ==="
kubectl get svc -n "${ARGOCD_NAMESPACE}"

echo ""
echo "Argo CD installed. Register it in Teleport with:"
echo "  ./scripts/argocd/teleport-register.sh"
echo ""
echo "Then access via: https://${TELEPORT_DOMAIN} -> argocd app"
