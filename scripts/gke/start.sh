#!/usr/bin/env bash
# Orchestrated rebuild of the GKE environment.
# Creates cluster, installs agents, sets up ACR access, registers in Argo CD,
# applies network policies, and registers website in Teleport.
#
# Step order matters: ACR pull secret (step 5) must be set up BEFORE registering
# GKE in Argo CD (step 6), because Argo CD auto-syncs immediately and pods will
# fail with ImagePullBackOff if the secret doesn't exist yet.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-start"

SCRIPT_DIR="$(dirname "$0")"

echo "=========================================="
echo "  GKE Environment Rebuild"
echo "=========================================="
echo ""

# Step 1: Create cluster.
echo "--- Step 1/8: Create GKE cluster ---"
"${SCRIPT_DIR}/create.sh"

echo ""
echo "--- Step 2/8: Install Portainer Agent ---"
"${SCRIPT_DIR}/../portainer/gke-agent-install.sh"

echo ""
echo "--- Step 3/8: Register in Portainer ---"
"${SCRIPT_DIR}/../portainer/gke-agent-register.sh"

echo ""
echo "--- Step 4/8: Install Teleport Agent ---"
"${SCRIPT_DIR}/../teleport/gke-agent-install.sh"

echo ""
echo "--- Step 5/8: Set up ACR pull secret ---"
"${SCRIPT_DIR}/acr-pull-secret.sh"

echo ""
echo "--- Step 6/8: Register GKE in Argo CD ---"
"${SCRIPT_DIR}/argocd-cluster-add.sh"

echo ""
echo "--- Step 7/8: Apply network policies ---"
"${SCRIPT_DIR}/apply-network-policies.sh"

echo ""
echo "--- Step 8/8: Register website in Teleport ---"
"${SCRIPT_DIR}/../website/gke-teleport-register.sh"

echo ""
echo "=========================================="
echo "  GKE Environment Ready"
echo "=========================================="
echo ""
echo "Verify:"
echo "  1. GKE appears in Portainer UI as 'GKE'"
echo "  2. 'k8s-developer-platform-gke' in Teleport: tctl kube ls"
echo "  3. davidshaevel-website-gke Synced/Healthy in Argo CD"
echo "  4. https://davidshaevel-website-gke.teleport.davidshaevel.com loads"
