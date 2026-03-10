# K8s Platform Ops Experience Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy davidshaevel-website via Argo CD, set up Prometheus/Grafana monitoring, simulate and troubleshoot incidents — transforming the platform from "infrastructure I built" into "a platform I operate."

**Architecture:** Website (Next.js frontend + NestJS backend) deployed to AKS via Argo CD, monitored by kube-prometheus-stack (Prometheus + Grafana) and Hubble (ACNS). GKE deployment as stretch goal. All access via Teleport.

**Tech Stack:** Kubernetes, Argo CD, Helm, kube-prometheus-stack, Cilium/Hubble, ACR, Teleport

---

## Task 1: Start AKS Cluster and Verify Existing Services

**Files:**
- Run: `scripts/aks/start.sh`
- Run: `scripts/aks/credentials.sh`
- Run: `scripts/teleport/dns.sh`
- Run: `scripts/cilium/status.sh`

**Step 1: Start the AKS cluster**

```bash
cd /Users/dshaevel/workspace-ds/davidshaevel-k8s-platform/main
source .envrc
./scripts/aks/start.sh
```

Expected: Cluster starts (takes ~5-10 minutes).

**Step 2: Get credentials and verify nodes**

```bash
./scripts/aks/credentials.sh
```

Expected: `kubectl` configured, 1 node in `Ready` state.

**Step 3: Update DNS (LoadBalancer IP may have changed)**

```bash
./scripts/teleport/dns.sh
```

Expected: DNS records updated for `teleport.davidshaevel.com` and `*.teleport.davidshaevel.com`.

**Step 4: Verify existing services**

```bash
kubectl get pods -n teleport-cluster
kubectl get pods -n portainer
kubectl get pods -n argocd
./scripts/cilium/status.sh
```

Expected: All pods Running/Ready. Hubble relay and UI running. ACNS enabled.

**Step 5: Verify Teleport access**

Open https://teleport.davidshaevel.com in browser. Verify Portainer and Argo CD apps accessible.

**Step 6: Check ACR images are available**

```bash
az acr repository show-tags --name k8sdevplatformacr --repository davidshaevel-website/frontend --output table
az acr repository show-tags --name k8sdevplatformacr --repository davidshaevel-website/backend --output table
```

Expected: At least one tag (git short SHA) for each image. Note the tag for use in Task 2.

---

## Task 2: Create Website Kubernetes Manifests

**Files:**
- Create: `manifests/davidshaevel-website/namespace.yaml`
- Create: `manifests/davidshaevel-website/frontend.yaml`
- Create: `manifests/davidshaevel-website/backend.yaml`

**Step 1: Create namespace manifest**

Create `manifests/davidshaevel-website/namespace.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: davidshaevel-website
  labels:
    pod-security.kubernetes.io/enforce: baseline
```

**Step 2: Create frontend Deployment and Service**

Create `manifests/davidshaevel-website/frontend.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: davidshaevel-website
  labels:
    app: davidshaevel-website
    component: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: davidshaevel-website
      component: frontend
  template:
    metadata:
      labels:
        app: davidshaevel-website
        component: frontend
    spec:
      containers:
        - name: frontend
          image: k8sdevplatformacr.azurecr.io/davidshaevel-website/frontend:<TAG>
          ports:
            - containerPort: 3000
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: davidshaevel-website
spec:
  selector:
    app: davidshaevel-website
    component: frontend
  ports:
    - port: 3000
      targetPort: 3000
  type: ClusterIP
```

Replace `<TAG>` with the image tag from Task 1, Step 6.

**Step 3: Create backend Deployment and Service**

Create `manifests/davidshaevel-website/backend.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: davidshaevel-website
  labels:
    app: davidshaevel-website
    component: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: davidshaevel-website
      component: backend
  template:
    metadata:
      labels:
        app: davidshaevel-website
        component: backend
    spec:
      containers:
        - name: backend
          image: k8sdevplatformacr.azurecr.io/davidshaevel-website/backend:<TAG>
          ports:
            - containerPort: 3001
          env:
            - name: NODE_ENV
              value: production
          livenessProbe:
            httpGet:
              path: /api/health
              port: 3001
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /api/health
              port: 3001
            initialDelaySeconds: 10
            periodSeconds: 5
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: davidshaevel-website
spec:
  selector:
    app: davidshaevel-website
    component: backend
  ports:
    - port: 3001
      targetPort: 3001
  type: ClusterIP
```

Replace `<TAG>` with the same image tag.

**Step 4: Commit manifests**

```bash
git add manifests/davidshaevel-website/
git commit -m "feat(website): add Kubernetes manifests for davidshaevel-website

Deployment and Service for frontend (port 3000) and backend (port 3001)
with health checks, resource limits, and ACR image references.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Create Argo CD Application and Deploy

**Files:**
- Modify: `argocd/projects/platform.yaml` (add namespace + source repo)
- Create: `argocd/applications/davidshaevel-website.yaml`

**Step 1: Update AppProject to allow the new namespace**

In `argocd/projects/platform.yaml`, add a destination for the website namespace:

```yaml
# Add to spec.destinations:
    - namespace: davidshaevel-website
      server: https://kubernetes.default.svc
```

No new sourceRepos needed — the k8s-platform repo is already listed.

**Step 2: Create Argo CD Application manifest**

Create `argocd/applications/davidshaevel-website.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davidshaevel-website
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/davidshaevel-dot-com/davidshaevel-k8s-platform
    targetRevision: main
    path: manifests/davidshaevel-website
  destination:
    server: https://kubernetes.default.svc
    namespace: davidshaevel-website
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Note: Using automated sync (unlike Portainer which uses manual sync). This is the standard GitOps pattern — changes pushed to Git are automatically applied.

**Step 3: Apply the updated project and application**

```bash
kubectl apply -f argocd/projects/platform.yaml
kubectl apply -f argocd/applications/davidshaevel-website.yaml
```

**Step 4: Verify deployment via Argo CD**

```bash
kubectl get applications -n argocd
kubectl get pods -n davidshaevel-website
kubectl get svc -n davidshaevel-website
```

Expected: Application shows `Synced` and `Healthy`. Frontend and backend pods Running.

**Step 5: Verify app is accessible**

```bash
# Port-forward to test
kubectl port-forward svc/frontend -n davidshaevel-website 3000:3000 &
curl -s http://localhost:3000/health
# Expected: 200 OK

kubectl port-forward svc/backend -n davidshaevel-website 3001:3001 &
curl -s http://localhost:3001/api/health
# Expected: 200 OK

# Kill port-forwards
kill %1 %2
```

**Step 6: Commit Argo CD manifests**

```bash
git add argocd/projects/platform.yaml argocd/applications/davidshaevel-website.yaml
git commit -m "feat(website): add Argo CD application for davidshaevel-website

Automated sync with prune and self-heal. Deploys from
manifests/davidshaevel-website/ on main branch.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Add Network Policies for Website Namespace

**Files:**
- Modify: `manifests/cilium/namespace-isolation.yaml` (add website section)
- Modify: `scripts/cilium/apply-policies.sh` (add namespace check)

**Step 1: Add website policies to namespace-isolation.yaml**

Append to `manifests/cilium/namespace-isolation.yaml`:

```yaml

---
# =============================================================================
# DAVIDSHAEVEL-WEBSITE NAMESPACE
# =============================================================================

# Default deny all ingress to davidshaevel-website namespace.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: davidshaevel-website
spec:
  podSelector: {}
  policyTypes:
    - Ingress

---
# Allow pods within the davidshaevel-website namespace to communicate.
# Frontend needs to reach backend on port 3001.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-intra-namespace
  namespace: davidshaevel-website
spec:
  endpointSelector: {}
  ingress:
    - fromEndpoints:
        - {}
```

Note: No external ingress rule needed — the website is accessed via Teleport app proxy, which runs in teleport-cluster namespace. We'll add a `allow-from-teleport` rule if needed after verifying access patterns.

**Step 2: Update apply-policies.sh to check the new namespace**

In `scripts/cilium/apply-policies.sh`, change the namespace check loop:

```bash
# Change:
for ns in portainer teleport-cluster; do
# To:
for ns in portainer teleport-cluster davidshaevel-website; do
```

Same change in the stale allow-dns cleanup loop.

**Step 3: Apply policies**

```bash
./scripts/cilium/apply-policies.sh
```

Expected: Policies applied. All 3 namespaces show NetworkPolicies and CiliumNetworkPolicies.

**Step 4: Verify app still works after policies**

```bash
kubectl port-forward svc/frontend -n davidshaevel-website 3000:3000 &
curl -s http://localhost:3000/health
kill %1
```

Expected: Still works — intra-namespace allows frontend↔backend, port-forward bypasses ingress policy.

**Step 5: Commit**

```bash
git add manifests/cilium/namespace-isolation.yaml scripts/cilium/apply-policies.sh
git commit -m "feat(cilium): add network policies for davidshaevel-website namespace

Default deny ingress + allow intra-namespace communication.
Same pattern as portainer and teleport-cluster namespaces.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Install Prometheus and Grafana

**Files:**
- Create: `helm-values/monitoring/values.yaml`
- Create: `scripts/monitoring/install.sh`
- Create: `scripts/monitoring/uninstall.sh`
- Create: `scripts/monitoring/status.sh`

**Step 1: Create Helm values for kube-prometheus-stack**

Create `helm-values/monitoring/values.yaml`:

```yaml
# kube-prometheus-stack Helm values for AKS.
# Chart: prometheus-community/kube-prometheus-stack
# Reference: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack

# Grafana — ClusterIP, accessed via Teleport.
grafana:
  service:
    type: ClusterIP
  adminPassword: "admin"
  # Persistence for dashboards and settings.
  persistence:
    enabled: true
    size: 1Gi

# Prometheus — keep defaults, adjust retention for dev cluster.
prometheus:
  prometheusSpec:
    retention: 7d
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

# Node exporter — enabled by default, provides node-level metrics.
nodeExporter:
  enabled: true

# kube-state-metrics — enabled by default, provides K8s object metrics.
kubeStateMetrics:
  enabled: true

# Alertmanager — disable for now (no alert destinations configured).
alertmanager:
  enabled: false
```

**Step 2: Create install script**

Create `scripts/monitoring/install.sh`:

```bash
#!/usr/bin/env bash
# Install kube-prometheus-stack (Prometheus + Grafana) via Helm.

source "$(dirname "$0")/../config.sh"
setup_logging "monitoring-install"

MONITORING_NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "Adding Prometheus community Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo ""
echo "Creating namespace '${MONITORING_NAMESPACE}'..."
kubectl create namespace "${MONITORING_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Installing kube-prometheus-stack in namespace '${MONITORING_NAMESPACE}'..."
echo "  Grafana:      ClusterIP (accessed via Teleport)"
echo "  Prometheus:    7d retention, 5Gi storage"
echo "  Alertmanager:  Disabled"
echo ""

helm upgrade --install --wait -n "${MONITORING_NAMESPACE}" kube-prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    -f "${SCRIPT_DIR}/helm-values/monitoring/values.yaml" \
    --timeout 10m

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
echo "Monitoring stack installed."
echo ""
echo "To access Grafana:"
echo "  kubectl port-forward svc/kube-prometheus-stack-grafana -n ${MONITORING_NAMESPACE} 3000:80"
echo "  Open http://localhost:3000"
echo "  Login: admin / admin"
echo ""
echo "To register Grafana in Teleport, run:"
echo "  ./scripts/monitoring/teleport-register.sh"
```

```bash
chmod +x scripts/monitoring/install.sh
```

**Step 3: Create uninstall script**

Create `scripts/monitoring/uninstall.sh`:

```bash
#!/usr/bin/env bash
# Uninstall kube-prometheus-stack.

source "$(dirname "$0")/../config.sh"
setup_logging "monitoring-uninstall"

MONITORING_NAMESPACE="monitoring"

echo "Uninstalling kube-prometheus-stack..."
helm uninstall kube-prometheus-stack -n "${MONITORING_NAMESPACE}" --wait

# CRDs are not removed by helm uninstall. Remove them manually.
echo ""
echo "Removing Prometheus CRDs..."
kubectl delete crd alertmanagerconfigs.monitoring.coreos.com --ignore-not-found=true
kubectl delete crd alertmanagers.monitoring.coreos.com --ignore-not-found=true
kubectl delete crd podmonitors.monitoring.coreos.com --ignore-not-found=true
kubectl delete crd probes.monitoring.coreos.com --ignore-not-found=true
kubectl delete crd prometheusagents.monitoring.coreos.com --ignore-not-found=true
kubectl delete crd prometheuses.monitoring.coreos.com --ignore-not-found=true
kubectl delete crd prometheusrules.monitoring.coreos.com --ignore-not-found=true
kubectl delete crd scrapeconfigs.monitoring.coreos.com --ignore-not-found=true
kubectl delete crd servicemonitors.monitoring.coreos.com --ignore-not-found=true
kubectl delete crd thanosrulers.monitoring.coreos.com --ignore-not-found=true

echo ""
echo "Deleting namespace '${MONITORING_NAMESPACE}'..."
kubectl delete namespace "${MONITORING_NAMESPACE}" --ignore-not-found=true

echo ""
echo "Monitoring stack uninstalled."
```

```bash
chmod +x scripts/monitoring/uninstall.sh
```

**Step 4: Create status script**

Create `scripts/monitoring/status.sh`:

```bash
#!/usr/bin/env bash
# Show monitoring stack status.

source "$(dirname "$0")/../config.sh"
setup_logging "monitoring-status"

MONITORING_NAMESPACE="monitoring"

echo "=== Pods ==="
kubectl get pods -n "${MONITORING_NAMESPACE}" -o wide

echo ""
echo "=== Services ==="
kubectl get svc -n "${MONITORING_NAMESPACE}"

echo ""
echo "=== PVCs ==="
kubectl get pvc -n "${MONITORING_NAMESPACE}"

echo ""
echo "=== Helm Release ==="
helm list -n "${MONITORING_NAMESPACE}"
```

```bash
chmod +x scripts/monitoring/status.sh
```

**Step 5: Run the install**

```bash
./scripts/monitoring/install.sh
```

Expected: All pods running. Grafana, Prometheus, node-exporter, kube-state-metrics pods visible.

**Step 6: Verify Grafana is accessible**

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 &
# Open http://localhost:3000, login admin/admin
# Browse built-in dashboards: Dashboards -> Browse
# Look for: Kubernetes / Compute Resources / Namespace (Pods), Node Exporter / Nodes
kill %1
```

**Step 7: Commit**

```bash
git add helm-values/monitoring/ scripts/monitoring/
git commit -m "feat(monitoring): install kube-prometheus-stack with Grafana

Prometheus (7d retention, 5Gi storage) + Grafana (ClusterIP) + node-exporter
+ kube-state-metrics. Alertmanager disabled. Accessed via port-forward or Teleport.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Register Grafana in Teleport

**Files:**
- Create: `scripts/monitoring/teleport-register.sh`

**Step 1: Create Teleport registration script**

Create `scripts/monitoring/teleport-register.sh`:

```bash
#!/usr/bin/env bash
# Register Grafana as a Teleport application.
# Upgrades the existing teleport-agent Helm release to include Grafana.

source "$(dirname "$0")/../config.sh"
setup_logging "monitoring-teleport-register"

TELEPORT_NAMESPACE="teleport-cluster"
MONITORING_NAMESPACE="monitoring"

# Verify Teleport agent is installed.
if ! helm status teleport-agent -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Teleport agent not found. Run ./scripts/teleport/aks-agent-install.sh first."
    exit 1
fi

# Get the current chart version to match.
TELEPORT_VERSION=$(helm list -n "${TELEPORT_NAMESPACE}" -o json | jq -r '.[] | select(.name=="teleport-agent") | .app_version')
echo "Teleport agent version: ${TELEPORT_VERSION}"

echo ""
echo "Upgrading teleport-agent to register Grafana app..."
echo "  Apps: portainer + argocd + grafana"
echo "  Grafana URI: http://kube-prometheus-stack-grafana.${MONITORING_NAMESPACE}.svc.cluster.local"
echo ""

# Explicitly set all apps to avoid Helm array merge issues with --reuse-values.
helm upgrade teleport-agent teleport/teleport-kube-agent \
    -n "${TELEPORT_NAMESPACE}" \
    --reuse-values \
    --set "apps[0].name=portainer" \
    --set "apps[0].uri=https://portainer.portainer.svc.cluster.local:9443" \
    --set "apps[0].insecure_skip_verify=true" \
    --set "apps[1].name=argocd" \
    --set "apps[1].uri=http://argocd-server.argocd.svc.cluster.local" \
    --set "apps[2].name=grafana" \
    --set "apps[2].uri=http://kube-prometheus-stack-grafana.${MONITORING_NAMESPACE}.svc.cluster.local" \
    --version="${TELEPORT_VERSION}" \
    --wait

echo ""
echo "Waiting for agent pod to be ready..."
kubectl rollout status statefulset/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || kubectl rollout status deployment/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || kubectl rollout status daemonset/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || echo "Warning: Could not verify agent rollout. Check manually."

echo ""
echo "=== Registered Apps ==="
kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- tctl apps ls

echo ""
echo "Grafana is now accessible via Teleport:"
echo "  https://${TELEPORT_DOMAIN} -> grafana app"
```

```bash
chmod +x scripts/monitoring/teleport-register.sh
```

**Step 2: Run the registration**

```bash
./scripts/monitoring/teleport-register.sh
```

Expected: Teleport agent upgraded. `tctl apps ls` shows portainer, argocd, and grafana.

**Step 3: Verify Grafana via Teleport**

Open https://teleport.davidshaevel.com, navigate to Grafana app. Login admin/admin.

**Step 4: Add network policy for monitoring namespace**

This may be needed if Teleport can't reach Grafana. Add to `manifests/cilium/namespace-isolation.yaml`:

```yaml

---
# =============================================================================
# MONITORING NAMESPACE
# =============================================================================

# Default deny all ingress to monitoring namespace.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: monitoring
spec:
  podSelector: {}
  policyTypes:
    - Ingress

---
# Allow pods within the monitoring namespace to communicate.
# Prometheus needs to scrape node-exporter and kube-state-metrics.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-intra-namespace
  namespace: monitoring
spec:
  endpointSelector: {}
  ingress:
    - fromEndpoints:
        - {}

---
# Allow ingress from teleport-cluster namespace to Grafana on port 3000.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-from-teleport
  namespace: monitoring
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: grafana
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: teleport-cluster
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP

---
# Allow Prometheus to scrape pods in other namespaces.
# Prometheus needs to reach pod metrics endpoints across all namespaces.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: davidshaevel-website
spec:
  endpointSelector: {}
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: monitoring
```

Update `scripts/cilium/apply-policies.sh` namespace list to include `monitoring`.

**Step 5: Apply and commit**

```bash
./scripts/cilium/apply-policies.sh
git add scripts/monitoring/teleport-register.sh manifests/cilium/namespace-isolation.yaml scripts/cilium/apply-policies.sh
git commit -m "feat(monitoring): register Grafana in Teleport and add network policies

Grafana accessible via Teleport app proxy. Network policies for monitoring
namespace: default deny, intra-namespace, allow-from-teleport for Grafana,
allow Prometheus to scrape davidshaevel-website pods.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Explore Dashboards and ACNS Observability

This is an exploration task — no code changes, just learning what's available.

**Step 1: Explore Grafana built-in dashboards**

Open Grafana (via Teleport or port-forward). Navigate to Dashboards -> Browse. Key dashboards to find:

- **Kubernetes / Compute Resources / Cluster** — cluster-wide CPU, memory, network
- **Kubernetes / Compute Resources / Namespace (Pods)** — per-namespace resource usage
- **Kubernetes / Compute Resources / Pod** — individual pod metrics
- **Node Exporter / Nodes** — node-level CPU, memory, disk, network
- **Kubernetes / Networking / Namespace (Pods)** — network traffic per namespace

Filter to `davidshaevel-website` namespace and observe your app's metrics.

**Step 2: Explore ACNS / Hubble metrics**

Check if ACNS exposes Prometheus metrics that Grafana can scrape:

```bash
# Check if hubble-relay exposes metrics
kubectl get svc -n kube-system | grep hubble
kubectl describe svc hubble-relay -n kube-system

# Check for any Azure-provided monitoring
az aks show --resource-group k8s-developer-platform-rg --name k8s-developer-platform-aks \
    --query "azureMonitorProfile" -o json

# Check for any Grafana dashboards related to Cilium/Hubble
# In Grafana: search dashboards for "cilium" or "hubble"
```

**Step 3: Use Hubble CLI for live network flows**

```bash
# If cilium CLI is installed:
cilium hubble observe --namespace davidshaevel-website

# Or port-forward to hubble-relay and use hubble CLI:
kubectl port-forward svc/hubble-relay -n kube-system 4245:443 &
hubble observe --namespace davidshaevel-website
```

**Step 4: Open Hubble UI**

```bash
kubectl port-forward svc/hubble-ui -n kube-system 12000:80 &
# Open http://localhost:12000
# Select davidshaevel-website namespace
# Generate traffic: curl http://localhost:3000 (in another terminal with frontend port-forwarded)
# Observe the network flow graph
```

**Step 5: Take notes on what you found**

Document which dashboards are most useful, what ACNS provides, and what gaps exist. This becomes interview talking material.

---

## Task 8: Simulate Application-Level Incident

**Goal:** Push a bad config via Argo CD, observe the failure in Grafana, troubleshoot, and roll back.

**Step 1: Observe baseline in Grafana**

Open the "Kubernetes / Compute Resources / Namespace (Pods)" dashboard filtered to `davidshaevel-website`. Note the normal state: 2 pods, stable CPU/memory, no restarts.

**Step 2: Push a bad image tag**

Edit `manifests/davidshaevel-website/frontend.yaml` — change the image tag to a nonexistent one:

```yaml
image: k8sdevplatformacr.azurecr.io/davidshaevel-website/frontend:does-not-exist
```

Commit and push. Argo CD auto-sync will pick this up.

```bash
git add manifests/davidshaevel-website/frontend.yaml
git commit -m "break(website): intentional bad image tag for incident simulation

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push
```

**Step 3: Observe the failure**

```bash
# Watch pods — expect ImagePullBackOff
kubectl get pods -n davidshaevel-website -w

# Check Argo CD application status
kubectl get applications -n argocd
```

In Grafana: watch for pod restart count increasing, new pod stuck in Pending/ImagePullBackOff.

**Step 4: Troubleshoot (practice narrating)**

Narrate out loud as if interviewers are watching:

```bash
# "I can see the pod is in ImagePullBackOff. Let me check the events."
kubectl describe pod -n davidshaevel-website -l component=frontend

# "The error shows the image tag doesn't exist in ACR. Let me verify."
az acr repository show-tags --name k8sdevplatformacr --repository davidshaevel-website/frontend

# "I can see the available tags. The deployment has a typo. Let me check
# the Argo CD application to see what changed."
kubectl get application davidshaevel-website -n argocd -o yaml | grep -A5 "status:"
```

**Step 5: Roll back via Argo CD**

Fix the image tag back to the correct value. Commit and push.

```bash
# Fix the image tag
# Edit manifests/davidshaevel-website/frontend.yaml back to correct tag
git add manifests/davidshaevel-website/frontend.yaml
git commit -m "fix(website): restore correct image tag after incident simulation

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
git push
```

Watch Argo CD auto-sync and pods recover.

**Step 6: Verify recovery in Grafana**

Confirm pods are back to Running, restarts stabilized, metrics normal.

---

## Task 9: Simulate Network-Level Incident (Multi-Cloud)

**Goal:** Block backend→database traffic on both AKS and GKE, diagnose with each cluster's observability tools, fix. Same incident, different tools and policy types — demonstrates cross-cloud troubleshooting.

**Why backend→database:** The original plan blocked frontend→backend, but the frontend is a static Next.js app with no server-side calls to the backend. The backend→database flow (port 5432) is the most active inter-pod dependency — blocking it causes the backend health check to fail, triggering pod restarts visible in Grafana.

**Cross-cloud comparison:**

| | AKS | GKE |
|---|---|---|
| **Block with** | CiliumNetworkPolicy | Standard Kubernetes NetworkPolicy |
| **Diagnose with** | Hubble CLI (mTLS) + Hubble UI + Grafana | Hubble CLI (`kubectl exec`) + GCP Console |
| **See drops in** | Hubble UI (red lines) + Cilium Agent Metrics dashboard | GCP Console → Observability → Traffic flows |
| **Fix by** | `kubectl delete cnp` | `kubectl delete networkpolicy` |

---

### Part A: AKS Incident

**Step 1: Open observability tools (AKS)**

Ensure kubectl context is AKS. Open in separate tabs/terminals:
- Grafana: "Kubernetes / Compute Resources / Namespace (Pods)" filtered to `davidshaevel-website`
- Hubble UI: http://localhost:12000 → `davidshaevel-website` namespace
- Hubble CLI (optional):

```bash
# Port-forward hubble-relay (if not already running)
kubectl port-forward -n kube-system svc/hubble-relay 4245:443 &

# Port-forward Hubble UI (if not already running)
kubectl port-forward -n kube-system svc/hubble-ui 12000:80 &

# Observe flows with mTLS
hubble observe --namespace davidshaevel-website --follow \
  --tls --tls-ca-cert-files /tmp/hubble-ca.crt \
  --tls-client-cert-file /tmp/hubble-client.crt \
  --tls-client-key-file /tmp/hubble-client.key \
  --tls-server-name "*.hubble-relay.cilium.io"
```

**Step 2: Verify AKS baseline**

Note the normal state: backend pods are healthy, backend→database:5432 flows show FORWARDED in Hubble, no restarts in Grafana.

```bash
kubectl get pods -n davidshaevel-website
# Expected: frontend, backend, database all Running/Ready
```

**Step 3: Apply blocking policy (CiliumNetworkPolicy on AKS)**

Create a CiliumNetworkPolicy that restricts database ingress to only database→database, blocking backend→database:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: block-backend-to-database
  namespace: davidshaevel-website
spec:
  endpointSelector:
    matchLabels:
      component: database
  ingress:
    - fromEndpoints:
        - matchLabels:
            component: database
EOF
```

**Step 4: Observe the failure (AKS)**

```bash
# Watch pods — expect backend to start failing health checks and restarting
kubectl get pods -n davidshaevel-website -w

# Check Hubble flows — look for DROPPED packets on port 5432
hubble observe --namespace davidshaevel-website --verdict DROPPED \
  --tls --tls-ca-cert-files /tmp/hubble-ca.crt \
  --tls-client-cert-file /tmp/hubble-client.crt \
  --tls-client-key-file /tmp/hubble-client.key \
  --tls-server-name "*.hubble-relay.cilium.io"
```

In Grafana: watch for pod restart count increasing on the backend.
In Hubble UI: red lines (dropped flows) from backend to database.

**Step 5: Troubleshoot AKS (practice narrating)**

```bash
# "I can see the backend pod is restarting. Let me check its logs."
kubectl logs -n davidshaevel-website -l component=backend --tail=20

# "Connection refused to the database. Let me check Hubble for dropped flows."
# (Hubble shows DROPPED on port 5432 from backend to database)

# "There are dropped packets between backend and database. Let me check network policies."
kubectl get ciliumnetworkpolicies -n davidshaevel-website

# "There's a block-backend-to-database policy. Let me inspect it."
kubectl describe ciliumnetworkpolicy block-backend-to-database -n davidshaevel-website

# "This policy is restricting database ingress to only database pods.
# Backend traffic to port 5432 is being denied. Let me remove this policy."
```

**Step 6: Fix AKS by removing the blocking policy**

```bash
kubectl delete ciliumnetworkpolicy block-backend-to-database -n davidshaevel-website
```

**Step 7: Verify AKS recovery**

```bash
# Watch pods recover
kubectl get pods -n davidshaevel-website -w

# Hubble flows should show FORWARDED packets to database again
hubble observe --namespace davidshaevel-website --verdict FORWARDED \
  --tls --tls-ca-cert-files /tmp/hubble-ca.crt \
  --tls-client-cert-file /tmp/hubble-client.crt \
  --tls-client-key-file /tmp/hubble-client.key \
  --tls-server-name "*.hubble-relay.cilium.io"
```

In Grafana: confirm backend pod restarts stabilize, CPU/memory return to baseline.

---

### Part B: GKE Incident

**Step 8: Switch to GKE context**

```bash
gcloud container clusters get-credentials k8s-developer-platform-gke \
  --zone us-central1-a --project <project-id>
```

**Step 9: Verify GKE baseline**

```bash
kubectl get pods -n davidshaevel-website
# Expected: frontend, backend, database all Running/Ready

# Confirm normal flows
kubectl exec -it -n gke-managed-dpv2-observability \
  deployment/hubble-relay -c hubble-cli -- \
  hubble observe --namespace davidshaevel-website --last 10
```

**Step 10: Apply blocking policy (Kubernetes NetworkPolicy on GKE)**

GKE Standard doesn't have CiliumNetworkPolicy CRDs — use standard Kubernetes NetworkPolicy instead. Same effect, different API:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-backend-to-database
  namespace: davidshaevel-website
spec:
  podSelector:
    matchLabels:
      component: database
  ingress:
    - from:
        - podSelector:
            matchLabels:
              component: database
EOF
```

**Step 11: Observe the failure (GKE)**

```bash
# Watch pods — expect backend to start failing health checks and restarting
kubectl get pods -n davidshaevel-website -w

# Check Hubble flows — look for DROPPED packets on port 5432
kubectl exec -it -n gke-managed-dpv2-observability \
  deployment/hubble-relay -c hubble-cli -- \
  hubble observe --namespace davidshaevel-website --verdict DROPPED
```

In GCP Console: Observability → Traffic flows → check the "Number of egress flows, drop reasons" chart (should now show data).

**Step 12: Troubleshoot GKE (practice narrating)**

```bash
# "Backend is restarting on GKE. Let me check logs."
kubectl logs -n davidshaevel-website -l component=backend --tail=20

# "Same pattern — connection refused to database. Let me check Hubble."
# (Hubble shows DROPPED on port 5432)

# "On GKE we use standard NetworkPolicy, not CiliumNetworkPolicy."
kubectl get networkpolicies -n davidshaevel-website

# "There's a block-backend-to-database NetworkPolicy. Let me inspect it."
kubectl describe networkpolicy block-backend-to-database -n davidshaevel-website

# "Same issue — database ingress restricted to database pods only.
# Backend can't reach port 5432. Removing the policy."
```

**Step 13: Fix GKE by removing the blocking policy**

```bash
kubectl delete networkpolicy block-backend-to-database -n davidshaevel-website
```

**Step 14: Verify GKE recovery**

```bash
# Watch pods recover
kubectl get pods -n davidshaevel-website -w

# Hubble flows should show FORWARDED packets to database again
kubectl exec -it -n gke-managed-dpv2-observability \
  deployment/hubble-relay -c hubble-cli -- \
  hubble observe --namespace davidshaevel-website --verdict FORWARDED
```

In GCP Console: drop reasons chart should return to zero.

---

### Interview Talking Point

**Cross-cloud incident response:** "I simulated the same network incident on both clusters — blocking backend→database traffic. On AKS, I used a CiliumNetworkPolicy and diagnosed it with the Hubble CLI over mTLS, the Hubble UI service map showing red drop lines, and the Cilium Agent Metrics dashboard in Grafana. On GKE, I used a standard Kubernetes NetworkPolicy and diagnosed it by exec'ing into the managed Hubble relay pod and checking the GCP Console traffic flows. The debugging workflow was identical — see restarts, check Hubble for drops, find the bad policy, remove it — but the tools and policy APIs differed. That's the operational reality of multi-cloud: same concepts, different implementations."

No commit needed — this was a live simulation, not a persisted change.

---

## Task 10: GKE Stretch Goal — Multi-Cloud Deployment ✅

**Completed 2026-03-09.** Full implementation plan and execution tracked in TT-263 and `docs/plans/2026-03-09-gke-multi-cloud-deployment.md`.

**Only do this if time permits after Tasks 1–9 are complete.**

**Files:**
- Create: `argocd/applications/davidshaevel-website-gke.yaml`

**Step 1: Start GKE cluster**

```bash
./scripts/gke/start.sh
```

**Step 2: Verify GKE is accessible via Portainer/Teleport**

Check that Portainer shows the GKE environment and it's reachable.

**Step 3: Register GKE as an Argo CD cluster**

```bash
# Get GKE credentials
gcloud container clusters get-credentials k8s-developer-platform-gke --zone us-central1-a --project $(grep GCP_PROJECT .envrc | cut -d= -f2 | tr -d '"')

# Use argocd CLI to add the cluster (requires argocd CLI installed)
# Or create a Secret manually — this step may need research
```

Note: Adding external clusters to Argo CD requires either the `argocd` CLI or creating a cluster Secret. Research the exact approach during implementation.

**Step 4: Create GKE Application manifest**

Create `argocd/applications/davidshaevel-website-gke.yaml` pointing to the GKE cluster with the same manifests path. The image will need to be pullable from GKE — ACR credentials or image replication to GCR may be needed.

**Step 5: Verify deployment on GKE**

```bash
kubectl --context <gke-context> get pods -n davidshaevel-website
```

**Step 6: Commit and push**

```bash
git add argocd/applications/davidshaevel-website-gke.yaml
git commit -m "feat(website): add Argo CD application for GKE multi-cloud deployment

Same manifests deployed to both AKS and GKE for operational consistency.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 11: Update Project Documentation

**Files:**
- Modify: `CLAUDE.md` (add monitoring section, update architecture diagram)
- Modify: `CLAUDE.local.md` (add monitoring details)

**Step 1: Update CLAUDE.md**

- Add monitoring namespace to architecture diagram
- Add davidshaevel-website namespace to architecture diagram
- Add Grafana to helpful commands section
- Add monitoring scripts to repository structure
- Update Learning Path progress (Module 6 partially complete)

**Step 2: Update CLAUDE.local.md**

- Add monitoring section (Grafana URL, credentials)
- Update cost estimates (Prometheus PV storage)

**Step 3: Commit**

```bash
git add CLAUDE.md CLAUDE.local.md
git commit -m "docs(platform): update docs with monitoring and website deployment

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 12: Push to Remote and Stop Cluster

**Step 1: Push all commits**

```bash
git push
```

**Step 2: Stop AKS cluster (if done for the day)**

```bash
./scripts/aks/stop.sh
```

Note: Stopping the cluster will tear down pods, but PVCs persist. On next start, all Helm releases will recreate pods. Argo CD auto-sync will redeploy the website.
