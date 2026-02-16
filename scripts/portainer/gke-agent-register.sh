#!/usr/bin/env bash
# Register the GKE Portainer Agent endpoint with Portainer BE via its REST API.
# Replaces the manual "Add Environment" step in the Portainer UI.
#
# Since Portainer runs as ClusterIP (no public IP), this uses kubectl port-forward
# to reach it on AKS.
#
# Prerequisites:
#   - AKS credentials configured (kubectl can reach AKS)
#   - GKE Portainer Agent installed with LoadBalancer IP assigned
#   - PORTAINER_ADMIN_PASSWORD set in environment
#
# Usage: ./scripts/portainer/gke-agent-register.sh

source "$(dirname "$0")/../config.sh"
setup_logging "portainer-gke-agent-register"

PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:?Set PORTAINER_ADMIN_PASSWORD in .envrc or environment}"
PORTAINER_LOCAL_PORT=9444
PORTAINER_BASE_URL="https://localhost:${PORTAINER_LOCAL_PORT}"
ENDPOINT_NAME="GKE"
PORTAINER_GROUP_ID=1

# --- Step 1: Get GKE Agent LoadBalancer IP ---
echo "Getting GKE Portainer Agent LoadBalancer IP..."

CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ "${CURRENT_CONTEXT}" != *"${GKE_CLUSTER_NAME}"* ]]; then
    echo "Switching kubectl context to GKE cluster..."
    gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
        --project="${GCP_PROJECT}" \
        --zone="${GKE_ZONE}"
fi

AGENT_IP=$(kubectl get svc portainer-agent -n portainer \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

if [ -z "${AGENT_IP}" ]; then
    echo "Error: GKE Portainer Agent LoadBalancer IP not found."
    echo "Ensure the agent is installed: ./scripts/portainer/gke-agent-install.sh"
    exit 1
fi
echo "Agent IP: ${AGENT_IP}"

# --- Step 2: Switch to AKS and start port-forward ---
echo ""
echo "Switching to AKS context for Portainer API access..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing

echo "Starting port-forward to Portainer (localhost:${PORTAINER_LOCAL_PORT} -> portainer:9443)..."
kubectl port-forward svc/portainer -n portainer "${PORTAINER_LOCAL_PORT}:9443" &
PF_PID=$!

# Ensure port-forward is cleaned up on exit.
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

# --- Step 3: Authenticate to Portainer API ---
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

# --- Step 4: Check if endpoint already exists ---
echo ""
echo "Checking for existing '${ENDPOINT_NAME}' endpoint..."
EXISTING_ENDPOINTS=$(curl -sk -X GET "${PORTAINER_BASE_URL}/api/endpoints" \
    -H "Authorization: Bearer ${JWT}")

EXISTING_ID=$(echo "${EXISTING_ENDPOINTS}" | jq -r ".[] | select(.Name == \"${ENDPOINT_NAME}\") | .Id // empty")

if [ -n "${EXISTING_ID}" ]; then
    echo "Endpoint '${ENDPOINT_NAME}' already exists (ID: ${EXISTING_ID}). Deleting stale endpoint..."
    RESPONSE_CODE=$(curl -sk -w "%{http_code}" -o /dev/null -X DELETE "${PORTAINER_BASE_URL}/api/endpoints/${EXISTING_ID}" \
        -H "Authorization: Bearer ${JWT}")

    if [[ "${RESPONSE_CODE}" -eq 204 ]]; then
        echo "Stale endpoint deleted."
    else
        echo "Error: Failed to delete stale endpoint. Received status code ${RESPONSE_CODE}."
        exit 1
    fi
fi

# --- Step 5: Create endpoint (retry up to 90s for LB propagation) ---
echo "Creating endpoint '${ENDPOINT_NAME}'..."
for attempt in {1..6}; do
    CREATE_RESPONSE=$(curl -sk -X POST "${PORTAINER_BASE_URL}/api/endpoints" \
        -H "Authorization: Bearer ${JWT}" \
        -F "Name=${ENDPOINT_NAME}" \
        -F "EndpointCreationType=2" \
        -F "URL=tcp://${AGENT_IP}:9001" \
        -F "TLS=true" \
        -F "TLSSkipVerify=true" \
        -F "TLSSkipClientVerify=true" \
        -F "GroupID=${PORTAINER_GROUP_ID}")

    NEW_ID=$(echo "${CREATE_RESPONSE}" | jq -r '.Id // empty')
    if [ -n "${NEW_ID}" ]; then
        echo "Endpoint created (ID: ${NEW_ID})."
        break
    fi

    if [[ "${attempt}" -eq 6 ]]; then
        echo "Error: Failed to create endpoint after ${attempt} attempts."
        echo "Response: ${CREATE_RESPONSE}"
        exit 1
    fi

    echo "Attempt ${attempt}/6 failed (agent may not be routable yet). Retrying in 15s..."
    sleep 15
done

# --- Step 6: Verify connection ---
echo ""
echo "Verifying endpoint connection..."
for i in {1..15}; do
    ENDPOINTS=$(curl -sk -X GET "${PORTAINER_BASE_URL}/api/endpoints" \
        -H "Authorization: Bearer ${JWT}")
    ENDPOINT_STATUS=$(echo "${ENDPOINTS}" | jq -r ".[] | select(.Name == \"${ENDPOINT_NAME}\") | .Status")

    if [[ "${ENDPOINT_STATUS}" == "1" ]]; then
        echo "Endpoint '${ENDPOINT_NAME}' status: connected"
        break
    fi

    if [[ "$i" -eq 15 ]]; then
        echo "Warning: Endpoint '${ENDPOINT_NAME}' not yet connected after 15 seconds (status: ${ENDPOINT_STATUS}). Registration succeeded — connection may still be initializing."
        break
    fi
    sleep 1
done

echo ""
echo "Portainer agent registration complete."
echo "  Agent: tcp://${AGENT_IP}:9001"
echo "  Endpoint: ${ENDPOINT_NAME}"
