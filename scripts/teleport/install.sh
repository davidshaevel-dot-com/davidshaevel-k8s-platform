#!/usr/bin/env bash
# Install Teleport Community Edition via Helm.
# Reference: https://goteleport.com/docs/deploy-a-cluster/helm-deployments/kubernetes-cluster/

source "$(dirname "$0")/../config.sh"
setup_logging "teleport-install"

TELEPORT_NAMESPACE="teleport-cluster"
TELEPORT_ACME_EMAIL="${TELEPORT_ACME_EMAIL:?Set TELEPORT_ACME_EMAIL in .envrc or environment}"

echo "Adding Teleport Helm repository..."
helm repo add teleport https://charts.releases.teleport.dev
helm repo update

echo ""
echo "Creating namespace '${TELEPORT_NAMESPACE}'..."
kubectl create namespace "${TELEPORT_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "${TELEPORT_NAMESPACE}" pod-security.kubernetes.io/enforce=baseline --overwrite

echo ""
echo "Installing Teleport in namespace '${TELEPORT_NAMESPACE}'..."
echo "  Cluster name:    ${TELEPORT_DOMAIN}"
echo "  Listener mode:   multiplex"
echo "  ACME (TLS):      enabled (Let's Encrypt)"
echo ""

helm upgrade --install --wait -n "${TELEPORT_NAMESPACE}" teleport-cluster teleport/teleport-cluster \
    --set clusterName="${TELEPORT_DOMAIN}" \
    --set proxyListenerMode=multiplex \
    --set acme=true \
    --set acmeEmail="${TELEPORT_ACME_EMAIL}"

echo ""
echo "Teleport installed. Checking deployment status..."
echo ""
echo "=== Pods ==="
kubectl get pods -n "${TELEPORT_NAMESPACE}"
echo ""
echo "=== Services ==="
kubectl get svc -n "${TELEPORT_NAMESPACE}"

echo ""
echo "Waiting for LoadBalancer external IP (this may take a few minutes)..."
if kubectl wait -n "${TELEPORT_NAMESPACE}" --for=jsonpath='{.status.loadBalancer.ingress}' service/teleport-cluster --timeout=3m; then
    EXTERNAL_IP=$(kubectl get svc teleport-cluster -n "${TELEPORT_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo ""
    echo "Teleport LoadBalancer IP: ${EXTERNAL_IP}"
    echo ""
    echo "Next steps:"
    echo "  1. Run ./scripts/teleport/dns.sh to create DNS record"
    echo "  2. Wait for TLS certificate (may take a few minutes)"
    echo "  3. Access https://${TELEPORT_DOMAIN}"
else
    echo "LoadBalancer IP not assigned after 3 minutes."
    echo "Run: kubectl get svc -n ${TELEPORT_NAMESPACE} -w"
fi
