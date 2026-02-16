#!/usr/bin/env bash
# Deploy teleport-kube-agent to register Portainer app and Kubernetes cluster with Teleport.
# This creates a join token, installs the agent via Helm, and switches Portainer to ClusterIP.

source "$(dirname "$0")/../config.sh"
setup_logging "teleport-agent-install"

TELEPORT_NAMESPACE="teleport-cluster"

# Verify Teleport is installed.
if ! helm status teleport-cluster -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Teleport cluster not found. Run ./scripts/teleport/install.sh first."
    exit 1
fi

# Create a join token for the agent.
echo "Creating join token for app + kube agent..."
TOKEN=$(kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- \
    tctl tokens add --type=app,kube --ttl=1h --format=text)
echo "Token created (valid for 1 hour)."

# Get the Teleport chart version to match.
TELEPORT_VERSION=$(helm list -n "${TELEPORT_NAMESPACE}" -o json | jq -r '.[0].app_version')
echo "Teleport version: ${TELEPORT_VERSION}"

echo ""
echo "Installing teleport-kube-agent..."
echo "  Proxy:          ${TELEPORT_DOMAIN}:443"
echo "  Kube cluster:   ${AKS_CLUSTER_NAME}"
echo "  App:            portainer -> https://portainer.portainer.svc.cluster.local:9443"
echo ""

helm upgrade --install --wait -n "${TELEPORT_NAMESPACE}" teleport-agent teleport/teleport-kube-agent \
    --set roles="app\,kube" \
    --set proxyAddr="${TELEPORT_DOMAIN}:443" \
    --set authToken="${TOKEN}" \
    --set kubeClusterName="${AKS_CLUSTER_NAME}" \
    --set "apps[0].name=portainer" \
    --set "apps[0].uri=https://portainer.portainer.svc.cluster.local:9443" \
    --set "apps[0].insecure_skip_verify=true" \
    --version="${TELEPORT_VERSION}"

echo ""
echo "Switching Portainer service to ClusterIP (removing public IP)..."
helm upgrade portainer portainer/portainer \
    -n portainer \
    --reuse-values \
    --set service.type=ClusterIP \
    --wait

# Grant admin user Kubernetes access via Teleport roles.
# system:masters = full cluster-admin on AKS
# cluster-admin = GKE-compatible admin group (GKE blocks system:masters impersonation)
echo ""
echo "Granting admin user Kubernetes group access..."
kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- \
    tctl users update admin --set-kubernetes-groups=system:masters,cluster-admin

echo ""
echo "=== Verification ==="
echo ""
echo "Agent pod:"
kubectl get pods -n "${TELEPORT_NAMESPACE}" -l app=teleport-agent
echo ""
echo "Portainer service (should be ClusterIP):"
kubectl get svc -n portainer
echo ""
echo "Registered apps:"
kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- tctl apps ls
echo ""
echo "Registered kube clusters:"
kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- tctl kube ls
echo ""
echo "Portainer is now accessible only via Teleport:"
echo "  https://${TELEPORT_DOMAIN}"
