# Wave 2 Session C Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable Hubble observability and Cilium network policies (TT-155), then set up Azure Key Vault + External Secrets Operator for secrets management (TT-162).

**Architecture:** Two independent AKS platform installs in separate namespaces (`kube-system`/`cilium` for Hubble, `external-secrets` for ESO). Cilium is already running as the AKS CNI (Azure-managed via `--network-dataplane cilium`). ESO syncs secrets from Azure Key Vault into Kubernetes, replacing hardcoded values passed via Helm `--set` flags. Each issue gets its own worktree, branch, and PR.

**Tech Stack:** Azure CLI, Cilium CLI, Helm, kubectl, Azure Key Vault, External Secrets Operator

**Parallel sessions context:** Wave 2 has 3 parallel sessions. Session A (TT-154 Argo CD) and Session B (TT-153 ACR + TT-160 Rename) are running concurrently. Our work does not conflict with theirs — different namespaces, different scripts, different helm releases.

---

## Prerequisites

Before starting any tasks:

1. Verify AKS cluster is running: `az aks show -g k8s-developer-platform-rg -n k8s-developer-platform-aks --query powerState.code -o tsv` (expect `Running`)
2. Get AKS credentials: `az aks get-credentials -g k8s-developer-platform-rg -n k8s-developer-platform-aks`
3. Verify kubectl context: `kubectl get nodes` (expect 1 node, Ready)
4. Verify Cilium pods are running: `kubectl get pods -n kube-system -l k8s-app=cilium`

If the cluster is stopped, start it via GitHub Actions workflow or `./scripts/aks/start.sh`.

---

## Part 1: TT-155 — Configure Hubble and Cilium Network Policies

### Task 1: Create worktree and branch

**Step 1: Create worktree**

```bash
cd /Users/dshaevel/workspace-ds/davidshaevel-k8s-platform
git worktree add tt-155-cilium-hubble -b claude/tt-155-cilium-hubble
```

**Step 2: Copy gitignored files**

```bash
cp main/.envrc tt-155-cilium-hubble/.envrc
cp main/CLAUDE.local.md tt-155-cilium-hubble/CLAUDE.local.md
cp main/SESSION_LOG.md tt-155-cilium-hubble/SESSION_LOG.md
```

**Step 3: Verify worktree**

```bash
cd tt-155-cilium-hubble && git branch --show-current
```

Expected: `claude/tt-155-cilium-hubble`

---

### Task 2: Research Hubble enablement on Azure-managed Cilium

AKS with `--network-dataplane cilium` uses Azure-managed Cilium. We need to determine the correct approach for enabling Hubble before writing scripts.

**Step 1: Check current Cilium configuration**

```bash
kubectl get pods -n kube-system -l k8s-app=cilium -o wide
kubectl get cm -n kube-system cilium-config -o yaml | grep -i hubble
```

**Step 2: Check if cilium CLI is installed locally**

```bash
cilium version 2>/dev/null || echo "cilium CLI not installed"
```

If not installed: `brew install cilium-cli`

**Step 3: Check Cilium status and Hubble state**

```bash
cilium status
cilium hubble status 2>/dev/null || echo "Hubble not enabled"
```

**Step 4: Determine enablement approach**

Options (choose based on what works with Azure-managed Cilium):
- **Option A:** `cilium hubble enable` — uses cilium CLI to patch the running config
- **Option B:** `az aks update` with ACNS flags — uses Azure's Advanced Container Networking Services
- **Option C:** Helm overlay on the Azure-managed Cilium — install Hubble relay + UI components separately

Document the chosen approach before proceeding to Task 3.

---

### Task 3: Create `scripts/cilium/status.sh`

**Files:**
- Create: `scripts/cilium/status.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Show Cilium and Hubble status on AKS.

source "$(dirname "$0")/../config.sh"
setup_logging "cilium-status"

echo "=== Cilium Pods (kube-system) ==="
kubectl get pods -n kube-system -l k8s-app=cilium

echo ""
echo "=== Cilium Status ==="
cilium status 2>/dev/null || echo "cilium CLI not installed — install with: brew install cilium-cli"

echo ""
echo "=== Hubble Status ==="
cilium hubble status 2>/dev/null || echo "Hubble not enabled or cilium CLI not installed"

echo ""
echo "=== Hubble Relay ==="
kubectl get pods -n kube-system -l k8s-app=hubble-relay 2>/dev/null || true

echo ""
echo "=== Hubble UI ==="
kubectl get pods -n kube-system -l k8s-app=hubble-ui 2>/dev/null || true

echo ""
echo "=== CiliumNetworkPolicies ==="
kubectl get ciliumnetworkpolicies -A 2>/dev/null || echo "No CiliumNetworkPolicy CRD found"
```

**Step 2: Make executable and run**

```bash
chmod +x scripts/cilium/status.sh
./scripts/cilium/status.sh
```

**Step 3: Commit**

```bash
git add scripts/cilium/status.sh
git commit -m "feat(cilium): add status script for Cilium and Hubble

related-issues: TT-155"
```

---

### Task 4: Create Hubble enable/disable scripts

**Files:**
- Create: `scripts/cilium/hubble-enable.sh`
- Create: `scripts/cilium/hubble-disable.sh`

The exact implementation depends on the research from Task 2. Below is the template assuming `cilium hubble enable` works with Azure-managed Cilium. Adjust based on findings.

**Step 1: Write `hubble-enable.sh`**

```bash
#!/usr/bin/env bash
# Enable Hubble observability on the AKS cluster.
# Cilium is already installed as the AKS CNI (Azure-managed).
# This script enables the Hubble relay for network flow visibility.

source "$(dirname "$0")/../config.sh"
setup_logging "hubble-enable"

echo "Checking Cilium status..."
cilium status

echo ""
echo "Enabling Hubble..."
cilium hubble enable --wait

echo ""
echo "Verifying Hubble is running..."
cilium hubble status

echo ""
echo "Hubble relay pods:"
kubectl get pods -n kube-system -l k8s-app=hubble-relay

echo ""
echo "Hubble enabled successfully."
echo "  View flows:  cilium hubble observe"
echo "  Port-forward: cilium hubble port-forward &"
```

**Step 2: Write `hubble-disable.sh`**

```bash
#!/usr/bin/env bash
# Disable Hubble observability on the AKS cluster.

source "$(dirname "$0")/../config.sh"
setup_logging "hubble-disable"

echo "Disabling Hubble..."
cilium hubble disable --wait

echo ""
echo "Hubble disabled."
cilium status
```

**Step 3: Make executable, test enable**

```bash
chmod +x scripts/cilium/hubble-enable.sh scripts/cilium/hubble-disable.sh
./scripts/cilium/hubble-enable.sh
```

**Step 4: Verify Hubble is running**

```bash
cilium hubble status
kubectl get pods -n kube-system -l k8s-app=hubble-relay
```

**Step 5: Commit**

```bash
git add scripts/cilium/hubble-enable.sh scripts/cilium/hubble-disable.sh
git commit -m "feat(cilium): add Hubble enable/disable scripts

related-issues: TT-155"
```

---

### Task 5: Install Hubble UI and register with Teleport

**Files:**
- Create: `scripts/cilium/hubble-ui-install.sh`
- Create: `scripts/cilium/hubble-ui-uninstall.sh`

**Step 1: Write `hubble-ui-install.sh`**

```bash
#!/usr/bin/env bash
# Install Hubble UI for network flow visualization.
# Access via Teleport: https://hubble-ui.teleport.davidshaevel.com

source "$(dirname "$0")/../config.sh"
setup_logging "hubble-ui-install"

echo "Enabling Hubble UI..."
cilium hubble enable --ui --wait

echo ""
echo "Hubble UI pods:"
kubectl get pods -n kube-system -l k8s-app=hubble-ui

echo ""
echo "Hubble UI service:"
kubectl get svc -n kube-system hubble-ui

echo ""
echo "Hubble UI installed successfully."
echo ""
echo "To access locally:"
echo "  cilium hubble ui"
echo ""
echo "To access via Teleport, register as a Teleport app (see aks-agent-install.sh)."
```

**Step 2: Write `hubble-ui-uninstall.sh`**

```bash
#!/usr/bin/env bash
# Uninstall Hubble UI.

source "$(dirname "$0")/../config.sh"
setup_logging "hubble-ui-uninstall"

echo "Disabling Hubble UI..."
cilium hubble enable --ui=false --wait 2>/dev/null || true

echo ""
echo "Hubble UI removed."
```

**Step 3: Make executable and run install**

```bash
chmod +x scripts/cilium/hubble-ui-install.sh scripts/cilium/hubble-ui-uninstall.sh
./scripts/cilium/hubble-ui-install.sh
```

**Step 4: Verify Hubble UI is running**

```bash
kubectl get pods -n kube-system -l k8s-app=hubble-ui
kubectl get svc -n kube-system hubble-ui
```

**Step 5: Register Hubble UI with Teleport**

Update the Teleport agent to include Hubble UI as an app. This involves updating the Teleport agent Helm values to add a new app entry pointing to the Hubble UI ClusterIP service.

Check the existing agent install script for the pattern:

```bash
cat scripts/teleport/aks-agent-install.sh
```

Add Hubble UI app registration to the agent values (the service is typically `hubble-ui.kube-system.svc.cluster.local:80`).

**Step 6: Commit**

```bash
git add scripts/cilium/hubble-ui-install.sh scripts/cilium/hubble-ui-uninstall.sh
git commit -m "feat(cilium): add Hubble UI install/uninstall scripts

related-issues: TT-155"
```

---

### Task 6: Define Cilium network policies for namespace isolation

**Files:**
- Create: `manifests/cilium/namespace-isolation.yaml`

**Step 1: Write network policy manifests**

Create CiliumNetworkPolicy resources that enforce namespace isolation. Each namespace should only allow:
- Intra-namespace traffic (pods within the same namespace)
- DNS resolution (kube-dns/CoreDNS in kube-system)
- Ingress from Teleport proxy (for app access)
- Egress to the internet (for pulling images, ACME, etc.)

Namespaces to cover: `portainer`, `teleport-cluster`, and any future namespaces (template).

```yaml
# manifests/cilium/namespace-isolation.yaml
#
# Default deny + allow DNS + allow intra-namespace traffic.
# Applied per-namespace for platform services.
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: portainer
spec:
  endpointSelector: {}
  ingressDeny:
    - fromEndpoints:
        - matchExpressions:
            - key: io.kubernetes.pod.namespace
              operator: NotIn
              values:
                - portainer
                - teleport-cluster
                - kube-system
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-dns
  namespace: portainer
spec:
  endpointSelector: {}
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
```

Note: The exact policies will be refined during implementation based on actual traffic patterns observed via Hubble. Start with a minimal set and iterate.

**Step 2: Create an apply script**

Create `scripts/cilium/apply-policies.sh`:

```bash
#!/usr/bin/env bash
# Apply Cilium network policies for namespace isolation.

source "$(dirname "$0")/../config.sh"
setup_logging "cilium-apply-policies"

MANIFEST_DIR="$(dirname "$0")/../../manifests/cilium"

echo "Applying Cilium network policies..."
kubectl apply -f "${MANIFEST_DIR}/"

echo ""
echo "Active CiliumNetworkPolicies:"
kubectl get ciliumnetworkpolicies -A
```

**Step 3: Apply and verify**

```bash
chmod +x scripts/cilium/apply-policies.sh
./scripts/cilium/apply-policies.sh
```

**Step 4: Verify with Hubble**

```bash
# Observe traffic flows to verify policies aren't blocking legitimate traffic
cilium hubble observe --namespace portainer --last 50
cilium hubble observe --namespace teleport-cluster --last 50
```

**Step 5: Commit**

```bash
git add manifests/cilium/ scripts/cilium/apply-policies.sh
git commit -m "feat(cilium): add namespace isolation network policies

Default-deny ingress with allowlists for DNS, intra-namespace,
and Teleport proxy access.

related-issues: TT-155"
```

---

### Task 7: Create helm-values for Cilium/Hubble

**Files:**
- Create: `helm-values/cilium/README.md`

Since Cilium is Azure-managed on AKS, we don't install it via Helm ourselves. The helm-values directory serves as documentation for the configuration applied via `cilium` CLI commands.

**Step 1: Create README documenting the configuration**

```markdown
# Cilium / Hubble Helm Values

Cilium is managed by Azure on AKS (`--network-dataplane cilium`).
It is NOT installed via Helm in this repo. Azure manages the Cilium
DaemonSet in `kube-system`.

Hubble and Hubble UI are enabled via the `cilium` CLI:
- Enable: `./scripts/cilium/hubble-enable.sh`
- UI: `./scripts/cilium/hubble-ui-install.sh`

Network policies are applied as CiliumNetworkPolicy manifests:
- Manifests: `manifests/cilium/`
- Apply: `./scripts/cilium/apply-policies.sh`
```

**Step 2: Commit**

```bash
mkdir -p helm-values/cilium
git add helm-values/cilium/README.md
git commit -m "docs(cilium): add helm-values README explaining Azure-managed Cilium

related-issues: TT-155"
```

---

### Task 8: Update CLAUDE.md and create PR for TT-155

**Step 1: Update CLAUDE.md**

Add Cilium/Hubble to the architecture diagram, helpful commands, and repository structure sections.

**Step 2: Update Linear issue TT-155**

Mark as "In Progress" at the start (Task 1), then "Done" after PR merge.

**Step 3: Create PR**

```bash
git push -u origin claude/tt-155-cilium-hubble
gh pr create --title "feat(cilium): configure Hubble and Cilium network policies" \
  --body "$(cat <<'EOF'
## Summary
- Enable Hubble observability on AKS (Azure-managed Cilium)
- Install Hubble UI for network flow visualization
- Define CiliumNetworkPolicy manifests for namespace isolation
- Add scripts: status, hubble-enable/disable, hubble-ui-install/uninstall, apply-policies
- Register Hubble UI with Teleport for secure access

## Test plan
- [ ] `scripts/cilium/status.sh` shows Cilium + Hubble running
- [ ] `cilium hubble observe` shows network flows
- [ ] Hubble UI accessible via Teleport
- [ ] Network policies applied, verified with `kubectl get cnp -A`
- [ ] Existing services (Portainer, Teleport) still functional after policies applied

related-issues: TT-155

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 4: Wait for code review, address feedback, merge**

Follow the PR process: wait for Gemini Code Assist review, address feedback, squash merge.

**Step 5: Cleanup worktree**

```bash
cd /Users/dshaevel/workspace-ds/davidshaevel-k8s-platform
cp tt-155-cilium-hubble/.envrc main/.envrc
cp tt-155-cilium-hubble/CLAUDE.local.md main/CLAUDE.local.md
cp tt-155-cilium-hubble/SESSION_LOG.md main/SESSION_LOG.md
cd main && git pull
git push origin --delete claude/tt-155-cilium-hubble
cd .. && git worktree remove tt-155-cilium-hubble
```

---

## Part 2: TT-162 — Set Up Secrets Management with External Secrets Operator

### Task 9: Create worktree and branch

**Step 1: Create worktree**

```bash
cd /Users/dshaevel/workspace-ds/davidshaevel-k8s-platform
git worktree add tt-162-external-secrets -b claude/tt-162-external-secrets
```

**Step 2: Copy gitignored files**

```bash
cp main/.envrc tt-162-external-secrets/.envrc
cp main/CLAUDE.local.md tt-162-external-secrets/CLAUDE.local.md
cp main/SESSION_LOG.md tt-162-external-secrets/SESSION_LOG.md
```

---

### Task 10: Create Azure Key Vault

**Files:**
- Create: `scripts/external-secrets/keyvault-create.sh`
- Create: `scripts/external-secrets/keyvault-delete.sh`

**Step 1: Write `keyvault-create.sh`**

```bash
#!/usr/bin/env bash
# Create Azure Key Vault for secrets management.

source "$(dirname "$0")/../config.sh"
setup_logging "keyvault-create"

KEYVAULT_NAME="k8s-platform-kv"

echo "Creating Azure Key Vault: ${KEYVAULT_NAME}"
echo "  Resource Group: ${RESOURCE_GROUP}"
echo "  Location: ${AKS_LOCATION}"
echo ""

az keyvault create \
    --name "${KEYVAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${AKS_LOCATION}" \
    --enable-rbac-authorization true

echo ""
echo "Key Vault created: ${KEYVAULT_NAME}"
echo "  URI: https://${KEYVAULT_NAME}.vault.azure.net/"
```

Note: The Key Vault name must be globally unique. If `k8s-platform-kv` is taken, adjust the name. Add `KEYVAULT_NAME` to `config.sh`.

**Step 2: Write `keyvault-delete.sh`**

```bash
#!/usr/bin/env bash
# Delete Azure Key Vault (interactive confirmation required).

source "$(dirname "$0")/../config.sh"
setup_logging "keyvault-delete"

KEYVAULT_NAME="k8s-platform-kv"

echo "WARNING: This will permanently delete Key Vault: ${KEYVAULT_NAME}"
read -r -p "Type '${KEYVAULT_NAME}' to confirm deletion: " CONFIRM
if [[ "${CONFIRM}" != "${KEYVAULT_NAME}" ]]; then
    echo "Aborted."
    exit 1
fi

az keyvault delete \
    --name "${KEYVAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}"

echo "Key Vault deleted: ${KEYVAULT_NAME}"
echo "Note: Soft-deleted vaults can be purged with: az keyvault purge --name ${KEYVAULT_NAME}"
```

**Step 3: Add KEYVAULT_NAME to config.sh**

Add to the Azure/AKS section:
```bash
KEYVAULT_NAME="k8s-platform-kv"
```

**Step 4: Make executable, create Key Vault**

```bash
chmod +x scripts/external-secrets/keyvault-create.sh scripts/external-secrets/keyvault-delete.sh
./scripts/external-secrets/keyvault-create.sh
```

**Step 5: Verify Key Vault exists**

```bash
az keyvault show --name k8s-platform-kv --resource-group k8s-developer-platform-rg --query name -o tsv
```

**Step 6: Commit**

```bash
git add scripts/external-secrets/keyvault-create.sh scripts/external-secrets/keyvault-delete.sh scripts/config.sh
git commit -m "feat(keyvault): add Azure Key Vault create/delete scripts

related-issues: TT-162"
```

---

### Task 11: Create service principal for ESO to access Key Vault

**Files:**
- Create: `scripts/external-secrets/keyvault-sp-create.sh`

ESO needs credentials to read from Key Vault. Create a service principal with `Key Vault Secrets User` RBAC role.

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Create a service principal for ESO to read secrets from Azure Key Vault.
# Outputs credentials to a local file (gitignored) and creates a K8s secret.

source "$(dirname "$0")/../config.sh"
setup_logging "keyvault-sp-create"

KEYVAULT_SP_NAME="eso-keyvault-reader"
KEYVAULT_ID=$(az keyvault show --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)

echo "Creating service principal: ${KEYVAULT_SP_NAME}"
echo "  Key Vault: ${KEYVAULT_NAME}"
echo ""

# Create SP and capture credentials
SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "${KEYVAULT_SP_NAME}" \
    --role "Key Vault Secrets User" \
    --scopes "${KEYVAULT_ID}" \
    --output json)

CLIENT_ID=$(echo "${SP_OUTPUT}" | jq -r '.appId')
CLIENT_SECRET=$(echo "${SP_OUTPUT}" | jq -r '.password')
TENANT_ID=$(echo "${SP_OUTPUT}" | jq -r '.tenant')

echo "Service principal created:"
echo "  Client ID: ${CLIENT_ID}"
echo "  Tenant ID: ${TENANT_ID}"
echo ""

# Save credentials to gitignored file
CREDS_FILE="$(dirname "$0")/eso-sp-credentials.json"
echo "${SP_OUTPUT}" > "${CREDS_FILE}"
echo "Credentials saved to: ${CREDS_FILE}"
echo "IMPORTANT: Save these to 1Password, then delete the file."
echo ""

# Create Kubernetes secret for ESO
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic azure-keyvault-credentials \
    --namespace external-secrets \
    --from-literal=clientId="${CLIENT_ID}" \
    --from-literal=clientSecret="${CLIENT_SECRET}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Kubernetes secret 'azure-keyvault-credentials' created in 'external-secrets' namespace."
echo "  Tenant ID (for ClusterSecretStore): ${TENANT_ID}"
```

**Step 2: Add eso-sp-credentials.json to .gitignore**

Verify that `scripts/github/` credential files are already gitignored. Add ESO creds if needed:
```
scripts/external-secrets/eso-sp-credentials.json
```

**Step 3: Make executable and run**

```bash
chmod +x scripts/external-secrets/keyvault-sp-create.sh
./scripts/external-secrets/keyvault-sp-create.sh
```

**Step 4: Save credentials to 1Password, then delete local file**

**Step 5: Commit**

```bash
git add scripts/external-secrets/keyvault-sp-create.sh .gitignore
git commit -m "feat(keyvault): add service principal script for ESO Key Vault access

related-issues: TT-162"
```

---

### Task 12: Install External Secrets Operator

**Files:**
- Create: `scripts/external-secrets/install.sh`
- Create: `scripts/external-secrets/uninstall.sh`
- Create: `scripts/external-secrets/status.sh`
- Create: `helm-values/external-secrets/values.yaml`

**Step 1: Write `helm-values/external-secrets/values.yaml`**

```yaml
# External Secrets Operator Helm values for AKS
# Chart: external-secrets/external-secrets
installCRDs: true
```

**Step 2: Write `install.sh`**

```bash
#!/usr/bin/env bash
# Install External Secrets Operator on AKS.

source "$(dirname "$0")/../config.sh"
setup_logging "eso-install"

HELM_VALUES="$(dirname "$0")/../../helm-values/external-secrets/values.yaml"

echo "Installing External Secrets Operator..."
echo ""

# Add Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

# Create namespace
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -

# Install ESO
helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --values "${HELM_VALUES}" \
    --wait

echo ""
echo "External Secrets Operator installed."
echo ""
kubectl get pods -n external-secrets
```

**Step 3: Write `uninstall.sh`**

```bash
#!/usr/bin/env bash
# Uninstall External Secrets Operator from AKS.

source "$(dirname "$0")/../config.sh"
setup_logging "eso-uninstall"

echo "WARNING: This will uninstall External Secrets Operator."
echo "All ExternalSecret resources will stop syncing."
read -r -p "Type 'external-secrets' to confirm: " CONFIRM
if [[ "${CONFIRM}" != "external-secrets" ]]; then
    echo "Aborted."
    exit 1
fi

if helm status external-secrets -n external-secrets &>/dev/null; then
    helm uninstall external-secrets -n external-secrets --wait
    echo "External Secrets Operator uninstalled."
else
    echo "Helm release 'external-secrets' not found."
fi

kubectl delete namespace external-secrets --ignore-not-found=true
echo "Namespace 'external-secrets' deleted."
```

**Step 4: Write `status.sh`**

```bash
#!/usr/bin/env bash
# Show External Secrets Operator status.

source "$(dirname "$0")/../config.sh"
setup_logging "eso-status"

echo "=== ESO Helm Release ==="
helm status external-secrets -n external-secrets 2>/dev/null || echo "Not installed"

echo ""
echo "=== ESO Pods ==="
kubectl get pods -n external-secrets 2>/dev/null || echo "Namespace not found"

echo ""
echo "=== ClusterSecretStores ==="
kubectl get clustersecretstores 2>/dev/null || echo "No ClusterSecretStore CRD found"

echo ""
echo "=== ExternalSecrets (all namespaces) ==="
kubectl get externalsecrets -A 2>/dev/null || echo "No ExternalSecret CRD found"
```

**Step 5: Make executable and install**

```bash
chmod +x scripts/external-secrets/install.sh scripts/external-secrets/uninstall.sh scripts/external-secrets/status.sh
./scripts/external-secrets/install.sh
```

**Step 6: Verify installation**

```bash
./scripts/external-secrets/status.sh
```

Expected: 3 pods running (operator, webhook, cert-controller).

**Step 7: Commit**

```bash
git add scripts/external-secrets/install.sh scripts/external-secrets/uninstall.sh scripts/external-secrets/status.sh helm-values/external-secrets/values.yaml
git commit -m "feat(external-secrets): install ESO with Helm on AKS

related-issues: TT-162"
```

---

### Task 13: Configure ClusterSecretStore for Azure Key Vault

**Files:**
- Create: `manifests/external-secrets/cluster-secret-store.yaml`

**Step 1: Write the ClusterSecretStore manifest**

```yaml
# manifests/external-secrets/cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault
spec:
  provider:
    azurekv:
      tenantId: "<TENANT_ID>"           # From keyvault-sp-create.sh output
      vaultUrl: "https://k8s-platform-kv.vault.azure.net/"
      authSecretRef:
        clientId:
          name: azure-keyvault-credentials
          namespace: external-secrets
          key: clientId
        clientSecret:
          name: azure-keyvault-credentials
          namespace: external-secrets
          key: clientSecret
```

Note: Replace `<TENANT_ID>` with the actual Azure tenant ID during implementation. This is not sensitive — it's the directory ID visible in the Azure portal.

**Step 2: Apply the manifest**

```bash
kubectl apply -f manifests/external-secrets/cluster-secret-store.yaml
```

**Step 3: Verify the ClusterSecretStore is ready**

```bash
kubectl get clustersecretstores azure-keyvault
kubectl describe clustersecretstores azure-keyvault
```

Expected: Status should show `Ready: True`.

**Step 4: Commit**

```bash
git add manifests/external-secrets/cluster-secret-store.yaml
git commit -m "feat(external-secrets): configure ClusterSecretStore for Azure Key Vault

related-issues: TT-162"
```

---

### Task 14: Migrate existing secrets to Key Vault + ExternalSecrets

**Files:**
- Create: `scripts/external-secrets/seed-keyvault.sh`
- Create: `manifests/external-secrets/platform-secrets.yaml`

Identify secrets currently passed as Helm `--set` values or environment variables that should be managed by ESO:

| Secret | Current Location | Key Vault Secret Name |
|--------|-----------------|----------------------|
| Portainer admin password | .envrc `PORTAINER_ADMIN_PASSWORD` | `portainer-admin-password` |
| Cloudflare API token | .envrc `CLOUDFLARE_API_TOKEN` | `cloudflare-api-token` |
| Cloudflare zone ID | .envrc `CLOUDFLARE_ZONE_ID` | `cloudflare-zone-id` |
| Teleport ACME email | .envrc `TELEPORT_ACME_EMAIL` | `teleport-acme-email` |

Note: Azure subscription and GCP project are not secrets (they're config), so they stay in `.envrc`. The Teleport join token is ephemeral (generated at install time), so it's not migrated.

**Step 1: Write `seed-keyvault.sh`**

```bash
#!/usr/bin/env bash
# Seed Azure Key Vault with platform secrets from environment variables.
# Run this once to populate Key Vault, then ESO will sync them to K8s.
#
# Requires: .envrc sourced with PORTAINER_ADMIN_PASSWORD, CLOUDFLARE_API_TOKEN,
#           CLOUDFLARE_ZONE_ID, TELEPORT_ACME_EMAIL

source "$(dirname "$0")/../config.sh"
setup_logging "seed-keyvault"

echo "Seeding Azure Key Vault: ${KEYVAULT_NAME}"
echo ""

# Validate required env vars
: "${PORTAINER_ADMIN_PASSWORD:?Set PORTAINER_ADMIN_PASSWORD in .envrc}"
: "${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN in .envrc}"
: "${CLOUDFLARE_ZONE_ID:?Set CLOUDFLARE_ZONE_ID in .envrc}"
: "${TELEPORT_ACME_EMAIL:?Set TELEPORT_ACME_EMAIL in .envrc}"

az keyvault secret set --vault-name "${KEYVAULT_NAME}" --name "portainer-admin-password" --value "${PORTAINER_ADMIN_PASSWORD}" --output none
echo "  Set: portainer-admin-password"

az keyvault secret set --vault-name "${KEYVAULT_NAME}" --name "cloudflare-api-token" --value "${CLOUDFLARE_API_TOKEN}" --output none
echo "  Set: cloudflare-api-token"

az keyvault secret set --vault-name "${KEYVAULT_NAME}" --name "cloudflare-zone-id" --value "${CLOUDFLARE_ZONE_ID}" --output none
echo "  Set: cloudflare-zone-id"

az keyvault secret set --vault-name "${KEYVAULT_NAME}" --name "teleport-acme-email" --value "${TELEPORT_ACME_EMAIL}" --output none
echo "  Set: teleport-acme-email"

echo ""
echo "Key Vault seeded. Secrets:"
az keyvault secret list --vault-name "${KEYVAULT_NAME}" --query "[].name" -o tsv
```

**Step 2: Write ExternalSecret manifests**

```yaml
# manifests/external-secrets/platform-secrets.yaml
#
# ExternalSecret resources that sync from Azure Key Vault to K8s secrets.
# These replace hardcoded values passed via Helm --set flags.
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: portainer-secrets
  namespace: portainer
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore
  target:
    name: portainer-secrets
  data:
    - secretKey: admin-password
      remoteRef:
        key: portainer-admin-password
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: cloudflare-secrets
  namespace: teleport-cluster
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore
  target:
    name: cloudflare-secrets
  data:
    - secretKey: api-token
      remoteRef:
        key: cloudflare-api-token
    - secretKey: zone-id
      remoteRef:
        key: cloudflare-zone-id
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: teleport-secrets
  namespace: teleport-cluster
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-keyvault
    kind: ClusterSecretStore
  target:
    name: teleport-secrets
  data:
    - secretKey: acme-email
      remoteRef:
        key: teleport-acme-email
```

**Step 3: Seed Key Vault and apply ExternalSecrets**

```bash
chmod +x scripts/external-secrets/seed-keyvault.sh
source .envrc
./scripts/external-secrets/seed-keyvault.sh
kubectl apply -f manifests/external-secrets/platform-secrets.yaml
```

**Step 4: Verify secrets synced**

```bash
kubectl get externalsecrets -A
kubectl get secrets -n portainer portainer-secrets -o yaml
kubectl get secrets -n teleport-cluster cloudflare-secrets -o yaml
kubectl get secrets -n teleport-cluster teleport-secrets -o yaml
```

Expected: All ExternalSecrets show `SecretSynced: True`, and K8s secrets contain the correct data.

**Step 5: Commit**

```bash
git add scripts/external-secrets/seed-keyvault.sh manifests/external-secrets/platform-secrets.yaml
git commit -m "feat(external-secrets): migrate platform secrets to Key Vault + ESO

Seed script populates Key Vault from env vars. ExternalSecret resources
sync secrets to K8s for Portainer, Cloudflare, and Teleport namespaces.

related-issues: TT-162"
```

---

### Task 15: Update CLAUDE.md, .envrc.example, and create PR for TT-162

**Step 1: Update CLAUDE.md**

- Add ESO and Key Vault to architecture diagram
- Add helpful commands for Key Vault and ESO
- Add new environment variable documentation (if any new vars needed)
- Update repository structure with new directories

**Step 2: Update .envrc.example**

No new env vars needed — ESO reads from Key Vault, not env vars. The seed script uses existing env vars one time.

**Step 3: Update CLAUDE.local.md**

Add Key Vault details:
```markdown
## Azure Key Vault Details

| Property | Value |
|----------|-------|
| **Key Vault Name** | k8s-platform-kv |
| **URI** | https://k8s-platform-kv.vault.azure.net/ |
| **ESO Service Principal** | eso-keyvault-reader |
```

**Step 4: Create PR**

```bash
git push -u origin claude/tt-162-external-secrets
gh pr create --title "feat(external-secrets): set up ESO with Azure Key Vault" \
  --body "$(cat <<'EOF'
## Summary
- Create Azure Key Vault in k8s-developer-platform-rg
- Install External Secrets Operator via Helm
- Configure ClusterSecretStore for Azure Key Vault access
- Create service principal with Key Vault Secrets User role
- Migrate platform secrets (Portainer, Cloudflare, Teleport) to Key Vault
- Add ExternalSecret resources to sync secrets to K8s

## Test plan
- [ ] Key Vault exists: `az keyvault show --name k8s-platform-kv`
- [ ] ESO pods running: `kubectl get pods -n external-secrets`
- [ ] ClusterSecretStore ready: `kubectl get css azure-keyvault`
- [ ] ExternalSecrets synced: `kubectl get es -A` (all show SecretSynced)
- [ ] K8s secrets created in target namespaces
- [ ] Existing services still functional

related-issues: TT-162

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 5: Wait for code review, address feedback, merge**

**Step 6: Cleanup worktree**

```bash
cd /Users/dshaevel/workspace-ds/davidshaevel-k8s-platform
cp tt-162-external-secrets/.envrc main/.envrc
cp tt-162-external-secrets/CLAUDE.local.md main/CLAUDE.local.md
cp tt-162-external-secrets/SESSION_LOG.md main/SESSION_LOG.md
cd main && git pull
git push origin --delete claude/tt-162-external-secrets
cd .. && git worktree remove tt-162-external-secrets
```

---

## Post-Session Checklist

- [ ] TT-155 PR merged, issue marked Done in Linear
- [ ] TT-162 PR merged, issue marked Done in Linear
- [ ] Both worktrees cleaned up
- [ ] SESSION_LOG.md updated (session-handoff skill)
- [ ] AKS cluster stopped if no other sessions need it (coordinate with Sessions A and B)
- [ ] Post project status update to Linear

## What This Unblocks

- **TT-158** (Monitoring) — blocked by TT-152 + TT-155. After our TT-155 completes, TT-158 only needs TT-152 (already done). TT-158 is unblocked for Wave 3.
- TT-162 (ESO) has no downstream blockers in the dependency graph, but all future platform components can use ESO for secrets management.
