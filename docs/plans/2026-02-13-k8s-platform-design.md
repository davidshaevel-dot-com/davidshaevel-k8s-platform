# Design: Kubernetes Developer Platform (davidshaevel-k8s-platform)

**Date:** 2026-02-13
**Status:** Approved
**Related:** [TT-148](https://linear.app/davidshaevel-dot-com/issue/TT-148/deploy-davidshaevel-platform-to-gke)

## Overview

Evolve the davidshaevel-portainer project into a full Kubernetes developer platform that mirrors how an SRE on a platform team would build and operate multi-cloud infrastructure. The platform manages workload environments across Azure, GCP, and AWS using industry-standard tools for GitOps, networking, infrastructure-as-code, and observability.

## Goals

1. **Learn platform engineering tools** by building a real multi-cloud platform (Argo CD, Crossplane, Cilium, DevStand)
2. **Portfolio showcase** demonstrating SRE/platform engineering skills
3. **Multi-cloud workload deployment** — deploy applications (e.g., dochound) to any cluster
4. **Cost-optimized** — ephemeral workload environments, always-on control plane only when needed

## Architecture

### Cloud Strategy

**Azure is the primary cloud provider** for the always-on control plane:
- Resource group: `k8s-developer-platform-rg` (eastus)
- AKS cluster: `k8s-developer-platform-aks` — Portainer, Teleport, Argo CD, Crossplane, monitoring stack
- Azure Key Vault: Secrets management backend for External Secrets Operator
- Azure Container Registry (ACR): Primary image registry
- Fresh infrastructure (not carried forward from portainer-rg / portainer-aks)

**GCP and AWS are ephemeral workload environments:**
- GKE clusters (GCP): Created/destroyed on demand via GitHub Actions or Crossplane
- EKS clusters (AWS): Created/destroyed on demand via Crossplane
- Azure workload clusters: Also ephemeral, created alongside GCP/AWS

**ACR as primary registry** with decoupled replication:
- ACR is the single source of truth for container images
- GCP Artifact Registry: Replicated from ACR when GKE environments are active
- AWS ECR: Replicated from ACR when EKS environments are active
- **Build workflow:** Builds image and pushes to ACR only. Build success is never blocked by downstream registries.
- **Replication workflow:** Triggers after build succeeds (`workflow_run`) or manually. Pulls from ACR and pushes to target cloud registries. Each cloud is a separate job — failures are isolated and independently retryable. Only replicates to clouds that are currently active.
- ACR's built-in geo-replication only works within Azure regions, not across cloud providers.

### Platform Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| Platform Management | Portainer BE | Multi-cluster Kubernetes management UI |
| Secure Access | Teleport CE | Zero-trust access to all clusters and apps |
| GitOps | Argo CD | Declarative deployments from Git |
| Networking | Cilium + Hubble | eBPF-based CNI, network policies, observability |
| Infrastructure | Crossplane | Provision cloud resources (GKE, EKS clusters) from K8s |
| Developer Portal | DevStand | Developer self-service portal |
| Secrets Management | External Secrets Operator | Sync secrets from Azure Key Vault to K8s |
| Monitoring | Prometheus | Metrics collection |
| Logging | Grafana Loki | Log aggregation and search |
| Dashboards | Grafana | Visualization and dashboards |
| Alerting | Alertmanager | Alert routing and notification |
| Network Observability | Hubble (via Cilium) | Service map, network flow visualization |
| CI/CD | GitHub Actions | Workflow automation, image builds |
| DNS | Cloudflare | API-managed DNS |
| TLS | Let's Encrypt | Certificates via Teleport ACME |

### Cluster Topology

```
AKS Control Plane (Azure, always-on when active)
├── portainer namespace        → Portainer BE server
├── teleport-cluster namespace → Teleport proxy + auth + agents
├── argocd namespace           → Argo CD server + controllers
├── crossplane-system namespace → Crossplane + providers
├── external-secrets namespace → External Secrets Operator + ClusterSecretStore
├── monitoring namespace       → Prometheus + Grafana + Alertmanager + Loki
├── cilium namespace           → Cilium CNI + Hubble
└── devstand namespace         → DevStand portal

GKE Workload Cluster (GCP, ephemeral) — registered with Argo CD via dedicated service account
├── portainer namespace        → Portainer Agent
├── teleport-cluster namespace → Teleport kube agent
├── cilium namespace           → Cilium CNI + Hubble relay
├── external-secrets namespace → External Secrets Operator + ClusterSecretStore
└── workload namespaces        → Application deployments

EKS Workload Cluster (AWS, ephemeral) — registered with Argo CD via dedicated service account
├── portainer namespace        → Portainer Agent
├── teleport-cluster namespace → Teleport kube agent
├── cilium namespace           → Cilium CNI + Hubble relay
├── external-secrets namespace → External Secrets Operator + ClusterSecretStore
└── workload namespaces        → Application deployments

Azure Workload Cluster (Azure, ephemeral)
├── (same structure as GKE/EKS workload clusters)
└── workload namespaces        → Application deployments
```

## Repository Strategy

### New Repositories

| Repository | Purpose |
|------------|---------|
| **davidshaevel-k8s-platform** | K8s platform configs, Helm values, Crossplane compositions, Argo CD apps, GitHub Actions workflows |
| **davidshaevel-website** | davidshaevel.com application code (Nest.js + Next.js), Vercel deployment, Neon database |
| **davidshaevel-ecs-platform** | Renamed from davidshaevel-platform — ECS/Fargate infrastructure (Terraform, GitHub Actions) |

### Migration from davidshaevel-portainer

davidshaevel-k8s-platform starts fresh (not a fork) but copies forward:
- All scripts from `scripts/` (aks/, gke/, portainer/, teleport/, github/)
- GitHub Actions workflows (`.github/workflows/`)
- `scripts/config.sh` shared configuration (updated with new resource group / cluster names)
- `.envrc.example` template
- Design documents from `docs/plans/`

New Azure infrastructure is created from scratch (`k8s-developer-platform-rg` / `k8s-developer-platform-aks`), separate from the original `portainer-rg` / `portainer-aks`. davidshaevel-portainer is archived after migration (read-only, README points to new repo).

### Repository Structure (davidshaevel-k8s-platform)

```
davidshaevel-k8s-platform/
├── scripts/
│   ├── config.sh                    # Shared configuration
│   ├── aks/                         # AKS cluster lifecycle
│   ├── gke/                         # GKE cluster lifecycle
│   ├── eks/                         # EKS cluster lifecycle (new)
│   ├── portainer/                   # Portainer server + agent
│   ├── teleport/                    # Teleport server + agent
│   ├── argocd/                      # Argo CD installation
│   ├── cilium/                      # Cilium + Hubble installation
│   ├── crossplane/                  # Crossplane installation scripts
│   ├── external-secrets/            # External Secrets Operator
│   ├── monitoring/                  # Prometheus + Grafana + Alertmanager + Loki
│   ├── devstand/                    # DevStand installation
│   ├── acr/                         # ACR setup + replication
│   └── github/                      # GitHub Actions setup
├── helm-values/                     # Helm value overrides per tool
├── crossplane/                      # Crossplane compositions and claims
│   ├── xrds/                        # Composite Resource Definitions (API contracts)
│   ├── compositions/                # Reusable cloud resource templates
│   └── claims/                      # Environment-specific claims
├── argocd/                          # Argo CD application manifests
│   ├── applications/                # App definitions
│   └── projects/                    # Argo CD project configs
├── .github/workflows/               # GitHub Actions workflows
├── docs/
│   ├── plans/                       # Design documents
│   ├── agendas/                     # Work session agendas
│   └── postmortems/                 # Incident postmortems
├── CLAUDE.md                        # Project context
├── .envrc.example                   # Environment variable template
└── README.md                        # Portfolio-ready documentation
```

## Phased Implementation

### Phase 1: Repo Setup and Infrastructure
- Create davidshaevel-k8s-platform repository
- Copy scripts, workflows, configs from davidshaevel-portainer
- Set up bare repo + worktree structure
- Update `scripts/config.sh` with new names (`k8s-developer-platform-rg`, `k8s-developer-platform-aks`)
- Create resource group `k8s-developer-platform-rg` in eastus
- Create AKS cluster `k8s-developer-platform-aks` with Azure CNI Overlay + Cilium (`--network-plugin azure --network-dataplane cilium --network-plugin-mode overlay`)
- Install Portainer BE, Teleport, Teleport agent (using existing scripts)
- Configure Cloudflare DNS for Teleport
- Create new Azure service principal scoped to `k8s-developer-platform-rg`
- Configure GitHub secrets (Azure service principal, GCP credentials, Cloudflare API token)
- Verify AKS Start/Stop, GKE Start/Stop workflows work from new repo

### Phase 2: Container Images and ACR
- Create Azure Container Registry
- Build and push davidshaevel.com images to ACR
- Set up ACR credentials for AKS (managed identity or image pull secret)
- Create build workflow (build → push to ACR)
- Create replication workflow (pull from ACR → push to active cloud registries, one job per cloud)

### Phase 3: Argo CD
- Install Argo CD on AKS control plane via Helm
- Register via Teleport (app access)
- Create Argo CD applications for existing platform components (e.g., Portainer, Teleport)
- Set up GitOps workflow: push to repo → Argo CD syncs to cluster

### Phase 4: Cilium
- Cilium CNI is provisioned with the cluster in Phase 1 (`--network-dataplane cilium`)
- Enable Hubble for network flow observability
- Define network policies for namespace isolation
- Install Hubble UI (accessible via Teleport)
- Workload clusters: GKE uses Dataplane V2 (Cilium-based) at creation; EKS installs Cilium via Helm as part of platform agent setup (Phase 8)

### Phase 5: Crossplane
- Install Crossplane on AKS control plane
- Install GCP and AWS providers
- Configure `ProviderConfig` credentials (initially manual K8s secrets, migrated to ESO-managed secrets in Phase 9)
- Create compositions for GKE and EKS cluster provisioning
- Replace `gcloud container clusters create` with Crossplane claims
- Update GKE lifecycle GitHub Actions workflows and scripts to use Crossplane claims instead of gcloud commands
- Add Azure provider for ephemeral Azure workload clusters

### Phase 6: DevStand
- Install DevStand on AKS
- Configure service catalog
- Integrate with Crossplane for self-service environment provisioning

### Phase 7: Monitoring
- Install Prometheus + Grafana + Alertmanager via kube-prometheus-stack Helm chart
- Configure Grafana dashboards for cluster and workload metrics
- Hubble provides network-layer observability (installed with Cilium in Phase 4)
- Configure Prometheus to scrape Cilium and Hubble metrics
- Register Grafana via Teleport (app access)
- Set up basic alerting rules

### Phase 8: EKS
- Verify Crossplane AWS provider is installed and configured
- Create EKS cluster composition
- Add EKS lifecycle workflows (GitHub Actions)
- Set up ACR → ECR image replication
- Install platform agents (Portainer, Teleport, Cilium, ESO) on EKS

### Phase 9: Secrets Management
- Create Azure Key Vault in `k8s-developer-platform-rg`
- Install External Secrets Operator (ESO) via Helm on AKS (`external-secrets` namespace)
- Configure `ClusterSecretStore` to connect to Azure Key Vault (via workload identity or service principal)
- Migrate existing hardcoded secrets (Teleport, Portainer, ACR credentials) to Key Vault + `ExternalSecret` resources
- Workload clusters: Install ESO on each ephemeral cluster as part of platform agent setup, with `ClusterSecretStore` pointing to Azure Key Vault as the single source of truth. Cross-cloud authentication: GKE uses Workload Identity Federation, EKS uses IAM OIDC provider with IRSA, Azure workload clusters use Azure AD Workload Identity
- Add install/uninstall scripts to `scripts/external-secrets/`
- Store Helm value overrides in `helm-values/external-secrets/`

### Phase 10: Logging
- Install Grafana Loki via Helm on AKS (`monitoring` namespace, alongside Prometheus stack)
- Deploy Promtail as DaemonSet for log collection
- Configure Grafana data source for Loki
- Configure log retention (Azure Blob Storage or local PV for cost optimization)
- Set up basic LogQL queries and Grafana dashboards for log exploration
- Add install/uninstall scripts to `scripts/monitoring/` (extend existing monitoring scripts)

## Workload Deployment

Any application (e.g., dochound, davidshaevel.com) can be deployed to any cluster:
1. Push container image to ACR (build workflow)
2. Replication workflow pushes to target cloud's registry
3. Create Argo CD application manifest pointing to the workload repo
4. Argo CD deploys to the target cluster
5. Cilium network policies control traffic
6. Prometheus collects metrics, Grafana visualizes

## Cost Strategy

| Component | Running (per month) | Stopped (per month) |
|-----------|---------------------|---------------------|
| AKS control plane (free tier) | Free | Free |
| AKS node (Standard_B2ms or larger, 8GB+ RAM) | ~$60-90 | $0 |
| AKS Load Balancer (Teleport) | ~$18 | $0 |
| AKS Managed Disks (PVs) | ~$5-10 | ~$5-10 |
| ACR (Basic tier) | ~$5 | ~$5 |
| Azure Key Vault (Standard) | <$1 | <$1 |
| GKE workload cluster (e2-medium node) | ~$25 | $0 (deleted) |
| GKE control plane (free tier credit) | Free | $0 (deleted) |
| EKS workload cluster (t3.medium node) | ~$30 | $0 (deleted) |
| EKS control plane | ~$73 | $0 (deleted) |
| **Total (all running)** | **~$215-255** | **~$10-15** |

AKS stop/start preserves persistent volumes. GKE and EKS are fully deleted when stopped ($0). ACR, Key Vault, and managed disks are the only costs when everything is down. GKE free tier provides $74.40/month credit per billing account, covering the control plane for one zonal cluster. Without the free tier, GKE would add ~$73/month.

## Linear Project Structure

**Project:** Kubernetes Developer Platform
**Team:** Team Tacocat

> **Note:** Phase numbers describe logical architecture layers (ordered for readability). The `Blocked By` column below reflects actual execution dependencies — issues without upstream blockers can run in parallel regardless of phase number.

| # | Issue | Priority | Blocked By |
|---|-------|----------|------------|
| 1 | Repo setup and migration from davidshaevel-portainer | High | -- |
| 2 | Container images and ACR setup | High | #1 |
| 3 | Install and configure Argo CD | High | #1 |
| 4 | Configure Hubble and Cilium network policies | Medium | #1 |
| 5 | Install and configure Crossplane | Medium | #3 |
| 6 | Install and configure DevStand | Medium | #5 |
| 7 | Install and configure Prometheus, Grafana, and Alertmanager | Medium | #1, #4 |
| 8 | Add EKS cluster lifecycle | Low | #5 |
| 9 | Set up secrets management with External Secrets Operator | Medium | #1 |
| 10 | Set up log aggregation with Grafana Loki | Medium | #7 |
| 11 | Rename davidshaevel-platform to davidshaevel-ecs-platform | Medium | #1 |
| 12 | Archive davidshaevel-portainer | Medium | #1 |
