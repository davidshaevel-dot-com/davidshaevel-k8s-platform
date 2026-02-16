#!/usr/bin/env bash
# Orchestrated rebuild of the GKE environment.
# Creates cluster, installs and registers Portainer Agent, installs Teleport Agent.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-start"

SCRIPT_DIR="$(dirname "$0")"

echo "=========================================="
echo "  GKE Environment Rebuild"
echo "=========================================="
echo ""

# Step 1: Create cluster.
echo "--- Step 1/4: Create GKE cluster ---"
"${SCRIPT_DIR}/create.sh"

echo ""
echo "--- Step 2/4: Install Portainer Agent ---"
"${SCRIPT_DIR}/../portainer/gke-agent-install.sh"

echo ""
echo "--- Step 3/4: Register in Portainer ---"
"${SCRIPT_DIR}/../portainer/gke-agent-register.sh"

echo ""
echo "--- Step 4/4: Install Teleport Agent ---"
"${SCRIPT_DIR}/../teleport/gke-agent-install.sh"

echo ""
echo "=========================================="
echo "  GKE Environment Ready"
echo "=========================================="
echo ""
echo "Verify:"
echo "  1. GKE appears in Portainer UI as 'GKE'"
echo "  2. 'portainer-gke' in Teleport: tctl kube ls"
