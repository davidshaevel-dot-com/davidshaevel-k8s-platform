#!/usr/bin/env bash
# Deploy teleport-kube-agent on the GKE cluster to register it with Teleport.
# Registers the GKE cluster as "portainer-gke" in Teleport for kubectl access.

source "$(dirname "$0")/../config.sh"
setup_logging "teleport-gke-agent-install"

TELEPORT_NAMESPACE="teleport-cluster"
GKE_KUBE_NAME="portainer-gke"

# Switch to AKS context to create the join token.
echo "Switching to AKS context to create join token..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing

# Verify Teleport is installed on AKS.
if ! helm status teleport-cluster -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Teleport cluster not found on AKS. Run ./scripts/teleport/install.sh first."
    exit 1
fi

# Create a join token for the GKE kube agent.
echo "Creating join token for kube agent..."
TOKEN=$(kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- \
    tctl tokens add --type=kube --ttl=1h --format=text)
echo "Token created (valid for 1 hour)."

# Get the Teleport chart version to match.
TELEPORT_VERSION=$(helm list -n "${TELEPORT_NAMESPACE}" -o json | jq -r '.[0].app_version')
echo "Teleport version: ${TELEPORT_VERSION}"

# Switch to GKE context for the agent install.
echo ""
echo "Switching to GKE context..."
gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}"

echo ""
echo "Installing teleport-kube-agent on GKE..."
echo "  Proxy:        ${TELEPORT_DOMAIN}:443"
echo "  Kube cluster: ${GKE_KUBE_NAME}"
echo ""

helm repo add teleport https://charts.releases.teleport.dev 2>/dev/null || true
helm repo update

kubectl create namespace "${TELEPORT_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install --wait -n "${TELEPORT_NAMESPACE}" teleport-agent teleport/teleport-kube-agent \
    --set roles="kube" \
    --set proxyAddr="${TELEPORT_DOMAIN}:443" \
    --set authToken="${TOKEN}" \
    --set kubeClusterName="${GKE_KUBE_NAME}" \
    --version="${TELEPORT_VERSION}"

echo ""
echo "=== Verification ==="
echo ""
echo "Agent pod on GKE:"
kubectl get pods -n "${TELEPORT_NAMESPACE}" -l app=teleport-agent
echo ""

# Switch back to AKS to verify registration.
echo "Switching back to AKS context to verify registration..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing

echo ""
echo "Registered kube clusters:"
kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- tctl kube ls
echo ""
echo "GKE cluster '${GKE_KUBE_NAME}' registered with Teleport."
echo "Access via: tsh kube login ${GKE_KUBE_NAME}"
