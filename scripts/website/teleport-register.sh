#!/usr/bin/env bash
# Register davidshaevel-website as a Teleport application.
# Upgrades the existing teleport-agent Helm release to include the website.

source "$(dirname "$0")/../config.sh"
setup_logging "website-teleport-register"

TELEPORT_NAMESPACE="teleport-cluster"
WEBSITE_NAMESPACE="davidshaevel-website"

# Verify Teleport agent is installed.
if ! helm status teleport-agent -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Teleport agent not found. Run ./scripts/teleport/aks-agent-install.sh first."
    exit 1
fi

# Verify website frontend is running.
if ! kubectl get svc frontend -n "${WEBSITE_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Website frontend service not found in namespace '${WEBSITE_NAMESPACE}'."
    echo "Deploy the website first via Argo CD."
    exit 1
fi

# Get the current chart version to match.
TELEPORT_VERSION=$(helm list -n "${TELEPORT_NAMESPACE}" -o json | jq -r '.[] | select(.name=="teleport-agent") | .app_version')
echo "Teleport agent version: ${TELEPORT_VERSION}"

echo ""
echo "Upgrading teleport-agent to register website app..."
echo "  Apps: portainer + argocd + davidshaevel-website-aks"
echo "  Website URI: http://frontend.${WEBSITE_NAMESPACE}.svc.cluster.local:3000"
echo ""

# Explicitly set all apps to avoid Helm array merge issues with --reuse-values.
helm upgrade teleport-agent teleport/teleport-kube-agent \
    -n "${TELEPORT_NAMESPACE}" \
    --reuse-values \
    --set "apps[0].name=portainer" \
    --set "apps[0].uri=https://portainer.portainer.svc.cluster.local:9443" \
    --set "apps[0].insecure_skip_verify=true" \
    --set "apps[1].name=argocd" \
    --set "apps[1].uri=http://argocd-server.argocd.svc.cluster.local" \
    --set "apps[2].name=davidshaevel-website-aks" \
    --set "apps[2].uri=http://frontend.${WEBSITE_NAMESPACE}.svc.cluster.local:3000" \
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
echo "davidshaevel-website-aks is now accessible via Teleport:"
echo "  https://${TELEPORT_DOMAIN} -> davidshaevel-website-aks app"
