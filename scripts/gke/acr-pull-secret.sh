#!/usr/bin/env bash
# Set up ACR image pull secret on GKE so pods can pull from Azure Container Registry.
# Requires: ACR_SP_APP_ID and ACR_SP_PASSWORD in .envrc.
#
# Uses the dedicated 'gke-acr-pull' service principal (AcrPull role only on k8sdevplatformacr).
# This script is called by gke/start.sh on every GKE rebuild.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-acr-pull-secret"

WEBSITE_NAMESPACE="davidshaevel-website"
ACR_SP_APP_ID="${ACR_SP_APP_ID:?Set ACR_SP_APP_ID in .envrc}"
ACR_SP_PASSWORD="${ACR_SP_PASSWORD:?Set ACR_SP_PASSWORD in .envrc}"

# Switch to GKE context.
echo "Switching to GKE context..."
gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}"

# Create namespace (idempotent).
kubectl create namespace "${WEBSITE_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Create or replace the pull secret.
echo "Creating ACR pull secret in ${WEBSITE_NAMESPACE}..."
kubectl create secret docker-registry acr-pull-secret \
    --docker-server="${ACR_LOGIN_SERVER}" \
    --docker-username="${ACR_SP_APP_ID}" \
    --docker-password="${ACR_SP_PASSWORD}" \
    -n "${WEBSITE_NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Patch the default service account.
echo "Patching default service account..."
kubectl patch serviceaccount default -n "${WEBSITE_NAMESPACE}" \
    -p '{"imagePullSecrets": [{"name": "acr-pull-secret"}]}'

echo ""
echo "ACR pull secret configured on GKE."
kubectl get serviceaccount default -n "${WEBSITE_NAMESPACE}" -o jsonpath='{.imagePullSecrets}'; echo

# Switch back to AKS context.
echo ""
echo "Switching back to AKS context..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing
