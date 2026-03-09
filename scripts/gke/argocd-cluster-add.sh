#!/usr/bin/env bash
# Register GKE cluster in Argo CD using --core mode (no password needed).
# Requires: argocd CLI, kubectl context for both AKS (current) and GKE.
#
# This script is called by gke/start.sh on every GKE rebuild.
# Uses cluster name so committed YAML (AppProject, Applications) is stable across recreates.
#
# Note: --core mode requires the default kubectl namespace to be 'argocd'
# so it can find the argocd-cm ConfigMap.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-argocd-cluster-add"

GKE_CONTEXT="gke_${GCP_PROJECT}_${GKE_ZONE}_${GKE_CLUSTER_NAME}"

# Set default namespace to argocd for --core mode.
kubectl config set-context --current --namespace=argocd

echo "Removing stale GKE cluster from Argo CD (if exists)..."
yes | argocd cluster rm k8s-developer-platform-gke --core 2>/dev/null || true

echo "Adding GKE cluster to Argo CD..."
echo "  Context: ${GKE_CONTEXT}"
echo "  Name:    k8s-developer-platform-gke"
echo ""

argocd cluster add "${GKE_CONTEXT}" \
    --name k8s-developer-platform-gke \
    --core -y

echo ""
echo "Argo CD clusters:"
argocd cluster list --core

# Restore default namespace.
kubectl config set-context --current --namespace=default
