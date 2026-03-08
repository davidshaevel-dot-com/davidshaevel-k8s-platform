#!/usr/bin/env bash
# Show the status of the monitoring stack.

source "$(dirname "$0")/../config.sh"
setup_logging "monitoring-status"

MONITORING_NAMESPACE="monitoring"

echo "=== Helm Release ==="
helm status kube-prometheus-stack -n "${MONITORING_NAMESPACE}" 2>/dev/null || echo "Helm release not found."

echo ""
echo "=== Pods ==="
kubectl get pods -n "${MONITORING_NAMESPACE}"

echo ""
echo "=== Services ==="
kubectl get svc -n "${MONITORING_NAMESPACE}"

echo ""
echo "=== PVCs ==="
kubectl get pvc -n "${MONITORING_NAMESPACE}"
