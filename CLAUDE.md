# Kubernetes Developer Platform - Claude Context

<!-- If CLAUDE.local.md exists, read it for additional context (Azure resource IDs, cluster details, etc.) -->

## Project Overview

A multi-cloud Kubernetes developer platform following the [Build Your First Kubernetes Developer Platform](https://rawkode.academy/learning-paths/build-your-first-kubernetes-developer-platform) learning path from Rawkode Academy. Manages AKS and GKE clusters through Portainer Business Edition with Teleport-secured zero-trust access — no direct public endpoints exposed.

**Key Technologies:**
- **Cloud:** Azure (AKS), Google Cloud (GKE)
- **Container Orchestration:** Kubernetes (multi-cluster, Azure CNI Overlay + Cilium)
- **Platform Management:** Portainer Business Edition (BE)
- **Secure Access:** Teleport Community Edition (self-hosted)
- **CI/CD:** GitHub Actions (workflow_dispatch)
- **IaC:** Azure CLI, gcloud CLI, Helm
- **DNS:** Cloudflare (API-managed)
- **CLI Tools:** kubectl, helm, az, gcloud, gh, tsh, tctl

**Project Management:**
- **Issue Tracking:** Linear (Team Tacocat)
- **Version Control:** GitHub
- **Branching Strategy:** Feature branches with PR workflow

---

## Architecture

```
Internet
    |
    v
Azure Load Balancer (port 443)
    |
    v
AKS Cluster (k8s-developer-platform-rg, eastus)
    |
    +-- teleport-cluster namespace
    |       |
    |       +-- Teleport Proxy (HTTPS, LoadBalancer)
    |       |       Web UI:   https://<TELEPORT_DOMAIN>
    |       |       App Proxy: routes to Portainer (ClusterIP)
    |       |       K8s Proxy: authenticated kubectl access
    |       |
    |       +-- Teleport Auth (ClusterIP)
    |       +-- Teleport Agent (app + kube registration)
    |
    +-- portainer namespace
    |       |
    |       Portainer BE (ClusterIP, port 9443 HTTPS)
    |           (no public IP, accessed via Teleport)
    |           Manages: AKS (local) + GKE (remote agent)
    |
    +-- (future namespaces: Argo CD, Crossplane, monitoring)

GKE Cluster (us-central1-a)
    |
    +-- portainer namespace
    |       +-- Portainer Agent (LoadBalancer, port 9001)
    |               (loadBalancerSourceRanges: AKS egress IP only)
    |
    +-- teleport-cluster namespace
            +-- Teleport Kube Agent (kubectl access via Teleport)
```

All traffic flows through Teleport. Portainer has no public endpoint. The GKE Portainer Agent LoadBalancer is restricted to the AKS cluster's egress IP via `loadBalancerSourceRanges`.

**Key difference from davidshaevel-portainer:** This cluster uses Standard_B2ms (8 GiB) with Azure CNI Overlay + Cilium networking, sized for the full platform stack (Argo CD, Crossplane, monitoring).

---

## Learning Path Progress

| # | Module | Status |
|---|--------|--------|
| 1 | Hands-on Introduction to Portainer | Video watched |
| 2 | Hands-on Introduction to DevStand | Not started |
| 3 | Introduction to Crossplane | Not started |
| 4 | Crossplane in Action | Not started |
| 5 | Hands-on Introduction to Waypoint | Not started |
| 6 | Monitoring with Prometheus & Robusta | Not started |

---

## Helpful Commands

```bash
# Azure CLI
az login
az account set --subscription "<subscription-name>"
az group list --output table

# AKS
az aks get-credentials --resource-group k8s-developer-platform-rg --name k8s-developer-platform-aks
az aks list --resource-group k8s-developer-platform-rg --output table

# GKE
gcloud container clusters get-credentials portainer-gke --zone us-central1-a --project <project-id>
gcloud container clusters list --project <project-id>

# Kubernetes
kubectl get nodes
kubectl get sc                    # Check StorageClass
kubectl get all -n portainer      # Check Portainer resources
kubectl get all -n teleport-cluster  # Check Teleport resources

# Cilium (verify CNI)
kubectl get pods -n kube-system -l k8s-app=cilium
cilium status                     # If cilium CLI installed

# Helm
helm list -A                       # All Helm releases
helm status portainer -n portainer
helm status teleport-cluster -n teleport-cluster
helm status teleport-agent -n teleport-cluster

# Teleport client (tsh) - requires tsh installed locally
tsh login --proxy=<TELEPORT_DOMAIN> --user=admin
tsh kube ls                       # List available kube clusters
tsh kube login k8s-developer-platform-aks  # Switch kubectl to AKS via Teleport
tsh kube login portainer-gke      # Switch kubectl to GKE via Teleport
tsh logout

# Teleport admin (via auth pod) - requires direct AKS context, not Teleport
kubectl exec -n teleport-cluster deployment/teleport-cluster-auth -- tctl status
kubectl exec -n teleport-cluster deployment/teleport-cluster-auth -- tctl users ls
kubectl exec -n teleport-cluster deployment/teleport-cluster-auth -- tctl apps ls
kubectl exec -n teleport-cluster deployment/teleport-cluster-auth -- tctl kube ls
```

---

## Script Execution & Logging

All scripts source `scripts/config.sh` for shared configuration. When running locally, output is logged to `/tmp/${USER}-k8s-platform/` so David can `tail -f` from a separate terminal. In CI (GitHub Actions), file logging is skipped.

```bash
# Tailing from a separate terminal:
tail -f /tmp/${USER}-k8s-platform/aks-create.log
```

---

## Environment Variables

Environment-specific values are stored in `.envrc` (gitignored). A committed `.envrc.example` documents the required variables.

**Setup:**
```bash
cp .envrc.example .envrc
# Edit .envrc with your values
```

With [direnv](https://direnv.net/), `.envrc` is auto-sourced. Otherwise: `source .envrc`

**Current variables:**

| Variable | Used By | Purpose |
|----------|---------|---------|
| `AZURE_SUBSCRIPTION` | `scripts/config.sh` | Azure subscription name or ID for all `az` commands |
| `GCP_PROJECT` | `scripts/config.sh` | GCP project ID for GKE cluster |
| `CLOUDFLARE_API_TOKEN` | `scripts/teleport/dns.sh` | Cloudflare API token with DNS edit permissions |
| `CLOUDFLARE_ZONE_ID` | `scripts/teleport/dns.sh` | Cloudflare zone ID for davidshaevel.com |
| `TELEPORT_ACME_EMAIL` | `scripts/teleport/install.sh` | Email for Let's Encrypt ACME certificate notifications |
| `PORTAINER_ADMIN_PASSWORD` | `scripts/portainer/gke-agent-register.sh` | Portainer admin password for REST API automation |
| `TELEPORT_DOMAIN` | `scripts/config.sh` | Teleport domain (defaults to teleport.davidshaevel.com) |

Scripts will error with a clear message if a required env var is missing.

---

## Repository Structure

```
davidshaevel-k8s-platform/
|
+-- .bare/                             # Bare git repository
+-- .git                               # Points to .bare
+-- .wakatime-project                  # WakaTime project name
|
+-- main/                              # Main branch worktree
|   +-- CLAUDE.md                      # Public project context (this file)
|   +-- CLAUDE.local.md                # Sensitive project context (gitignored)
|   +-- SESSION_LOG.md                 # Cross-agent memory (gitignored)
|   +-- .envrc                         # Environment variables (gitignored)
|   +-- .envrc.example                 # Template for .envrc (committed)
|   +-- .gitignore                     # Git ignore patterns
|   +-- scripts/                       # Reusable az/kubectl/helm/gcloud scripts
|   |   +-- config.sh                  # Shared configuration (sourced by all scripts)
|   |   +-- aks/                       # AKS cluster lifecycle
|   |   +-- gke/                       # GKE cluster lifecycle
|   |   +-- github/                    # GitHub Actions setup (SP, SA, secrets)
|   |   +-- portainer/                 # Portainer server + agent install/uninstall
|   |   +-- teleport/                  # Teleport server + agent install/uninstall
|   +-- .github/workflows/             # GitHub Actions workflows
|   +-- docs/                          # Documentation
|       +-- plans/                     # Design documents and plans
|
+-- <feature-worktrees>/               # Feature branch worktrees (flat!)
```

---

## References

- **Linear Project:** [Kubernetes Developer Platform](https://linear.app/davidshaevel-dot-com/project/kubernetes-developer-platform-e5de2eef1556)
- **Design Doc:** `docs/plans/2026-02-13-k8s-platform-design.md`
- **Learning Path:** [Build Your First Kubernetes Developer Platform](https://rawkode.academy/learning-paths/build-your-first-kubernetes-developer-platform)
- **Portainer BE Install Docs:** [Kubernetes Baremetal](https://docs.portainer.io/start/install/server/kubernetes/baremetal)
- **Azure AKS Docs:** [Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/)
- **Google GKE Docs:** [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine/docs)
- **Teleport Helm Deploy:** [Deploy on Kubernetes](https://goteleport.com/docs/deploy-a-cluster/helm-deployments/kubernetes-cluster/)
- **Cloudflare DNS API:** [DNS Records](https://developers.cloudflare.com/api/resources/dns/subresources/records/)
