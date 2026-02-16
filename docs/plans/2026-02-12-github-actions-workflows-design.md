# Design: GitHub Actions Workflows for Cluster Lifecycle Management

**Date:** February 12, 2026
**Linear Issue:** [TT-151](https://linear.app/davidshaevel-dot-com/issue/TT-151)
**Status:** Phases 1-3, 5 implemented. Phase 4 (secrets) and Phase 6 (portfolio listing) pending.

## Context

The davidshaevel-portainer project manages a multi-cloud Kubernetes setup (AKS + GKE) with Portainer BE and Teleport. Currently, starting and stopping clusters requires running local bash scripts manually. Adding GitHub Actions workflows eliminates this toil — clusters can be started/stopped from any device via the GitHub UI. This is pre-work for deploying davidshaevel-platform to GKE (TT-148) since we want one-click cluster lifecycle management.

The project also needs a Portainer API registration script to programmatically add GKE as an environment (currently a manual UI step), and the README needs updating for portfolio listing on davidshaevel.com.

---

## Phase 1: Script Refactoring for CI Compatibility

### 1a. Modify `scripts/config.sh` — Skip logging in CI

GitHub Actions sets `CI=true`. Guard `LOG_DIR` creation and `setup_logging` file output:

```bash
# Only create log directory when running locally
if [[ "${CI:-}" != "true" ]]; then
    LOG_DIR="/tmp/${USER}-portainer"
    mkdir -p "${LOG_DIR}"
fi

setup_logging() {
    # ... existing validation ...
    if [[ "${CI:-}" == "true" ]]; then
        return  # GitHub Actions captures output natively
    fi
    # ... existing tee logic ...
}
```

**File:** `scripts/config.sh` (lines 26-45)

### 1b. Modify `scripts/teleport/dns-delete.sh` — Non-interactive mode for CI

The `read -r -p "Type 'delete'..."` on line 41 blocks in CI. Add CI detection:

```bash
if [[ "${CI:-}" == "true" ]]; then
    echo "CI mode: skipping interactive confirmation."
else
    read -r -p "Type 'delete' to confirm deletion of ${#RECORD_IDS[@]} record(s): " confirm
    if [ "${confirm}" != "delete" ]; then
        echo "Confirmation failed. Aborting."
        exit 1
    fi
fi
```

**File:** `scripts/teleport/dns-delete.sh` (lines 40-45)

---

## Phase 2: Portainer API Scripts

### 2a. Create `scripts/portainer/gke-agent-register.sh`

Programmatically adds GKE to Portainer via REST API, replacing the manual UI step shown at the end of `gke-agent-install.sh` (lines 55-58).

**Challenge:** Portainer is ClusterIP only (no public IP). Solution: `kubectl port-forward` to reach it on AKS.

**Flow:**
1. Get GKE agent LoadBalancer IP (switch to GKE context)
2. Switch to AKS context, start background `kubectl port-forward svc/portainer -n portainer 9444:9443`
3. `trap cleanup EXIT` to kill port-forward on any exit
4. Auth: `POST /api/auth` with admin credentials → JWT token
5. Check if endpoint already exists (`GET /api/endpoints`, filter by name)
6. If exists: `PUT /api/endpoints/:id` to update IP. If not: `POST /api/endpoints` with `EndpointCreationType: 2`, `URL: tcp://AGENT_IP:9001`, `TLS: true`, `TLSSkipVerify: true`
7. Verify connection status

**Env var required:** `PORTAINER_ADMIN_PASSWORD`

### 2b. Create `scripts/portainer/gke-agent-deregister.sh`

Removes GKE endpoint from Portainer via API. Same port-forward pattern. Finds endpoint by name, `DELETE /api/endpoints/:id`. Idempotent (exits 0 if endpoint not found).

### 2c. Update `scripts/gke/start.sh` — Add registration step

Add `./scripts/portainer/gke-agent-register.sh` as Step 3 (after agent install, before Teleport agent):

```
Step 1: Create GKE cluster         (existing)
Step 2: Install Portainer Agent     (existing)
Step 3: Register in Portainer API   (NEW)
Step 4: Install Teleport Agent      (existing, renumbered)
```

### 2d. Update `.envrc.example` — Document new env var

Add `PORTAINER_ADMIN_PASSWORD` to the template.

---

## Phase 3: GitHub Actions Workflows

### GitHub Secrets Required

| Secret | Value | Source |
|--------|-------|--------|
| `AZURE_CREDENTIALS` | Service principal JSON | `az ad sp create-for-rbac --name github-portainer --role contributor --scopes /subscriptions/.../resourceGroups/portainer-rg --json-auth` |
| `AZURE_SUBSCRIPTION` | Subscription name | `.envrc` |
| `GCP_CREDENTIALS_JSON` | Service account key JSON | GCP Console → IAM → Service Accounts |
| `GCP_PROJECT` | `dev-david-024680` | `.envrc` |
| `CLOUDFLARE_API_TOKEN` | API token | `.envrc` |
| `CLOUDFLARE_ZONE_ID` | Zone ID | `.envrc` |
| `TELEPORT_ACME_EMAIL` | Email | `.envrc` |
| `PORTAINER_ADMIN_PASSWORD` | Admin password | Portainer setup |

### 3a. `.github/workflows/aks-start.yml`

**Trigger:** `workflow_dispatch` (manual)

**Steps:**
1. Checkout
2. Azure Login (`azure/login@v2`)
3. Setup kubectl + helm
4. `./scripts/aks/start.sh`
5. `./scripts/aks/credentials.sh`
6. Wait for pods ready: `kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=5m`
7. `./scripts/teleport/dns.sh` (LoadBalancer IP may change after stop/start)
8. Sleep 60s for DNS propagation
9. Verify Teleport accessible (retry loop, curl `https://teleport.davidshaevel.com/web/login`)
10. Output summary to `$GITHUB_STEP_SUMMARY`

### 3b. `.github/workflows/aks-stop.yml`

**Trigger:** `workflow_dispatch` with input `delete_dns` (default: true)

**Steps:**
1. Checkout
2. Azure Login
3. If `delete_dns`: `./scripts/teleport/dns-delete.sh` (uses CI-mode skip of confirmation)
4. `./scripts/aks/stop.sh`
5. Output summary

### 3c. `.github/workflows/gke-start.yml`

**Trigger:** `workflow_dispatch` (manual)

**Requires both Azure and GCP auth** (Portainer API on AKS, AKS egress IP lookup, Teleport token creation on AKS, GKE cluster creation).

**Steps:**
1. Checkout
2. Azure Login
3. GCP Auth (`google-github-actions/auth@v2`)
4. Setup gcloud with `gke-gcloud-auth-plugin`
5. Setup kubectl + helm
6. `./scripts/aks/credentials.sh` (needed by later steps)
7. `./scripts/gke/create.sh`
8. `./scripts/gke/credentials.sh`
9. `./scripts/portainer/gke-agent-install.sh` (installs agent, restricts LB to AKS IP)
10. `./scripts/portainer/gke-agent-register.sh` (port-forward to Portainer API, register endpoint)
11. `./scripts/teleport/gke-agent-install.sh` (creates token on AKS, installs on GKE)
12. Verify: check Teleport registrations, GKE pods
13. Output summary
14. **On failure:** `gcloud container clusters delete portainer-gke --quiet` (cost protection)

### 3d. `.github/workflows/gke-stop.yml`

**Trigger:** `workflow_dispatch` with input `deregister_portainer` (default: true)

**Steps:**
1. Checkout
2. If `deregister_portainer`: Azure Login → AKS credentials → `./scripts/portainer/gke-agent-deregister.sh`
3. GCP Auth
4. `./scripts/gke/stop.sh` (non-interactive deletion)
5. Output summary

---

## Phase 4: Secrets Setup

### 4a. Create Azure service principal

```bash
az ad sp create-for-rbac \
    --name "github-portainer" \
    --role contributor \
    --scopes /subscriptions/<subscription-id>/resourceGroups/portainer-rg \
    --json-auth
```

Save the JSON output as `AZURE_CREDENTIALS` secret.

### 4b. Create GCP service account

```bash
gcloud iam service-accounts create github-portainer \
    --project=<gcp-project-id> \
    --display-name="GitHub Actions - Portainer"

gcloud projects add-iam-policy-binding <gcp-project-id> \
    --member="serviceAccount:github-portainer@<gcp-project-id>.iam.gserviceaccount.com" \
    --role="roles/container.admin"

gcloud iam service-accounts keys create key.json \
    --iam-account=github-portainer@<gcp-project-id>.iam.gserviceaccount.com
```

Save `key.json` contents as `GCP_CREDENTIALS_JSON` secret.

### 4c. Configure all 8 secrets in GitHub repo settings

---

## Phase 5: README Update

Update `README.md` with:
- Portfolio-appropriate project title and description (not just "learning project")
- New "GitHub Actions Workflows" section documenting the 4 workflows
- Updated architecture notes mentioning CI/CD automation
- Updated scripts section listing the new Portainer API scripts

**Key framing:** Multi-cloud Kubernetes management platform with zero-trust access, cost-optimized lifecycle automation, and programmatic environment registration.

---

## Phase 6: davidshaevel.com Portfolio Listing

### How projects work on the website

- **Backend:** `POST /api/projects` (Nest.js, TypeORM, PostgreSQL)
- **Entity:** `title`, `description`, `githubUrl`, `projectUrl`, `technologies[]`, `isActive`, `sortOrder`
- **Frontend:** Currently hardcoded in `frontend/app/projects/page.tsx` — would need updating to render dynamically from the API
- **Migration seed:** `backend/database/migrations/002_seed_initial_project.sql` shows the pattern

### Add project via API

```bash
curl -X POST https://davidshaevel.com/api/projects \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Multi-Cloud Kubernetes Platform",
    "description": "Multi-cloud Kubernetes management with Portainer BE across AKS and GKE...",
    "githubUrl": "https://github.com/davidshaevel-dot-com/davidshaevel-portainer",
    "technologies": ["Kubernetes", "Azure AKS", "Google GKE", "Portainer", "Teleport", "GitHub Actions", "Helm", "Bash", "Cloudflare API"],
    "isActive": true,
    "sortOrder": 1
  }'
```

### Frontend update needed

The `projects/page.tsx` currently hardcodes the davidshaevel.com platform project. To show the new project, the page needs to fetch from `GET /api/projects` and render dynamically. This is a separate PR in the davidshaevel-platform repo.

---

## Implementation Order

| Step | What | Where | Status |
|------|------|-------|--------|
| 1 | Re-open Portainer project in Linear, create issue | Linear | Done |
| 2 | Create worktree in davidshaevel-portainer | davidshaevel-portainer | Done |
| 3 | Phase 1: CI compatibility changes to config.sh, dns-delete.sh | davidshaevel-portainer | Done |
| 4 | Phase 2: Create gke-agent-register.sh, gke-agent-deregister.sh, update gke/start.sh | davidshaevel-portainer | Done |
| 5 | Phase 3: Create 4 workflow YAML files | davidshaevel-portainer | Done |
| 6 | Phase 4: Create Azure SP, GCP SA, configure 8 GitHub secrets | Azure/GCP/GitHub | Pending |
| 7 | Test: Run AKS Start → GKE Start → GKE Stop → AKS Stop | GitHub Actions | Pending |
| 8 | Phase 5: Update README.md | davidshaevel-portainer | Done |
| 9 | PR, review, merge | GitHub | PR #6 open |
| 10 | Phase 6: Add project to davidshaevel.com (API + frontend) | davidshaevel-platform | Pending |

---

## Verification

1. **AKS Start workflow:** Trigger manually → cluster starts → DNS updates → Teleport accessible at https://teleport.davidshaevel.com
2. **GKE Start workflow:** Trigger manually → cluster created → Portainer Agent installed → GKE appears in Portainer UI → Teleport shows portainer-gke in `tctl kube ls`
3. **GKE Stop workflow:** Trigger manually → GKE removed from Portainer → cluster deleted → $0 cost
4. **AKS Stop workflow:** Trigger manually → DNS records deleted → cluster stopped → ~$48/month saved
5. **Failure safety:** Intentionally fail GKE Start mid-way → verify cleanup step deletes the cluster
6. **Local scripts still work:** Run scripts locally → confirm logging still works, interactive prompts still appear
