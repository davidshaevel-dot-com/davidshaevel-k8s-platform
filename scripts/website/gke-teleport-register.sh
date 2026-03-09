#!/usr/bin/env bash
# Register davidshaevel-website on GKE as a Teleport application.
# Upgrades the GKE teleport-agent Helm release to include the website app.
#
# This script is called by gke/start.sh on every GKE rebuild.

source "$(dirname "$0")/../config.sh"
setup_logging "website-gke-teleport-register"

TELEPORT_NAMESPACE="teleport-cluster"
WEBSITE_NAMESPACE="davidshaevel-website"

# Switch to GKE context.
echo "Switching to GKE context..."
gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}"

# Verify Teleport agent is installed on GKE.
if ! helm status teleport-agent -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Teleport agent not found on GKE. Run ./scripts/gke/start.sh first."
    exit 1
fi

# Verify website frontend is running on GKE.
if ! kubectl get svc frontend -n "${WEBSITE_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Website frontend service not found on GKE in namespace '${WEBSITE_NAMESPACE}'."
    echo "Wait for Argo CD to sync the GKE application."
    exit 1
fi

# Get the current chart version to match.
TELEPORT_VERSION=$(helm list -n "${TELEPORT_NAMESPACE}" -o json | jq -r '.[] | select(.name=="teleport-agent") | .app_version')
echo "Teleport agent version: ${TELEPORT_VERSION}"

echo ""
echo "Upgrading teleport-agent on GKE to register website app..."
echo "  Apps: davidshaevel-website-gke"
echo "  Website URI: http://frontend.${WEBSITE_NAMESPACE}.svc.cluster.local:3000"
echo ""

# The GKE agent currently only has kube registration. Add the app.
helm upgrade teleport-agent teleport/teleport-kube-agent \
    -n "${TELEPORT_NAMESPACE}" \
    --reuse-values \
    --set "roles=kube\,app" \
    --set "apps[0].name=davidshaevel-website-gke" \
    --set "apps[0].uri=http://frontend.${WEBSITE_NAMESPACE}.svc.cluster.local:3000" \
    --version="${TELEPORT_VERSION}" \
    --wait

echo ""
echo "Waiting for agent pod to be ready..."
kubectl rollout status statefulset/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || kubectl rollout status deployment/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || kubectl rollout status daemonset/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || echo "Warning: Could not verify agent rollout. Check manually."

# Switch back to AKS to verify registration.
echo ""
echo "Switching back to AKS context to verify registration..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing

echo ""
echo "=== Registered Apps ==="
kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- tctl apps ls

echo ""
echo "davidshaevel-website-gke is now accessible via Teleport:"
echo "  https://davidshaevel-website-gke.${TELEPORT_DOMAIN}"
