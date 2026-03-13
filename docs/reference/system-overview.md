# Kubernetes Developer Platform — System Overview

A structured reference for explaining the platform's architecture, operations, and incident response. Organized by lifecycle: build → run → fix.

---

## 1. Platform Overview

A multi-cloud Kubernetes developer platform managing AKS and GKE clusters through a single Argo CD instance with Teleport-secured zero-trust access. No services have direct public endpoints — all traffic flows through Teleport's identity-aware proxy.

**Why I built it:** To learn platform engineering hands-on — not just provisioning infrastructure, but operating a platform: deploying applications via GitOps, monitoring with Prometheus and Hubble, and troubleshooting real incidents across two cloud providers.

**Key numbers:**

| | |
|---|---|
| Clusters | 2 (AKS + GKE) |
| Namespaces on AKS | 6 (teleport, portainer, argocd, monitoring, website, kube-system) |
| Automation scripts | 30+ (cluster lifecycle, agents, policies, monitoring, secrets) |
| GitHub Actions workflows | 4 (AKS start/stop, GKE start/stop) |
| Public endpoints | 0 — everything through Teleport |
| Cost (running) | ~$185/month |
| Cost (stopped) | ~$10/month (storage only) |

**Tech stack:**

| Layer | Technology |
|-------|------------|
| Cloud | Azure (AKS), Google Cloud (GKE) |
| Networking | Azure CNI Overlay + Cilium (AKS), Dataplane V2 (GKE) |
| Container Registry | Azure Container Registry (ACR) |
| Secure Access | Teleport Community Edition (zero-trust, self-hosted) |
| GitOps | Argo CD (single control plane, multi-cluster) |
| Monitoring | kube-prometheus-stack (Prometheus + Grafana) |
| Network Observability | Hubble — ACNS (AKS), Dataplane V2 (GKE) |
| CI/CD | GitHub Actions (workflow_dispatch) |
| DNS/TLS | Cloudflare (API-managed) + Let's Encrypt (ACME via Teleport) |

---

## 2. Architecture & Design Decisions

```
Internet
    |
    v
Azure Load Balancer (port 443)
    |
    v
AKS Cluster (eastus) — always-on primary
    +-- teleport-cluster    Teleport Proxy + Auth + Agent (single entry point)
    +-- portainer           Portainer BE (manages AKS + GKE)
    +-- argocd              Argo CD (manages apps on both clusters)
    +-- monitoring          Prometheus + Grafana + Node Exporter
    +-- davidshaevel-website  Frontend + Backend + Database
    +-- kube-system         Cilium (ACNS) + Hubble Relay + Hubble UI

GKE Cluster (us-central1-a) — ephemeral secondary, Dataplane V2
    +-- davidshaevel-website  Frontend + Backend + Database (same manifests)
    +-- portainer           Portainer Agent (LB restricted to AKS egress IP)
    +-- teleport-cluster    Teleport Kube Agent + Website App
    +-- gke-managed-dpv2-observability  Hubble Relay (no UI on GKE Standard)
```

### Design Decisions

| Decision | Reasoning |
|----------|-----------|
| **Teleport** over ingress controller | Zero-trust model — no service has a public endpoint. Every request is authenticated and authorized before reaching any backend. Teleport provides SSO, RBAC, audit logging, and session recording in one component. |
| **Cilium** over default CNI | eBPF-based networking with identity-aware policies (CiliumNetworkPolicy) and built-in network flow observability (Hubble). On AKS, enabled via ACNS. On GKE, built into Dataplane V2. |
| **Argo CD** over Flux or Helm-only | Declarative GitOps with a web UI, multi-cluster support from a single instance, auto-sync with prune and self-heal. The UI is valuable for real-time visibility into sync status across both clusters. |
| **Single Argo CD** managing both clusters | One source of truth. Same manifests deploy to AKS and GKE. When GKE is deleted and recreated, Argo CD auto-syncs everything back. |
| **GKE as ephemeral** secondary | Cost optimization. GKE has no stop/start — the cluster is deleted entirely ($0) and rebuilt from scratch. Argo CD makes this painless. |
| **Standard NetworkPolicy on GKE** | CiliumNetworkPolicy CRDs require GKE Enterprise ($0.10/vCPU/hour). Standard Kubernetes NetworkPolicy is enforced by GKE's Cilium dataplane at no extra cost. |
| **kube-prometheus-stack** over Azure Monitor | Portable and open-source. Same monitoring stack works on any cloud. Includes Grafana with 20+ built-in dashboards. |
| **Separate repos** for app code and manifests | Standard GitOps pattern. Application code (davidshaevel-website) and deployment config (davidshaevel-k8s-platform) have independent release control. |

### Not in Scope (and Why)

- **No alerting** — Alertmanager disabled. Platform has monitoring but not notification. In production, I'd add Argo CD notifications + Prometheus alerting rules as the first line of detection.
- **No log aggregation** — kubectl logs only. Would add Grafana Loki to stay in the Grafana ecosystem.
- **No shared database** — Each cluster has its own PostgreSQL. No cross-cloud data replication.
- **No global load balancer** — No Cloudflare weighted DNS in front of both clusters. The architecture supports it (see Section 6).

---

## 3. Deployment & GitOps

### Two-Repo Model

| Repo | Contains | Trigger |
|------|----------|---------|
| **davidshaevel-website** | Application source (Next.js, NestJS, Dockerfiles) | Code push → GitHub Actions builds Docker images → ACR |
| **davidshaevel-k8s-platform** | Kubernetes manifests, Argo CD Applications, scripts | Manifest change → Argo CD auto-syncs to both clusters |

### Deployment Flow

```
1. Developer pushes code to davidshaevel-website
2. GitHub Actions builds Docker images → ACR (tagged with git short SHA)
3. Developer updates image tag in k8s-platform manifests (manual step)
4. Commit and push to main
5. Argo CD auto-syncs → deployed to AKS and GKE within ~3 minutes
```

**Why the manual image tag step:** Argo CD watches Git manifests, not container registries. This gives explicit control over what's deployed and when. Git history shows exactly which image was deployed and by whom. You can roll back the deployment (revert the manifest) without rolling back code. This matches how most production GitOps workflows operate.

### Multi-Cluster Sync

Both Argo CD Applications point to the same manifests directory. The only per-cluster difference is infrastructure config:
- **AKS:** Uses managed identity for ACR image pulls (zero credential management)
- **GKE:** Uses a dedicated service principal with an image pull secret (patched onto the default service account)

### GKE Ephemeral Rebuild

GKE has no stop/start. The GKE Stop workflow deletes the cluster entirely. The GKE Start workflow recreates it and runs 8 steps: create cluster → install Portainer agent → install Teleport agent → set up ACR pull secret → register in Argo CD → apply network policies → register website in Teleport → verify. Argo CD auto-syncs the website once the cluster is registered.

---

## 4. Monitoring & Observability

Three layers, each with a distinct purpose:

### Layer 1 — Metrics (Prometheus + Grafana)

Resource metrics with 7-day retention. Grafana accessed via Teleport (no public endpoint).

**Key dashboards:**
- **Kubernetes / Compute Resources / Namespace (Pods)** — first stop for checking application health (CPU, memory per pod)
- **Cilium Agent Metrics** — forwarded/dropped packets, policy enforcement status, endpoint state
- **Node Exporter / Nodes** — node-level CPU, memory, disk (capacity planning)

### Layer 2 — Network Flows (Hubble)

Per-packet visibility at the eBPF datapath layer. Every flow captured with source/destination pod identity, port, protocol, and policy verdict (FORWARDED or DROPPED).

**Debugging workflow:** `hubble observe --namespace <ns> --verdict DROPPED` immediately shows which packets are being denied and why — the exact source and destination pods, TCP flags, and policy verdict.

**Cross-cloud access:**

| | AKS (ACNS) | GKE (Dataplane V2) |
|---|---|---|
| CLI access | Local `hubble` CLI via port-forward | `kubectl exec` into relay pod |
| Authentication | mTLS certs from K8s secret | None — exec directly |
| Hubble UI | Yes (localhost:12000) | No — use GCP Console instead |
| Network policies | CiliumNetworkPolicy (identity-aware) | Standard Kubernetes NetworkPolicy |

### Layer 3 — Application Status (Argo CD)

Argo CD monitors sync status, health status, and drift for every application. In practice, Argo CD transitioning to **Degraded** would be the first signal that something is wrong — this is where an alert would fire in production.

### The Gap

This platform has monitoring without alerting. In production, I'd add:
- Argo CD notifications (Slack/webhook when an app goes Degraded or OutOfSync)
- Prometheus alerting rules (`KubePodNotReady`, `KubePodCrashLooping`) routed through Alertmanager to PagerDuty/Slack
- Dashboards are for triage, not discovery

---

## 5. Incident Response

Three incidents — one real, two simulated — each demonstrating a different triage pattern.

### Real: Cilium Egress Deny (16-Hour Teleport Outage)

**What happened:** Added CiliumNetworkPolicy egress rules for DNS, which triggered Cilium's implicit default-deny on all other egress traffic. Teleport proxy and agent couldn't reach external services (Let's Encrypt, Azure metadata). Teleport was down for 16 hours before diagnosis.

**Root cause:** CiliumNetworkPolicy egress rules trigger implicit deny on ALL other egress — not just the ports you specify. The DNS allow rule inadvertently blocked everything else.

**Fix:** Removed both `allow-dns` egress policies. The platform's design is ingress-only enforcement — no egress restrictions.

**Key lesson:** Never use CiliumNetworkPolicy egress rules unless you explicitly want to deny all other egress. This is a Cilium-specific behavior that's not obvious from the documentation.

### Simulated: Bad Image Tag (Application-Level)

**Scenario:** Pushed a nonexistent image tag (`frontend:does-not-exist`) via GitOps.

**What happened:**
- Kubernetes created a new pod with the bad image → `ErrImagePull` → `ImagePullBackOff`
- The existing frontend pod kept running (rolling update strategy preserves availability)
- Argo CD transitioned to `Progressing` → `Degraded` + `Synced`
- Grafana showed no significant changes (the running pod was unaffected)

**Triage flow:**
1. Argo CD shows Degraded (this is where the alert fires)
2. `kubectl get pods` → new pod in ImagePullBackOff, old pod still Running
3. `kubectl describe pod` → events show image pull failure with exact tag
4. `az acr repository show-tags` → verify valid tags
5. Fix image tag in Git, push → Argo CD auto-syncs → recovery

**Key lesson:** Rolling update strategy protects availability. The incident is visible in Argo CD and pod status, not Grafana. In a GitOps workflow, the fix goes through Git — not `kubectl edit`.

### Simulated: Network Policy Blocking Backend→Database (Network-Level)

**Scenario:** Blocked backend→database traffic on AKS using CiliumNetworkPolicy.

**What happened:**
- Backend couldn't reach PostgreSQL on port 5432
- Health checks failed → pod restarts → CrashLoopBackOff
- Hubble showed DROPPED verdict on port 5432 flows

**Key discoveries during simulation:**
- **Policies are additive:** CiliumNetworkPolicies are OR'd. If any policy allows traffic, it flows. Had to delete `allow-intra-namespace` before the blocking policy worked.
- **Persistent connections:** TypeORM maintains a connection pool. Existing database connections survived the policy change. Had to `kubectl rollout restart` to force new connections.
- **CrashLoopBackOff backoff timer:** After many restarts, Kubernetes uses exponential backoff (up to 5 minutes). `kubectl rollout restart` creates a fresh pod without the backoff penalty.
- **Prometheus scrape interval:** 30-second default means brief crash-loop cycles may not appear in Grafana. Hubble CLI and `kubectl get pods -w` are more reliable signals.

**Triage flow:**
1. Pod restarts visible in `kubectl get pods -w`
2. `kubectl logs` → connection refused to database
3. `hubble observe --verdict DROPPED` → DROPPED on port 5432
4. `kubectl get ciliumnetworkpolicies` → find the bad policy
5. Delete blocking policy, restore `allow-intra-namespace`, rollout restart
6. Verify: pods Running, Hubble shows FORWARDED

### Generalizable Triage Framework

```
1. Alert received (Argo CD Degraded, pod restarts, Hubble drops)
2. Assess scope and impact (which pods, is the service still up?)
3. Check pod status (kubectl get pods, describe pod)
4. Check events and logs (kubectl events, kubectl logs)
5. Check network flows (hubble observe --verdict DROPPED)
6. Identify root cause (bad image, network policy, resource limit)
7. Fix (GitOps commit, delete policy, scale up)
8. Verify recovery (pods Running, Hubble FORWARDED, Argo CD Healthy)
```

---

## 6. Multi-Cloud Operations

### Why Multi-Cloud

The multi-cloud setup demonstrates three operational realities:

1. **Operational consistency:** Same manifests deploy to both AKS and GKE via Argo CD, but infrastructure differs — AKS uses managed identity for ACR, GKE uses a service principal with an image pull secret.
2. **Cross-cloud troubleshooting:** GKE doesn't expose CiliumNetworkPolicy CRDs (requires GKE Enterprise), so network policies use standard Kubernetes NetworkPolicy. Hubble access differs: AKS needs mTLS certs, GKE uses `kubectl exec`. Same concepts, different implementations.
3. **Single control plane:** One Argo CD manages both clusters. When GKE is torn down and recreated, Argo CD auto-syncs everything back.

### Cross-Cloud Comparison

| | AKS | GKE |
|---|---|---|
| **Networking** | Azure CNI Overlay + Cilium (ACNS) | Dataplane V2 (Cilium-based) |
| **Network policies** | CiliumNetworkPolicy (identity-aware) | Standard Kubernetes NetworkPolicy |
| **Hubble access** | Local CLI with mTLS certs + port-forward | `kubectl exec` into relay pod |
| **Hubble UI** | Yes (Hubble UI pod in kube-system) | No (use GCP Console traffic flows) |
| **Image pull** | Managed identity (AcrPull role) | Service principal + image pull secret |
| **Cluster lifecycle** | Stop/start (PVCs persist) | Delete/recreate (fully ephemeral) |
| **Cost** | ~$130/month | ~$49/month (or $0 when deleted) |

### Deployment Patterns Enabled

With Cloudflare weighted DNS in front of both clusters, the platform enables:

| Pattern | How |
|---------|-----|
| **Blue/Green** | 100% to AKS (v1), deploy v2 to GKE, test via Teleport, flip DNS |
| **Canary** | 95% to AKS, 5% to GKE with new version, shift gradually |
| **Active/Active** | Both clusters run same version, Cloudflare load-balances |

The building blocks — multi-cluster GitOps, per-cluster network policies, centralized monitoring — are already in place. Adding these patterns is a configuration change, not a redesign.

---

## 7. Tradeoffs & Future Work

### Current Tradeoffs

| Tradeoff | Why It's Acceptable |
|----------|---------------------|
| No alerting | Dev/learning platform — would add Alertmanager + Argo CD notifications for production |
| No log aggregation | kubectl logs sufficient for single-node clusters — would add Loki for multi-node |
| Manual image tag promotion | Explicit control, full audit trail — acceptable for low deployment frequency |
| Single-node clusters | No HA, but keeps costs at ~$185/month. Production would use multi-node with PodDisruptionBudgets |
| No shared state between clusters | Each GKE rebuild gets a fresh database. Acceptable — the app is stateless-friendly |

### What I'd Add Next

1. **Alerting** — Alertmanager + Argo CD notifications → Slack/PagerDuty. First priority: dashboards are for triage, not discovery.
2. **CI-driven image promotion** — Build pipeline opens a PR to bump the manifest image tag. No additional controllers needed.
3. **Log aggregation** — Grafana Loki. Stays in the Grafana ecosystem, lightweight, designed for Kubernetes.
4. **Crossplane** — Declarative cloud infrastructure managed through Kubernetes CRDs.
5. **External Secrets Operator** — Centralized secrets management integrated with cloud secret stores.

### Likely Follow-Up Questions

**Why Teleport over an ingress controller?**
Teleport provides authentication, authorization, audit logging, and session recording as a single component. An ingress controller handles routing but not identity. With Teleport, every request is authenticated before it reaches any service — true zero-trust.

**Why Cilium over the default CNI?**
eBPF-based networking eliminates iptables overhead. CiliumNetworkPolicy provides identity-aware policies (not just IP-based). Hubble gives network flow observability at the kernel level. On AKS, it's enabled via ACNS at no extra cost. On GKE, it's built into Dataplane V2.

**Why Argo CD over Flux?**
Both are solid GitOps tools. Argo CD's web UI provides real-time visibility into sync status across both clusters, which is valuable for demos and operational awareness. Multi-cluster management from a single instance is well-supported.

**How would this scale to 5,000 hosts?**
The architecture scales horizontally: add node pools (not clusters) for compute, shard Argo CD with multiple application controllers, add Prometheus federation or Thanos for cross-cluster metrics, and move from single-node to multi-node with PodDisruptionBudgets. Teleport scales via proxy peering. The design patterns (GitOps, network policies, centralized monitoring) remain the same.
