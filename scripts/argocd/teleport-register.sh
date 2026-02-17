#!/usr/bin/env bash
# Register Argo CD as a Teleport application.
# Upgrades the existing teleport-agent Helm release to include Argo CD.

source "$(dirname "$0")/../config.sh"
setup_logging "argocd-teleport-register"

TELEPORT_NAMESPACE="teleport-cluster"
ARGOCD_NAMESPACE="argocd"

# Verify Teleport agent is installed.
if ! helm status teleport-agent -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Teleport agent not found. Run ./scripts/teleport/aks-agent-install.sh first."
    exit 1
fi

# Verify Argo CD is installed.
if ! helm status argocd -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Argo CD not found. Run ./scripts/argocd/install.sh first."
    exit 1
fi

# Get the current chart version to match.
TELEPORT_VERSION=$(helm list -n "${TELEPORT_NAMESPACE}" -o json | jq -r '.[] | select(.name=="teleport-agent") | .app_version')
echo "Teleport agent version: ${TELEPORT_VERSION}"

echo ""
echo "Upgrading teleport-agent to register Argo CD app..."
echo "  Apps: portainer + argocd"
echo "  Argo CD URI: http://argocd-server.${ARGOCD_NAMESPACE}.svc.cluster.local"
echo ""

# Explicitly set both apps to avoid Helm array merge issues with --reuse-values.
helm upgrade teleport-agent teleport/teleport-kube-agent \
    -n "${TELEPORT_NAMESPACE}" \
    --reuse-values \
    --set "apps[0].name=portainer" \
    --set "apps[0].uri=https://portainer.portainer.svc.cluster.local:9443" \
    --set "apps[0].insecure_skip_verify=true" \
    --set "apps[1].name=argocd" \
    --set "apps[1].uri=http://argocd-server.${ARGOCD_NAMESPACE}.svc.cluster.local" \
    --version="${TELEPORT_VERSION}" \
    --wait

echo ""
echo "Waiting for agent pod to be ready..."
kubectl rollout status statefulset/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || kubectl rollout status deployment/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || kubectl rollout status daemonset/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || echo "Warning: Could not verify agent rollout. Check manually."

echo ""
echo "=== Registered Apps ==="
kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- tctl apps ls

echo ""
echo "Argo CD is now accessible via Teleport:"
echo "  https://${TELEPORT_DOMAIN} -> argocd app"
