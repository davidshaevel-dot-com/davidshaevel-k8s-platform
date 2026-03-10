# Kubernetes Developer Platform

A multi-cloud Kubernetes developer platform with zero-trust access, GitOps deployments, full-stack observability, and cost-optimized lifecycle automation. Manages AKS and GKE clusters through a single Argo CD instance with Teleport-secured access — no direct public endpoints exposed.

Built following the [Build Your First Kubernetes Developer Platform](https://rawkode.academy/learning-paths/build-your-first-kubernetes-developer-platform) learning path from Rawkode Academy.

## Architecture

```
Internet
    |
    v
Azure Load Balancer (port 443)
    |
    v
AKS Cluster (eastus) — always-on primary
    |
    +-- teleport-cluster namespace
    |       +-- Teleport Proxy (HTTPS, LoadBalancer)
    |       |       Web UI, App Proxy, K8s Proxy
    |       +-- Teleport Auth (ClusterIP)
    |       +-- Teleport Agent (registers apps + kube clusters)
    |
    +-- portainer namespace
    |       Portainer BE (ClusterIP, accessed via Teleport)
    |           Manages: AKS (local) + GKE (remote agent)
    |
    +-- argocd namespace
    |       Argo CD (ClusterIP, accessed via Teleport)
    |           Manages: davidshaevel-website on AKS + GKE
    |
    +-- monitoring namespace
    |       +-- Prometheus (metrics, 7d retention)
    |       +-- Grafana (dashboards, accessed via Teleport)
    |       +-- Node Exporter, Kube State Metrics
    |
    +-- davidshaevel-website namespace
    |       +-- Frontend (Next.js, port 3000)
    |       +-- Backend (NestJS, port 3001)
    |       +-- Database (PostgreSQL 15)
    |
    +-- kube-system namespace (Azure-managed)
            +-- Cilium (eBPF CNI via Azure CNI Overlay)
            +-- Hubble Relay + UI (network flow observability via ACNS)

GKE Cluster (us-central1-a) — ephemeral secondary
    |
    +-- davidshaevel-website namespace
    |       +-- Frontend, Backend, Database
    |       (same manifests, pulls from ACR via image pull secret)
    |
    +-- portainer namespace
    |       +-- Portainer Agent (LoadBalancer, AKS egress IP only)
    |
    +-- teleport-cluster namespace
            +-- Teleport Kube Agent + Website App
```

All traffic flows through Teleport — no services have direct public endpoints except the Teleport proxy. One Argo CD instance on AKS manages both clusters. GKE is fully ephemeral: when deleted and recreated, Argo CD auto-syncs everything back.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Cloud | Azure (AKS), Google Cloud (GKE) |
| Container Orchestration | Kubernetes (multi-cluster) |
| Networking | Azure CNI Overlay + Cilium (AKS), Dataplane V2 (GKE) |
| Container Registry | Azure Container Registry (ACR) |
| Platform Management | Portainer Business Edition |
| Secure Access | Teleport Community Edition (self-hosted, zero-trust) |
| GitOps | Argo CD (single control plane, multi-cluster) |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana) |
| Network Observability | Hubble (ACNS) — flow logs, service map, metrics |
| CI/CD | GitHub Actions (workflow_dispatch) |
| DNS | Cloudflare (API-managed) |
| TLS | Let's Encrypt (ACME via Teleport) |
| IaC | Azure CLI, gcloud CLI, Helm |

## GitHub Actions Workflows

All workflows are triggered manually via `workflow_dispatch` from the GitHub Actions UI.

| Workflow | Description |
|----------|-------------|
| **AKS Start** | Start the AKS cluster, wait for pods, update Cloudflare DNS, verify Teleport accessibility |
| **AKS Stop** | Delete Cloudflare DNS records, stop the AKS cluster to save costs |
| **GKE Start** | Orchestrated rebuild: create cluster (Dataplane V2), install Portainer/Teleport agents, set up ACR pull secret, register in Argo CD, apply network policies, register website in Teleport |
| **GKE Stop** | Deregister from Portainer via API, delete the GKE cluster |

**AKS Stop** and **GKE Stop** have workflow inputs shown in the "Run workflow" dialog:

| Workflow | Input | Default | Description |
|----------|-------|---------|-------------|
| AKS Stop | `delete_dns` | `true` | Delete Cloudflare DNS records for Teleport |
| GKE Stop | `deregister_portainer` | `true` | Remove GKE endpoint from Portainer |

### Setting Up GitHub Repository Secrets

The workflows require an Azure service principal, a GCP service account, and 8 GitHub repository secrets. Helper scripts automate the entire setup.

First, ensure `.envrc` is configured with all required variables (see [.envrc.example](.envrc.example)):

```bash
cp .envrc.example .envrc
# Edit .envrc with your values
source .envrc
```

Then run the setup scripts:

1. **Create the Azure service principal** (requires `az` CLI, logged in):

   ```bash
   ./scripts/github/create-azure-sp.sh
   ```

2. **Create the GCP service account** (requires `gcloud` CLI, authenticated):

   ```bash
   ./scripts/github/create-gcp-sa.sh
   ```

3. **Configure all GitHub secrets** (requires `gh` CLI, authenticated):

   ```bash
   ./scripts/github/configure-secrets.sh
   ```

4. **Clean up credential files:**

   ```bash
   rm scripts/github/azure-sp.json scripts/github/gcp-sa-key.json
   ```

### Required Secrets

| Secret | Description | Source |
|--------|-------------|--------|
| `AZURE_CREDENTIALS` | Azure service principal JSON | `create-azure-sp.sh` |
| `AZURE_SUBSCRIPTION` | Azure subscription name or ID | `.envrc` |
| `GCP_CREDENTIALS_JSON` | GCP service account key JSON | `create-gcp-sa.sh` |
| `GCP_PROJECT` | GCP project ID | `.envrc` |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token (Zone:DNS:Edit) | `.envrc` |
| `CLOUDFLARE_ZONE_ID` | Cloudflare zone ID | `.envrc` |
| `TELEPORT_ACME_EMAIL` | Email for Let's Encrypt certificates | `.envrc` |
| `PORTAINER_ADMIN_PASSWORD` | Portainer admin password for API automation | `.envrc` |

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`)
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) (`gcloud`) with `gke-gcloud-auth-plugin`
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [jq](https://jqlang.github.io/jq/download/)
- [GitHub CLI](https://cli.github.com/) (`gh`) — for configuring workflow secrets
- An Azure subscription
- A GCP project with billing enabled
- A Cloudflare-managed domain (for DNS)
- A Portainer Business Edition license key

## Local Setup

1. **Clone the repository:**

   ```bash
   git clone https://github.com/davidshaevel-dot-com/davidshaevel-k8s-platform.git
   cd davidshaevel-k8s-platform
   ```

2. **Configure environment variables:**

   ```bash
   cp .envrc.example .envrc
   # Edit .envrc with your values
   ```

   If using [direnv](https://direnv.net/), `.envrc` is auto-sourced. Otherwise:

   ```bash
   source .envrc
   ```

3. **Create the AKS cluster:**

   ```bash
   ./scripts/aks/create.sh
   ```

4. **Install Portainer:**

   ```bash
   ./scripts/portainer/aks-install.sh
   ```

5. **Install Teleport and configure DNS:**

   ```bash
   ./scripts/teleport/install.sh
   ./scripts/teleport/dns.sh
   ```

   Wait a few minutes for DNS propagation and TLS certificate issuance, then verify `https://<your-teleport-domain>` is accessible before continuing.

6. **Deploy the Teleport agent** (registers Portainer app and Kubernetes cluster):

   ```bash
   ./scripts/teleport/aks-agent-install.sh
   ```

7. **Install Argo CD** (GitOps deployments):

   ```bash
   ./scripts/argocd/install.sh
   ./scripts/argocd/teleport-register.sh
   ```

8. **Install monitoring stack** (Prometheus + Grafana):

   ```bash
   ./scripts/monitoring/install.sh
   ./scripts/monitoring/teleport-register.sh
   ```

9. **Enable Cilium observability** (Hubble):

   ```bash
   ./scripts/cilium/hubble-enable.sh
   ./scripts/cilium/hubble-ui-install.sh
   ./scripts/cilium/apply-policies.sh
   ```

10. **Add a GKE cluster** (optional, multi-cluster setup):

    ```bash
    ./scripts/gke/start.sh
    ```

## Scripts

All scripts source `scripts/config.sh` for shared configuration. When running locally, output is logged to `/tmp/$USER-k8s-platform/`. In CI (GitHub Actions), file logging is skipped.

### AKS Cluster (`scripts/aks/`)

| Script | Description |
|--------|-------------|
| `aks/create.sh` | Create the AKS cluster (Azure CNI Overlay + Cilium + ACNS) |
| `aks/delete.sh` | Delete the AKS cluster |
| `aks/start.sh` | Start a stopped cluster |
| `aks/stop.sh` | Stop the cluster (save costs) |
| `aks/status.sh` | Show cluster status |
| `aks/credentials.sh` | Fetch kubeconfig credentials |

### GKE Cluster (`scripts/gke/`)

| Script | Description |
|--------|-------------|
| `gke/create.sh` | Create the GKE cluster (Dataplane V2, enables API if needed) |
| `gke/delete.sh` | Delete the GKE cluster (interactive, requires confirmation) |
| `gke/start.sh` | Orchestrated rebuild (create + agents + ACR + Argo CD + policies + Teleport) |
| `gke/stop.sh` | Delete the GKE cluster (non-interactive, for scripted use) |
| `gke/status.sh` | Show cluster status |
| `gke/credentials.sh` | Fetch kubeconfig credentials |
| `gke/acr-pull-secret.sh` | Create ACR image pull secret for cross-cloud image access |
| `gke/argocd-cluster-add.sh` | Register GKE as a remote cluster in Argo CD |
| `gke/apply-network-policies.sh` | Apply Kubernetes NetworkPolicy for namespace isolation |

### Portainer (`scripts/portainer/`)

| Script | Description |
|--------|-------------|
| `portainer/aks-install.sh` | Install Portainer BE server via Helm on AKS |
| `portainer/aks-uninstall.sh` | Uninstall Portainer server |
| `portainer/aks-status.sh` | Show Portainer deployment status |
| `portainer/gke-agent-install.sh` | Install Portainer Agent on GKE via kubectl manifest |
| `portainer/gke-agent-uninstall.sh` | Remove Portainer Agent from GKE |
| `portainer/gke-agent-register.sh` | Register GKE endpoint in Portainer via REST API |
| `portainer/gke-agent-deregister.sh` | Remove GKE endpoint from Portainer via REST API |
| `portainer/gke-agent-restrict-lb.sh` | Restrict Agent LoadBalancer to AKS egress IP only |

### Teleport (`scripts/teleport/`)

| Script | Description |
|--------|-------------|
| `teleport/install.sh` | Install Teleport Community Edition via Helm |
| `teleport/uninstall.sh` | Uninstall Teleport |
| `teleport/status.sh` | Show Teleport deployment status |
| `teleport/dns.sh` | Create/update Cloudflare DNS records (A + wildcard) |
| `teleport/dns-delete.sh` | Delete Cloudflare DNS records |
| `teleport/aks-agent-install.sh` | Deploy Teleport agent on AKS (app + kube registration) |
| `teleport/aks-agent-uninstall.sh` | Remove Teleport agent from AKS |
| `teleport/gke-agent-install.sh` | Deploy Teleport kube agent on GKE |
| `teleport/gke-agent-uninstall.sh` | Remove Teleport agent from GKE |

### Argo CD (`scripts/argocd/`)

| Script | Description |
|--------|-------------|
| `argocd/install.sh` | Install Argo CD via Helm on AKS |
| `argocd/uninstall.sh` | Uninstall Argo CD |
| `argocd/status.sh` | Show Argo CD deployment status and applications |
| `argocd/teleport-register.sh` | Register Argo CD as a Teleport application |

### Monitoring (`scripts/monitoring/`)

| Script | Description |
|--------|-------------|
| `monitoring/install.sh` | Install kube-prometheus-stack (Prometheus + Grafana) via Helm |
| `monitoring/uninstall.sh` | Uninstall the monitoring stack |
| `monitoring/status.sh` | Show monitoring stack status |
| `monitoring/teleport-register.sh` | Register Grafana as a Teleport application |

### Cilium / Hubble (`scripts/cilium/`)

| Script | Description |
|--------|-------------|
| `cilium/status.sh` | Show Cilium, Hubble, and network policy status |
| `cilium/apply-policies.sh` | Apply CiliumNetworkPolicy namespace isolation on AKS |
| `cilium/hubble-enable.sh` | Enable Hubble relay and UI via ACNS |
| `cilium/hubble-disable.sh` | Disable Hubble relay and UI |
| `cilium/hubble-ui-install.sh` | Install Hubble UI on AKS |
| `cilium/hubble-ui-uninstall.sh` | Uninstall Hubble UI |

### ACR (`scripts/acr/`)

| Script | Description |
|--------|-------------|
| `acr/create.sh` | Create Azure Container Registry |
| `acr/delete.sh` | Delete Azure Container Registry |

### Website (`scripts/website/`)

| Script | Description |
|--------|-------------|
| `website/teleport-register.sh` | Register AKS website as a Teleport application |
| `website/gke-teleport-register.sh` | Register GKE website as a Teleport application |

### GitHub Actions Setup (`scripts/github/`)

| Script | Description |
|--------|-------------|
| `github/create-azure-sp.sh` | Create Azure service principal for GitHub Actions |
| `github/create-gcp-sa.sh` | Create GCP service account for GitHub Actions |
| `github/configure-secrets.sh` | Configure all required GitHub repository secrets |

## Environment Variables

Defined in `.envrc` (gitignored). See [.envrc.example](.envrc.example) for the template.

| Variable | Purpose |
|----------|---------|
| `AZURE_SUBSCRIPTION` | Azure subscription name or ID |
| `GCP_PROJECT` | GCP project ID for GKE cluster |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token (Zone:DNS:Edit) |
| `CLOUDFLARE_ZONE_ID` | Cloudflare zone ID for the domain |
| `TELEPORT_ACME_EMAIL` | Email for Let's Encrypt certificate notifications |
| `PORTAINER_ADMIN_PASSWORD` | Portainer admin password for API automation |
| `ACR_SP_APP_ID` | Service principal app ID for GKE→ACR image pull |
| `ACR_SP_PASSWORD` | Service principal password for GKE→ACR image pull |
| `TELEPORT_DOMAIN` | Teleport domain (defaults to teleport.davidshaevel.com) |

## Project Management

- **Issue Tracking:** [Linear (Team Tacocat)](https://linear.app/davidshaevel-dot-com/project/kubernetes-developer-platform-e5de2eef1556)
- **Repository:** [GitHub](https://github.com/davidshaevel-dot-com/davidshaevel-k8s-platform)

## Cost Estimate

| Component | Running | Stopped |
|-----------|---------|---------|
| AKS control plane | Free | Free |
| AKS Standard_B4ls_v2 node (1x) | ~$107 | $0 |
| AKS Load Balancer (Teleport) | ~$18 | $0 |
| AKS Managed Disks (PVs) | ~$1-5 | ~$1-5 |
| ACR Basic tier | ~$5 | ~$5 |
| GKE Standard (e2-standard-2, 1 node) | ~$49 | $0 (deleted) |
| **Total** | **~$185-190** | **~$6-10** |

GKE has no stop/start — the **GKE Stop** workflow deletes the cluster entirely ($0), and **GKE Start** rebuilds it from scratch. AKS can be stopped and restarted without data loss (persistent volumes are retained). Managed disks are the only cost when both clusters are down.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
