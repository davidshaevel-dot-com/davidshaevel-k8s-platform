# GKE Cluster + Portainer Agent — Design

**Created:** February 9, 2026
**Context:** Day 1 Morning of Bumble Sr. SRE prep week. Add a GKE cluster as a second environment managed through the existing AKS-hosted Portainer BE.

---

## Architecture

```
Internet
    |
    v
AKS Cluster (portainer-rg, eastus)              GKE Cluster (dev-david, us-central1)
    |                                                 |
    +-- Portainer BE (ClusterIP)--outbound-->--+      +-- Portainer Agent (LB :9001)
    |       (server connects to agent)         |      |       (firewall: AKS egress IP only)
    |                                          |      |
    +-- Teleport Proxy (LB :443)               |      +-- Teleport Kube Agent
    |       teleport.davidshaevel.com          |      |       (registers as "portainer-gke")
    |                                          |      |
    +-- Teleport Agent (app + kube)            |      +-- (future: app, monitoring namespaces)
                                               |
                                    GCP Firewall Rule:
                                    allow TCP:9001 from <AKS-egress-IP>/32
```

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| GCP project | `dev-david-024680` | Personal dev project, already default |
| Agent type | Standard Agent | Simplest setup; GKE agent has LoadBalancer, AKS Portainer server connects outbound |
| Agent security | GCP firewall rule | Port 9001 restricted to AKS cluster egress IP only |
| Teleport for GKE | Yes | Registers as `portainer-gke` for kubectl access via Teleport |
| GKE cluster | Single-node Standard, `e2-medium`, `us-central1-a` | Cost-effective (~$2-3/day), deletable for $0 |

### Connection Flow

1. Portainer Agent on GKE exposes port 9001 via LoadBalancer
2. GCP firewall rule restricts port 9001 to the AKS cluster's outbound IP
3. Portainer BE on AKS connects outbound to `<GKE-agent-IP>:9001`
4. GKE appears as a second environment in the Portainer dashboard
5. Teleport kube agent on GKE registers the cluster as `portainer-gke`
6. `tsh kube ls` shows both `portainer-aks` and `portainer-gke`

---

## Scripts Directory Reorganization

Moving from flat `scripts/` to component-based subdirectories.

### Existing Scripts — Moves and Renames

| Current | New | Renamed? |
|---------|-----|----------|
| `scripts/config.sh` | `scripts/config.sh` | No |
| `scripts/aks-create.sh` | `scripts/aks/create.sh` | No |
| `scripts/aks-delete.sh` | `scripts/aks/delete.sh` | No |
| `scripts/aks-start.sh` | `scripts/aks/start.sh` | No |
| `scripts/aks-stop.sh` | `scripts/aks/stop.sh` | No |
| `scripts/aks-status.sh` | `scripts/aks/status.sh` | No |
| `scripts/aks-credentials.sh` | `scripts/aks/credentials.sh` | No |
| `scripts/portainer-install.sh` | `scripts/portainer/aks-install.sh` | **Yes** |
| `scripts/portainer-uninstall.sh` | `scripts/portainer/aks-uninstall.sh` | **Yes** |
| `scripts/portainer-status.sh` | `scripts/portainer/aks-status.sh` | **Yes** |
| `scripts/teleport-install.sh` | `scripts/teleport/install.sh` | No |
| `scripts/teleport-uninstall.sh` | `scripts/teleport/uninstall.sh` | No |
| `scripts/teleport-status.sh` | `scripts/teleport/status.sh` | No |
| `scripts/teleport-dns.sh` | `scripts/teleport/dns.sh` | No |
| `scripts/teleport-dns-delete.sh` | `scripts/teleport/dns-delete.sh` | No |
| `scripts/teleport-agent-install.sh` | `scripts/teleport/aks-agent-install.sh` | **Yes** |
| `scripts/teleport-agent-uninstall.sh` | `scripts/teleport/aks-agent-uninstall.sh` | **Yes** |

### New Scripts

| Script | Purpose |
|--------|---------|
| `scripts/gke/create.sh` | Enable GKE API, create cluster, get credentials |
| `scripts/gke/delete.sh` | Delete GKE cluster |
| `scripts/gke/start.sh` | Orchestrated rebuild: cluster + agent + firewall + Teleport |
| `scripts/gke/stop.sh` | Alias for delete (GKE has no stop/start like AKS) |
| `scripts/gke/status.sh` | Show GKE cluster status |
| `scripts/gke/credentials.sh` | Fetch kubeconfig for GKE |
| `scripts/gke/firewall.sh` | Create/update GCP firewall rule (AKS egress IP -> port 9001) |
| `scripts/portainer/gke-agent-install.sh` | Install Portainer Agent via Helm on GKE |
| `scripts/portainer/gke-agent-uninstall.sh` | Remove Portainer Agent from GKE |
| `scripts/teleport/gke-agent-install.sh` | Deploy Teleport kube agent on GKE |
| `scripts/teleport/gke-agent-uninstall.sh` | Remove Teleport agent from GKE |

### Final Directory Structure

```
scripts/
├── config.sh
├── aks/
│   ├── create.sh
│   ├── credentials.sh
│   ├── delete.sh
│   ├── start.sh
│   ├── status.sh
│   └── stop.sh
├── gke/
│   ├── create.sh
│   ├── credentials.sh
│   ├── delete.sh
│   ├── firewall.sh
│   ├── start.sh
│   ├── status.sh
│   └── stop.sh
├── portainer/
│   ├── aks-install.sh
│   ├── aks-status.sh
│   ├── aks-uninstall.sh
│   ├── gke-agent-install.sh
│   └── gke-agent-uninstall.sh
└── teleport/
    ├── aks-agent-install.sh
    ├── aks-agent-uninstall.sh
    ├── dns-delete.sh
    ├── dns.sh
    ├── gke-agent-install.sh
    ├── gke-agent-uninstall.sh
    ├── install.sh
    ├── status.sh
    └── uninstall.sh
```

---

## Config Changes

### `config.sh` Additions

```bash
# GKE configuration
GCP_PROJECT="${GCP_PROJECT:?Set GCP_PROJECT in .envrc or environment}"
GKE_CLUSTER_NAME="portainer-gke"
GKE_ZONE="us-central1-a"
GKE_MACHINE_TYPE="e2-medium"
GKE_NODE_COUNT=1
```

### `.envrc` Additions

```bash
export GCP_PROJECT="dev-david-024680"
```

---

## Implementation Sequence

1. Create Linear issue
2. Create git worktree
3. Reorganize `scripts/` (move + rename existing scripts)
4. Update `config.sh` with GCP variables
5. Update `.envrc.example` with `GCP_PROJECT`
6. Write new GKE scripts
7. Write Portainer Agent scripts
8. Write Teleport GKE agent scripts
9. Execute: create cluster, install agent, configure firewall, register with Teleport
10. Verify: GKE visible in Portainer UI, `portainer-gke` accessible via Teleport
11. Update docs (CLAUDE.md, README.md, CLAUDE.local.md)
12. PR + code review

---

## Cost

| Component | Daily | Monthly (if kept) |
|-----------|-------|--------------------|
| GKE `e2-medium` node (1x) | ~$1.50 | ~$45 |
| GKE control plane (Standard) | Free | Free |
| GCP Load Balancer (agent) | ~$0.60 | ~$18 |
| **GKE subtotal** | **~$2-3/day** | **~$60-65** |
| AKS (existing) | ~$1.60 | ~$50-55 |
| **Total both clusters** | **~$4-5/day** | **~$110-120** |

Delete GKE cluster when not in use for $0 idle cost.
