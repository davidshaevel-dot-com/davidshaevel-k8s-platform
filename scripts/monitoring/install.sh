#!/usr/bin/env bash
# Install kube-prometheus-stack via Helm on the AKS control plane.
# Reference: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack

source "$(dirname "$0")/../config.sh"
setup_logging "monitoring-install"

MONITORING_NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Adding prometheus-community Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo ""
echo "Creating namespace '${MONITORING_NAMESPACE}'..."
kubectl create namespace "${MONITORING_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Installing kube-prometheus-stack in namespace '${MONITORING_NAMESPACE}'..."
echo "  Grafana:        ClusterIP (accessed via Teleport)"
echo "  Prometheus:     7d retention, 5Gi storage"
echo "  Alertmanager:   Disabled"
echo ""

helm upgrade --install --wait -n "${MONITORING_NAMESPACE}" kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    -f "${SCRIPT_DIR}/helm-values/monitoring/values.yaml"

echo ""
echo "Waiting for Grafana to be ready..."
kubectl rollout status deployment/kube-prometheus-stack-grafana -n "${MONITORING_NAMESPACE}" --timeout=3m

echo ""
echo "Waiting for Prometheus operator to be ready..."
kubectl rollout status deployment/kube-prometheus-stack-kube-prom-operator -n "${MONITORING_NAMESPACE}" --timeout=3m

echo ""
echo "=== Pods ==="
kubectl get pods -n "${MONITORING_NAMESPACE}"

echo ""
echo "=== Services ==="
kubectl get svc -n "${MONITORING_NAMESPACE}"

echo ""
echo "=== PVCs ==="
kubectl get pvc -n "${MONITORING_NAMESPACE}"

echo ""
echo "=== Access Grafana ==="
echo "  Port-forward:"
echo "    kubectl port-forward svc/kube-prometheus-stack-grafana -n ${MONITORING_NAMESPACE} 3000:80"
echo "    Open http://localhost:3000"
echo ""
echo "  Credentials:"
echo "    Username: admin"
echo "    Password: admin"
echo ""
echo "  Via Teleport (after registration):"
echo "    https://${TELEPORT_DOMAIN} -> grafana app"
echo ""
echo "Register Grafana in Teleport with:"
echo "  ./scripts/monitoring/teleport-register.sh"
