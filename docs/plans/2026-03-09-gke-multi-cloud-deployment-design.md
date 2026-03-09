# GKE Multi-Cloud Deployment Design

**Goal:** Deploy davidshaevel-website to GKE via the same Argo CD instance on AKS, demonstrating multi-cluster management and cross-cloud operational consistency.

**Interview angles:**
- Argo CD multi-cluster management from a single control plane
- Troubleshooting cross-cloud differences (image pull, networking, access)

---

## Architecture

Single Argo CD on AKS manages both clusters. AKS is the always-on primary; GKE is an ephemeral secondary. When GKE is down, the Argo CD Application shows "Unknown" — when it comes back up, Argo CD auto-syncs.

```
AKS Cluster (always-on)
    +-- argocd namespace
    |       Argo CD
    |         +-- davidshaevel-website-aks  -> AKS (local)
    |         +-- davidshaevel-website-gke  -> GKE (remote)
    |
    +-- davidshaevel-website namespace
            Frontend, Backend, Database (same as today)

GKE Cluster (ephemeral)
    +-- davidshaevel-website namespace
    |       Frontend, Backend, Database
    |       (same manifests, pulls from ACR via image pull secret)
    |
    +-- teleport-cluster namespace
            Teleport Kube Agent (existing)
            + Website app registration (new)
```

## Image Pull Strategy

GKE pulls from ACR using an image pull secret. The secret is attached to the `default` service account in the `davidshaevel-website` namespace, keeping the application manifests identical across both clusters.

- Create an ACR service principal or token with `AcrPull` permission
- Create a `docker-registry` Secret on GKE in the `davidshaevel-website` namespace
- Patch the `default` service account to use the pull secret

AKS continues using managed identity (zero credential management). This is a deliberate cross-cloud difference worth discussing in the interview.

## Access

Both websites are accessed via Teleport app proxy:

- AKS: `https://davidshaevel-website-aks.teleport.davidshaevel.com`
- GKE: `https://davidshaevel-website-gke.teleport.davidshaevel.com`

The existing Teleport app `davidshaevel-website` will be renamed to `davidshaevel-website-aks`.

## Network Policies on GKE

GKE uses Dataplane V2 (Cilium-based internally), but does **not** expose `CiliumNetworkPolicy` CRDs (requires GKE Enterprise). Standard Kubernetes `NetworkPolicy` is used instead — GKE Dataplane V2 enforces these via its Cilium dataplane.

Policies for the website namespace on GKE:

- Default deny ingress (NetworkPolicy)
- Allow intra-namespace (NetworkPolicy)
- Allow from teleport-cluster to frontend on port 3000 (NetworkPolicy with `namespaceSelector`)

No Prometheus scrape policy on GKE (monitoring stack only runs on AKS).

## Data Flow

```
Developer pushes to main
    -> Argo CD detects change
    -> Syncs davidshaevel-website-aks (AKS, local)
    -> Syncs davidshaevel-website-gke (GKE, remote - if cluster is up)
```

Both deployments use the same manifests from `manifests/davidshaevel-website/`. The only per-cluster difference is infrastructure config (image pull secret and service account patch on GKE).

## Components

### New
- `argocd/applications/davidshaevel-website-gke.yaml` — Argo CD Application targeting GKE
- `scripts/website/gke-teleport-register.sh` — Register GKE website as Teleport app
- `manifests/cilium/gke-namespace-isolation.yaml` — Network policies for GKE website namespace
- GKE image pull secret + service account patch (scripted, credential not in Git)

### Modify
- `argocd/applications/davidshaevel-website.yaml` -> rename to `davidshaevel-website-aks.yaml`, update `metadata.name`
- `argocd/projects/platform.yaml` — add GKE cluster to destinations
- `scripts/website/teleport-register.sh` — rename app from `davidshaevel-website` to `davidshaevel-website-aks`

### Argo CD Cluster Registration
- Register GKE as a remote cluster in Argo CD (via `argocd cluster add` CLI or cluster Secret manifest)

## Future Extensibility

Adding a Cloudflare load balancer with `dev.davidshaevel.com` pointing to both clusters would be additive — add LoadBalancer/Ingress manifests and Cloudflare DNS records. No redesign needed.
