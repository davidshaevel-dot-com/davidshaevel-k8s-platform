# GKE Multi-Cloud Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy davidshaevel-website to GKE via the same Argo CD on AKS, with Teleport access and Cilium network policies.

**Architecture:** Single Argo CD on AKS manages two Applications — `davidshaevel-website-aks` (local) and `davidshaevel-website-gke` (remote). GKE pulls images from ACR via an image pull secret. Both sites accessible via Teleport app proxy.

**Tech Stack:** Kubernetes, Argo CD, Helm, Teleport, Cilium, ACR, GKE

**Key Design Decisions:**
- **Cluster name references:** AppProject and Application manifests reference GKE by `name: k8s-developer-platform-gke` instead of the API server IP. This means committed YAML never changes when GKE is deleted and recreated with a new IP.
- **`argocd --core` mode:** The GKE start script uses `argocd cluster add --core` to register GKE without needing the Argo CD admin password. This talks directly to the Kubernetes API via kubeconfig.
- **GKE restart automation:** `gke/start.sh` is extended with steps 5-8 to handle Argo CD registration, ACR pull secret, network policies, and Teleport website registration — making `./scripts/gke/start.sh` a single command that fully rebuilds the GKE environment.

---

## Task 1: Start Both Clusters ✅

**Step 1: Start AKS cluster**

```bash
cd /Users/dshaevel/workspace-ds/davidshaevel-k8s-platform/main
source .envrc
./scripts/aks/start.sh
```

Expected: AKS cluster starts (~5-10 minutes).

**Step 2: Get AKS credentials and update DNS**

```bash
./scripts/aks/credentials.sh
./scripts/teleport/dns.sh
```

**Step 3: Verify AKS services are healthy**

```bash
kubectl get pods -n argocd
kubectl get pods -n davidshaevel-website
kubectl get pods -n monitoring
kubectl get pods -n teleport-cluster
```

Expected: All pods Running.

**Step 4: Start GKE cluster**

```bash
./scripts/gke/start.sh
```

This runs `create.sh` + Portainer agent install + Teleport agent install. Takes ~5-10 minutes. Note: GKE `start.sh` does a full rebuild (create + agents) since GKE clusters are deleted when stopped, not paused.

**Step 5: Verify GKE is healthy**

```bash
# Switch to GKE context
gcloud container clusters get-credentials k8s-developer-platform-gke --zone us-central1-a --project "${GCP_PROJECT}"
kubectl get nodes
kubectl get pods -n teleport-cluster
```

Expected: 1 node Ready, Teleport agent Running.

**Step 6: Switch back to AKS context**

```bash
az aks get-credentials --resource-group k8s-developer-platform-rg --name k8s-developer-platform-aks --overwrite-existing
```

---

## Task 2: Rename AKS Website in Argo CD and Teleport ✅

**Files:**
- Rename: `argocd/applications/davidshaevel-website.yaml` -> `argocd/applications/davidshaevel-website-aks.yaml`
- Modify: `scripts/website/teleport-register.sh`
- Modify: `scripts/monitoring/teleport-register.sh`

**Step 1: Delete the old Argo CD Application**

The old Application `davidshaevel-website` must be deleted before creating the new one, since they manage the same namespace. Deleting an Argo CD Application does NOT delete the managed resources when the deletion policy is default (non-cascade).

```bash
kubectl delete application davidshaevel-website -n argocd
```

Verify the website pods are still running (they should be — Argo CD deletion doesn't cascade by default):

```bash
kubectl get pods -n davidshaevel-website
```

**Step 2: Rename the Argo CD Application manifest**

Rename file `argocd/applications/davidshaevel-website.yaml` to `argocd/applications/davidshaevel-website-aks.yaml`.

Update `metadata.name` from `davidshaevel-website` to `davidshaevel-website-aks`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davidshaevel-website-aks
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

**Step 3: Apply the renamed Application**

```bash
kubectl apply -f argocd/applications/davidshaevel-website-aks.yaml
```

Verify:

```bash
kubectl get applications -n argocd
```

Expected: `davidshaevel-website-aks` shows Synced/Healthy.

**Step 4: Update Teleport app name from `davidshaevel-website` to `davidshaevel-website-aks`**

In `scripts/website/teleport-register.sh`, change:
- `apps[2].name=davidshaevel-website` to `apps[2].name=davidshaevel-website-aks`
- Update echo messages to say `davidshaevel-website-aks`

In `scripts/monitoring/teleport-register.sh`, change:
- `apps[2].name=davidshaevel-website` to `apps[2].name=davidshaevel-website-aks`
- Update echo messages to say `davidshaevel-website-aks`

**Step 5: Run the monitoring teleport-register script to apply the rename**

Use the monitoring script since it's the latest and includes all 4 apps:

```bash
./scripts/monitoring/teleport-register.sh
```

Verify the app name changed:

```bash
kubectl exec -n teleport-cluster deployment/teleport-cluster-auth -- tctl apps ls
```

Expected: `davidshaevel-website-aks` (not `davidshaevel-website`).

**Step 6: Verify access**

Open `https://davidshaevel-website-aks.teleport.davidshaevel.com` in browser and confirm the website loads.

**Step 7: Commit**

```bash
git add argocd/applications/davidshaevel-website-aks.yaml scripts/website/teleport-register.sh scripts/monitoring/teleport-register.sh
git rm argocd/applications/davidshaevel-website.yaml
git commit -m "refactor(website): rename to davidshaevel-website-aks for multi-cloud consistency

Rename Argo CD Application and Teleport app from davidshaevel-website
to davidshaevel-website-aks in preparation for adding GKE deployment.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-263"
```

---

## Task 3: Register GKE as Argo CD Remote Cluster ✅ (partially — cluster added, AppProject updated)

Uses `argocd --core` mode to avoid needing the admin password or port-forwarding.

**Step 1: Install argocd CLI (if not installed)**

```bash
brew install argocd
```

Or download from GitHub releases.

**Step 2: Add GKE cluster to Argo CD**

```bash
argocd cluster add gke_dev-david-024680_us-central1-a_k8s-developer-platform-gke \
    --name k8s-developer-platform-gke --core -y
```

This creates a ServiceAccount and ClusterRoleBinding on GKE, and stores the credentials as a Secret in the `argocd` namespace on AKS.

Verify:

```bash
argocd cluster list --core
```

Expected: Two clusters — `https://kubernetes.default.svc` (AKS, in-cluster) and the GKE API server URL with name `k8s-developer-platform-gke`.

**Step 3: Update AppProject to allow GKE destinations (by name, not IP)**

In `argocd/projects/platform.yaml`, add GKE destination using cluster name:

```yaml
destinations:
  - namespace: portainer
    server: https://kubernetes.default.svc
  - namespace: argocd
    server: https://kubernetes.default.svc
  - namespace: davidshaevel-website
    server: https://kubernetes.default.svc
  - namespace: davidshaevel-website
    name: k8s-developer-platform-gke
```

Apply:

```bash
kubectl apply -f argocd/projects/platform.yaml
```

**Step 4: Commit**

```bash
git add argocd/projects/platform.yaml
git commit -m "feat(argocd): add GKE cluster to platform project destinations

Allow Argo CD to deploy to the davidshaevel-website namespace on GKE.
Uses cluster name reference so YAML is stable across GKE recreates.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-263"
```

---

## Task 4: Set Up ACR Image Pull Secret on GKE

**Files:**
- Create: `scripts/gke/acr-pull-secret.sh`

**Step 1: Create an ACR service principal (or reuse existing)**

Check if the `github-k8s-platform` SP can be reused:

```bash
az ad sp list --display-name github-k8s-platform --query "[].{appId:appId, displayName:displayName}" -o table
```

If reusing, get the app ID. If creating a new one:

```bash
az ad sp create-for-rbac --name acr-pull-gke --role AcrPull --scopes /subscriptions/<sub-id>/resourceGroups/k8s-developer-platform-rg/providers/Microsoft.ContainerRegistry/registries/k8sdevplatformacr
```

**Step 2: Create `scripts/gke/acr-pull-secret.sh`**

This script will be called by `gke/start.sh` on every GKE rebuild. It:
- Switches to GKE context
- Creates the `davidshaevel-website` namespace (idempotent)
- Creates the `acr-pull-secret` docker-registry secret
- Patches the default service account with `imagePullSecrets`
- Switches back to AKS context

Requires env vars: `ACR_SP_APP_ID` and `ACR_SP_PASSWORD` in `.envrc`.

**Step 3: Run the script**

```bash
./scripts/gke/acr-pull-secret.sh
```

Verify:

```bash
# On GKE
kubectl get serviceaccount default -n davidshaevel-website -o yaml
```

Expected: `imagePullSecrets` includes `acr-pull-secret`.

No commit of secrets — this is infrastructure config. The script itself is committed.

---

## Task 5: Create GKE Argo CD Application

**Files:**
- Create: `argocd/applications/davidshaevel-website-gke.yaml`

**Step 1: Create the GKE Application manifest**

Uses cluster name (not IP) so the manifest is stable across GKE recreates:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: davidshaevel-website-gke
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/davidshaevel-dot-com/davidshaevel-k8s-platform
    targetRevision: main
    path: manifests/davidshaevel-website
  destination:
    name: k8s-developer-platform-gke
    namespace: davidshaevel-website
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Step 2: Apply and verify**

```bash
kubectl apply -f argocd/applications/davidshaevel-website-gke.yaml
kubectl get applications -n argocd
```

Expected: `davidshaevel-website-gke` appears. Wait for sync.

**Step 3: Check pods on GKE**

```bash
gcloud container clusters get-credentials k8s-developer-platform-gke --zone us-central1-a --project "${GCP_PROJECT}"
kubectl get pods -n davidshaevel-website
```

Expected: frontend, backend, and database pods Running. If image pull fails, check the pull secret from Task 4.

**Step 4: Switch back to AKS**

```bash
az aks get-credentials --resource-group k8s-developer-platform-rg --name k8s-developer-platform-aks --overwrite-existing
```

**Step 5: Commit**

```bash
git add argocd/applications/davidshaevel-website-gke.yaml
git commit -m "feat(website): add Argo CD application for GKE multi-cloud deployment

Same manifests deployed to both AKS and GKE via single Argo CD instance.
Uses cluster name reference so manifest is stable across GKE recreates.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-263"
```

---

## Task 6: Apply Network Policies on GKE

**Files:**
- Create: `manifests/cilium/gke-namespace-isolation.yaml`

**Step 1: Create GKE network policies manifest**

Create `manifests/cilium/gke-namespace-isolation.yaml`:

```yaml
# Network policies for GKE davidshaevel-website namespace.
#
# GKE uses Dataplane V2 (Cilium-based), so CiliumNetworkPolicy works natively.
# Subset of AKS policies — no Prometheus scrape rule (monitoring only on AKS).

---
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

---
# Allow ingress from teleport-cluster namespace to frontend on port 3000.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-from-teleport
  namespace: davidshaevel-website
spec:
  endpointSelector:
    matchLabels:
      component: frontend
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: teleport-cluster
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
```

**Step 2: Apply on GKE**

```bash
gcloud container clusters get-credentials k8s-developer-platform-gke --zone us-central1-a --project "${GCP_PROJECT}"
kubectl apply -f manifests/cilium/gke-namespace-isolation.yaml
```

Verify:

```bash
kubectl get networkpolicies -n davidshaevel-website
kubectl get ciliumnetworkpolicies -n davidshaevel-website
```

Expected: 1 NetworkPolicy (default-deny-ingress), 2 CiliumNetworkPolicies (allow-intra-namespace, allow-from-teleport), all VALID.

**Step 3: Switch back to AKS**

```bash
az aks get-credentials --resource-group k8s-developer-platform-rg --name k8s-developer-platform-aks --overwrite-existing
```

**Step 4: Commit**

```bash
git add manifests/cilium/gke-namespace-isolation.yaml
git commit -m "feat(cilium): add GKE website namespace network policies

Default deny ingress, allow intra-namespace, allow from teleport for
GKE Dataplane V2 (Cilium-based). Same security posture as AKS.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-263"
```

---

## Task 7: Register GKE Website in Teleport

**Files:**
- Create: `scripts/website/gke-teleport-register.sh`

**Step 1: Create the GKE Teleport registration script**

Create `scripts/website/gke-teleport-register.sh`:

```bash
#!/usr/bin/env bash
# Register davidshaevel-website on GKE as a Teleport application.
# Upgrades the GKE teleport-agent Helm release to include the website app.

source "$(dirname "$0")/../config.sh"
setup_logging "website-gke-teleport-register"

TELEPORT_NAMESPACE="teleport-cluster"
WEBSITE_NAMESPACE="davidshaevel-website"

# Switch to GKE context.
echo "Switching to GKE context..."
gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}"

# Verify Teleport agent is installed on GKE.
if ! helm status teleport-agent -n "${TELEPORT_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Teleport agent not found on GKE. Run ./scripts/gke/start.sh first."
    exit 1
fi

# Verify website frontend is running on GKE.
if ! kubectl get svc frontend -n "${WEBSITE_NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Website frontend service not found on GKE in namespace '${WEBSITE_NAMESPACE}'."
    echo "Wait for Argo CD to sync the GKE application."
    exit 1
fi

# Get the current chart version to match.
TELEPORT_VERSION=$(helm list -n "${TELEPORT_NAMESPACE}" -o json | jq -r '.[] | select(.name=="teleport-agent") | .app_version')
echo "Teleport agent version: ${TELEPORT_VERSION}"

echo ""
echo "Upgrading teleport-agent on GKE to register website app..."
echo "  Apps: davidshaevel-website-gke"
echo "  Website URI: http://frontend.${WEBSITE_NAMESPACE}.svc.cluster.local:3000"
echo ""

# The GKE agent currently only has kube registration. Add the app.
helm upgrade teleport-agent teleport/teleport-kube-agent \
    -n "${TELEPORT_NAMESPACE}" \
    --reuse-values \
    --set "roles=kube\,app" \
    --set "apps[0].name=davidshaevel-website-gke" \
    --set "apps[0].uri=http://frontend.${WEBSITE_NAMESPACE}.svc.cluster.local:3000" \
    --version="${TELEPORT_VERSION}" \
    --wait

echo ""
echo "Waiting for agent pod to be ready..."
kubectl rollout status statefulset/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || kubectl rollout status deployment/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || kubectl rollout status daemonset/teleport-agent -n "${TELEPORT_NAMESPACE}" --timeout=3m 2>/dev/null \
    || echo "Warning: Could not verify agent rollout. Check manually."

# Switch back to AKS to verify registration.
echo ""
echo "Switching back to AKS context to verify registration..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing

echo ""
echo "=== Registered Apps ==="
kubectl exec -n "${TELEPORT_NAMESPACE}" deployment/teleport-cluster-auth -- tctl apps ls

echo ""
echo "davidshaevel-website-gke is now accessible via Teleport:"
echo "  https://davidshaevel-website-gke.${TELEPORT_DOMAIN}"
```

Make executable:

```bash
chmod +x scripts/website/gke-teleport-register.sh
```

**Step 2: Run the script**

```bash
./scripts/website/gke-teleport-register.sh
```

Expected: Agent upgraded, app registered, `davidshaevel-website-gke` appears in `tctl apps ls`.

**Step 3: Verify access**

Open `https://davidshaevel-website-gke.teleport.davidshaevel.com` in browser. The website should load.

**Step 4: Commit**

```bash
git add scripts/website/gke-teleport-register.sh
git commit -m "feat(website): register GKE website in Teleport for app access

Accessible at davidshaevel-website-gke.teleport.davidshaevel.com.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-263"
```

---

## Task 8: Extend gke/start.sh with Platform Setup

**Files:**
- Create: `scripts/gke/argocd-cluster-add.sh`
- Create: `scripts/gke/acr-pull-secret.sh`
- Create: `scripts/gke/apply-network-policies.sh`
- Modify: `scripts/gke/start.sh` (add steps 5-8)

**Step 1: Create `scripts/gke/argocd-cluster-add.sh`**

Registers GKE in Argo CD using `--core` mode (no password needed):

```bash
#!/usr/bin/env bash
# Register GKE cluster in Argo CD using --core mode.
# Requires: argocd CLI, kubectl context for both AKS (current) and GKE.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-argocd-cluster-add"

GKE_CONTEXT="gke_${GCP_PROJECT}_${GKE_ZONE}_${GKE_CLUSTER_NAME}"

echo "Removing stale GKE cluster from Argo CD (if exists)..."
argocd cluster rm k8s-developer-platform-gke --core 2>/dev/null || true

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
```

**Step 2: Create `scripts/gke/acr-pull-secret.sh`**

Creates ACR image pull secret and patches the default service account on GKE:

```bash
#!/usr/bin/env bash
# Set up ACR image pull secret on GKE so pods can pull from Azure Container Registry.
# Requires: ACR_SP_APP_ID and ACR_SP_PASSWORD in .envrc.

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
```

**Step 3: Create `scripts/gke/apply-network-policies.sh`**

```bash
#!/usr/bin/env bash
# Apply Cilium network policies on GKE for the davidshaevel-website namespace.

source "$(dirname "$0")/../config.sh"
setup_logging "gke-apply-network-policies"

# Switch to GKE context.
echo "Switching to GKE context..."
gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GKE_ZONE}"

echo "Applying GKE network policies..."
kubectl apply -f manifests/cilium/gke-namespace-isolation.yaml

echo ""
echo "Network policies:"
kubectl get networkpolicies -n davidshaevel-website
kubectl get ciliumnetworkpolicies -n davidshaevel-website

# Switch back to AKS context.
echo ""
echo "Switching back to AKS context..."
az aks get-credentials \
    --subscription "${SUBSCRIPTION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing
```

**Step 4: Update `scripts/gke/start.sh`**

Add steps 5-8 after the existing step 4:

```bash
#!/usr/bin/env bash
# Orchestrated rebuild of the GKE environment.
# Creates cluster, installs agents, registers in Argo CD, sets up ACR access,
# applies network policies, and registers website in Teleport.

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
echo "--- Step 5/8: Register GKE in Argo CD ---"
"${SCRIPT_DIR}/argocd-cluster-add.sh"

echo ""
echo "--- Step 6/8: Set up ACR pull secret ---"
"${SCRIPT_DIR}/acr-pull-secret.sh"

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
```

**Step 5: Make all new scripts executable**

```bash
chmod +x scripts/gke/argocd-cluster-add.sh scripts/gke/acr-pull-secret.sh scripts/gke/apply-network-policies.sh
```

**Step 6: Add env vars to `.envrc.example`**

Add `ACR_SP_APP_ID` and `ACR_SP_PASSWORD` placeholders.

**Step 7: Commit**

```bash
git add scripts/gke/argocd-cluster-add.sh scripts/gke/acr-pull-secret.sh \
    scripts/gke/apply-network-policies.sh scripts/gke/start.sh .envrc.example
git commit -m "feat(gke): automate full GKE environment rebuild in start.sh

Extends gke/start.sh to 8 steps: create cluster, install Portainer agent,
register in Portainer, install Teleport agent, register in Argo CD (--core),
set up ACR pull secret, apply network policies, register website in Teleport.

Single command rebuilds the complete GKE environment after delete/recreate.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-263"
```

---

## Task 9: Update Documentation and Push

**Files:**
- Modify: `CLAUDE.md` (architecture diagram, helpful commands)
- Modify: `CLAUDE.local.md` (deployed applications table)

**Step 1: Update CLAUDE.md architecture diagram**

Add the GKE website deployment to the GKE section:

```
GKE Cluster (us-central1-a)
    |
    +-- davidshaevel-website namespace
    |       |
    |       +-- Frontend (Next.js, port 3000)
    |       +-- Backend (NestJS, port 3001)
    |       +-- Database (PostgreSQL 15, 1Gi PVC)
    |
    +-- portainer namespace
    |       +-- Portainer Agent (LoadBalancer, port 9001)
    |
    +-- teleport-cluster namespace
            +-- Teleport Kube Agent (kubectl access via Teleport)
            +-- Website App (davidshaevel-website-gke via Teleport)
```

**Step 2: Update CLAUDE.local.md deployed applications table**

Add GKE website entry:

```markdown
| **davidshaevel-website-gke (frontend)** | davidshaevel-website (GKE) | https://davidshaevel-website-gke.teleport.davidshaevel.com |
```

Update existing AKS entry URL from `davidshaevel-website` to `davidshaevel-website-aks`.

**Step 3: Commit and push**

```bash
git add CLAUDE.md CLAUDE.local.md
git commit -m "docs(platform): update architecture with GKE website deployment

Add GKE davidshaevel-website to architecture diagram and deployed
applications table. Update AKS website Teleport URL.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>

related-issues: TT-263"
git push
```

---

## Task 10: Verify End-to-End and Update Linear

**Step 1: Verify both sites in Argo CD UI**

Open `https://argocd.teleport.davidshaevel.com`. Both `davidshaevel-website-aks` and `davidshaevel-website-gke` should appear, both Synced/Healthy.

**Step 2: Verify both sites via Teleport**

- `https://davidshaevel-website-aks.teleport.davidshaevel.com` — loads website from AKS
- `https://davidshaevel-website-gke.teleport.davidshaevel.com` — loads website from GKE

**Step 3: Update Linear**

- Mark TT-263 as Done
- Post project status update with multi-cloud deployment milestone

**Step 4: Stop GKE cluster (save costs)**

```bash
./scripts/gke/stop.sh
```

Verify in Argo CD UI that `davidshaevel-website-gke` shows Unknown/ConnectionFailed — this is expected and part of the operational story.
