#!/usr/bin/env bash
# Remove the GKE Portainer Agent endpoint from Portainer via REST API.
# Uses kubectl port-forward to reach Portainer ClusterIP on AKS.
#
# Prerequisites:
#   - AKS credentials configured (kubectl can reach AKS)
#   - PORTAINER_ADMIN_PASSWORD set in environment
#
# Usage: ./scripts/portainer/gke-agent-deregister.sh

source "$(dirname "$0")/../config.sh"
setup_logging "portainer-gke-agent-deregister"

PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:?Set PORTAINER_ADMIN_PASSWORD in .envrc or environment}"
PORTAINER_LOCAL_PORT=9444
PORTAINER_BASE_URL="https://localhost:${PORTAINER_LOCAL_PORT}"
ENDPOINT_NAME="GKE"

# --- Step 1: Ensure AKS context and start port-forward ---
echo "Ensuring AKS context..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing

echo "Starting port-forward to Portainer (localhost:${PORTAINER_LOCAL_PORT} -> portainer:9443)..."
kubectl port-forward svc/portainer -n portainer "${PORTAINER_LOCAL_PORT}:9443" &
PF_PID=$!

cleanup() {
    if kill -0 "${PF_PID}" 2>/dev/null; then
        echo "Stopping port-forward (PID ${PF_PID})..."
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Wait up to 15 seconds for port-forward to be ready
echo "Waiting for port-forward to be ready..."
for i in {1..15}; do
    if curl -sk "${PORTAINER_BASE_URL}" >/dev/null; then
        echo "Port-forward is ready."
        break
    fi
    if ! kill -0 "${PF_PID}"; then
        echo "Error: port-forward process died unexpectedly."
        exit 1
    fi
    if [[ "$i" -eq 15 ]]; then
        echo "Error: port-forward timed out."
        exit 1
    fi
    sleep 1
done

# --- Step 2: Authenticate to Portainer API ---
echo ""
echo "Authenticating to Portainer API..."
AUTH_RESPONSE=$(curl -sk -X POST "${PORTAINER_BASE_URL}/api/auth" \
    -H "Content-Type: application/json" \
    -d "{\"Username\":\"admin\",\"Password\":\"${PORTAINER_ADMIN_PASSWORD}\"}")

JWT=$(echo "${AUTH_RESPONSE}" | jq -r '.jwt // empty')
if [ -z "${JWT}" ]; then
    echo "Error: Failed to authenticate to Portainer API."
    echo "Response: ${AUTH_RESPONSE}"
    exit 1
fi
echo "Authenticated successfully."

# --- Step 3: Find and delete endpoint ---
echo ""
echo "Looking for endpoint '${ENDPOINT_NAME}'..."
ENDPOINTS=$(curl -sk -X GET "${PORTAINER_BASE_URL}/api/endpoints" \
    -H "Authorization: Bearer ${JWT}")

ENDPOINT_ID=$(echo "${ENDPOINTS}" | jq -r ".[] | select(.Name == \"${ENDPOINT_NAME}\") | .Id // empty")

if [ -z "${ENDPOINT_ID}" ]; then
    echo "Endpoint '${ENDPOINT_NAME}' not found. Nothing to remove."
    exit 0
fi

echo "Deleting endpoint '${ENDPOINT_NAME}' (ID: ${ENDPOINT_ID})..."
RESPONSE_CODE=$(curl -sk -w "%{http_code}" -o /dev/null -X DELETE "${PORTAINER_BASE_URL}/api/endpoints/${ENDPOINT_ID}" \
    -H "Authorization: Bearer ${JWT}")

if [[ "${RESPONSE_CODE}" -eq 204 ]]; then
    echo "Endpoint '${ENDPOINT_NAME}' removed from Portainer."
else
    echo "Error: Failed to delete endpoint. Received status code ${RESPONSE_CODE}."
    exit 1
fi
