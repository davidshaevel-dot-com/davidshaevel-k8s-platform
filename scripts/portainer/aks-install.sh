#!/usr/bin/env bash
# Install Portainer Business Edition via Helm.
# Reference: https://docs.portainer.io/start/install/server/kubernetes/baremetal

source "$(dirname "$0")/../config.sh"
setup_logging "portainer-install"

echo "Adding Portainer Helm repository..."
helm repo add portainer https://portainer.github.io/k8s/
helm repo update

TRUSTED_ORIGIN="${PORTAINER_TRUSTED_ORIGIN}"

echo ""
echo "Installing Portainer BE in namespace 'portainer'..."
echo "  Service type:     ClusterIP (accessed via Teleport)"
echo "  Edition:          Business (Enterprise)"
echo "  Image tag:        lts"
echo "  Trusted origins:  ${TRUSTED_ORIGIN}"
echo ""

# Note: tls.force and trusted_origins are omitted from Helm values because
# the kubectl patch below overrides container args entirely. Setting them here
# would be misleading since they have no effect.
helm upgrade --install --create-namespace --wait -n portainer portainer portainer/portainer \
    --set service.type=ClusterIP \
    --set enterpriseEdition.enabled=true \
    --set image.tag=lts

# Workaround: The Portainer Helm chart wraps --trusted-origins values in escaped
# double quotes, causing CSRF validation to fail. Patch the deployment args directly
# to set --http-disabled (TLS only) and --trusted-origins correctly.
echo ""
echo "Patching trusted-origins args (workaround for Helm chart quoting bug)..."
kubectl patch deployment portainer -n portainer --type='json' \
    -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/args\", \"value\": [\"--http-disabled\", \"--trusted-origins=${TRUSTED_ORIGIN}\"]}]"

echo ""
echo "Waiting for patched pod to be ready..."
kubectl rollout status deployment/portainer -n portainer --timeout=2m

echo ""
echo "Portainer installed. Checking deployment status..."
echo ""

echo "=== Pods ==="
kubectl get pods -n portainer

echo ""
echo "=== Services ==="
kubectl get svc -n portainer

echo ""
echo "Portainer is accessible via Teleport at: https://${TRUSTED_ORIGIN}"
