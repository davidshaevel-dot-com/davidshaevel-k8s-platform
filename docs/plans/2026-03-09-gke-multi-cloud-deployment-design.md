# GKE Multi-Cloud Deployment Design

**Goal:** Deploy davidshaevel-website to GKE via the same Argo CD instance on AKS, demonstrating multi-cluster management and cross-cloud operational consistency.

**Interview angles:**
- Argo CD multi-cluster management from a single control plane
- Troubleshooting cross-cloud differences (image pull, networking, access)
- Multi-cloud deployment patterns (blue/green, canary, active/active)
- Why build a multi-cloud platform in the first place

## Why Multi-Cloud?

This platform exists to demonstrate the operational skills an SRE needs when managing workloads across cloud providers — not because the application requires it, but because real platform teams deal with this complexity daily.

**Interview talking point — why multi-cloud:** "The multi-cloud setup demonstrates three things I'd encounter on a real platform team. First, **operational consistency**: the same manifests deploy to both AKS and GKE via Argo CD, but the infrastructure differs — AKS uses managed identity for ACR, GKE uses a service principal with an image pull secret. Second, **cross-cloud troubleshooting**: GKE doesn't expose CiliumNetworkPolicy CRDs like AKS does, so I had to adapt the network policies to standard Kubernetes NetworkPolicy. CiliumNetworkPolicy uses Cilium endpoint identities (`k8s:io.kubernetes.pod.namespace`), while standard NetworkPolicy uses Kubernetes label selectors (`namespaceSelector`). Third, **single control plane management**: one Argo CD instance on AKS manages both clusters, and when GKE is torn down and recreated, Argo CD auto-syncs everything back — the cluster is fully ephemeral."

**Interview talking point — cost awareness:** "I designed the platform to be cost-conscious. AKS is the always-on primary (~$130/month), GKE is ephemeral and gets deleted when not in use ($0 when stopped). The whole platform can be stopped for ~$10-15/month with only storage persisting. This mirrors how you'd manage non-production environments in a real organization — spin up when needed, tear down when done."

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

### Deployment Patterns Enabled by Multi-Cloud

Currently, both Argo CD Applications point to the same manifests on `main`, so both clusters always run the same version. To deploy different versions, you could use separate manifest directories, Kustomize overlays, or different `targetRevision` branches per Application.

With a Cloudflare load balancer in front of both clusters, the platform enables:

| Pattern | How It Would Work |
|---------|-------------------|
| **Blue/Green** | 100% traffic to AKS (v1). Deploy v2 to GKE, test via Teleport. Flip Cloudflare to send 100% to GKE. Roll back by flipping again. |
| **Canary** | Cloudflare weighted routing: 95% to AKS (v1), 5% to GKE (v2). Gradually shift weight as confidence grows. Monitor error rates in Grafana. |
| **Active/Active** | Both clusters run the same version. Cloudflare load-balances for geographic redundancy or failover. |

**Interview talking point — deployment patterns:** "The platform is architected so that adding canary or blue/green deployments is a configuration change, not a redesign. Both clusters already run the same app via Argo CD. To do a canary, I'd point the GKE Application at a different branch or Kustomize overlay with the new image tag, add Cloudflare weighted DNS in front of both, and shift traffic gradually. Grafana and Hubble give me the observability to monitor error rates and traffic patterns during the rollout. The building blocks — multi-cluster GitOps, per-cluster network policies, centralized monitoring — are already in place."
