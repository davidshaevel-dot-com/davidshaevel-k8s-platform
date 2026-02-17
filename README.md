# Kubernetes Developer Platform

A multi-cloud Kubernetes developer platform with zero-trust access, cost-optimized lifecycle automation, and programmatic environment registration. Manages AKS and GKE clusters through Portainer Business Edition with Teleport-secured access — no direct public endpoints exposed.

Built following the [Build Your First Kubernetes Developer Platform](https://rawkode.academy/learning-paths/build-your-first-kubernetes-developer-platform) learning path from Rawkode Academy.

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
    |       |       Web UI:   https://teleport.<your-domain>.com
    |       |       App Proxy: routes to Portainer (ClusterIP)
    |       |       K8s Proxy: authenticated kubectl access
    |       |
    |       +-- Teleport Auth (ClusterIP)
    |       +-- Teleport Agent (app + kube registration)
    |
    +-- portainer namespace
            |
            Portainer BE (ClusterIP, port 9443 HTTPS)
                (no public IP, accessed via Teleport)
                Manages: AKS (local) + GKE (remote agent)

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

## Tech Stack

| Layer | Technology |
|-------|------------|
| Cloud | Azure (AKS), Google Cloud (GKE) |
| Container Orchestration | Kubernetes (multi-cluster, Azure CNI Overlay + Cilium) |
| Platform Management | Portainer Business Edition |
| Secure Access | Teleport Community Edition (self-hosted) |
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
| **GKE Start** | Create GKE cluster, install Portainer Agent, register in Portainer via API, install Teleport Agent. Auto-deletes cluster on failure to prevent costs |
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

7. **Add a GKE cluster** (optional, multi-cluster setup):

   ```bash
   ./scripts/gke/start.sh
   ```

## Scripts

All scripts source `scripts/config.sh` for shared configuration. When running locally, output is logged to `/tmp/$USER-k8s-platform/`. In CI (GitHub Actions), file logging is skipped.

### AKS Cluster (`scripts/aks/`)

| Script | Description |
|--------|-------------|
| `aks/create.sh` | Create the AKS cluster (Azure CNI Overlay + Cilium) |
| `aks/delete.sh` | Delete the AKS cluster |
| `aks/start.sh` | Start a stopped cluster |
| `aks/stop.sh` | Stop the cluster (save costs) |
| `aks/status.sh` | Show cluster status |
| `aks/credentials.sh` | Fetch kubeconfig credentials |

### GKE Cluster (`scripts/gke/`)

| Script | Description |
|--------|-------------|
| `gke/create.sh` | Create the GKE cluster (enables API if needed) |
| `gke/delete.sh` | Delete the GKE cluster (interactive, requires confirmation) |
| `gke/start.sh` | Orchestrated rebuild (create + agents + registration) |
| `gke/stop.sh` | Delete the GKE cluster (non-interactive, for scripted use) |
| `gke/status.sh` | Show cluster status |
| `gke/credentials.sh` | Fetch kubeconfig credentials |

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
| `TELEPORT_DOMAIN` | Teleport domain (defaults to teleport.davidshaevel.com) |

## Project Management

- **Issue Tracking:** [Linear (Team Tacocat)](https://linear.app/davidshaevel-dot-com/project/kubernetes-developer-platform-e5de2eef1556)
- **Repository:** [GitHub](https://github.com/davidshaevel-dot-com/davidshaevel-k8s-platform)

## Cost Estimate

| Component | Running | Stopped |
|-----------|---------|---------|
| AKS control plane | Free | Free |
| AKS Standard_B2ms node (1x) | ~$60 | $0 |
| AKS Load Balancer (Teleport) | ~$18 | $0 |
| AKS Managed Disks (PVs) | ~$1-5 | ~$1-5 |
| GKE Standard (e2-medium, 1 node) | ~$25 | $0 (deleted) |
| **Total** | **~$105-110** | **~$1-5** |

GKE has no stop/start — the **GKE Stop** workflow deletes the cluster entirely ($0), and **GKE Start** rebuilds it from scratch. AKS can be stopped and restarted without data loss (persistent volumes are retained). Managed disks are the only cost when both clusters are down.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
