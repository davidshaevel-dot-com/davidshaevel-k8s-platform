#!/usr/bin/env bash
# Uninstall kube-prometheus-stack and clean up CRDs.

source "$(dirname "$0")/../config.sh"
setup_logging "monitoring-uninstall"

MONITORING_NAMESPACE="monitoring"

echo "Uninstalling kube-prometheus-stack..."
helm uninstall kube-prometheus-stack -n "${MONITORING_NAMESPACE}" || echo "Helm release not found, skipping."

echo ""
echo "Deleting Prometheus CRDs..."
kubectl delete crd \
    alertmanagerconfigs.monitoring.coreos.com \
    alertmanagers.monitoring.coreos.com \
    podmonitors.monitoring.coreos.com \
    probes.monitoring.coreos.com \
    prometheusagents.monitoring.coreos.com \
    prometheuses.monitoring.coreos.com \
    prometheusrules.monitoring.coreos.com \
    scrapeconfigs.monitoring.coreos.com \
    servicemonitors.monitoring.coreos.com \
    thanosrulers.monitoring.coreos.com \
    2>/dev/null || echo "Some CRDs not found, skipping."

echo ""
echo "Deleting namespace '${MONITORING_NAMESPACE}'..."
kubectl delete namespace "${MONITORING_NAMESPACE}" --ignore-not-found

echo ""
echo "Monitoring stack uninstalled."
