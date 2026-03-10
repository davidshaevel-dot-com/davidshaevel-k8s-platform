# Monitoring and Observability Reference

## Stack Overview

| Component | Purpose | Access |
|-----------|---------|--------|
| Prometheus | Metrics collection (7d retention, 5Gi PVC) | Internal (port 9090) |
| Grafana | Visualization and dashboards | https://grafana.teleport.davidshaevel.com |
| Node Exporter | Node-level CPU, memory, disk, network metrics | Scraped by Prometheus |
| Kube State Metrics | Kubernetes object metrics (pods, deployments, etc.) | Scraped by Prometheus |
| Cilium Agent | eBPF datapath metrics (drops, forwards, endpoints, BPF maps) | Scraped by PodMonitor on port 9962 |
| Hubble | Live network flow observation (CLI and UI) | Port-forward or CLI |

## Grafana Dashboards

### Built-in (kube-prometheus-stack)

- **Kubernetes / Compute Resources / Cluster** — cluster-wide CPU, memory, network
- **Kubernetes / Compute Resources / Namespace (Pods)** — per-namespace resource usage
- **Kubernetes / Compute Resources / Pod** — individual pod metrics
- **Node Exporter / Nodes** — node-level CPU, memory, disk, network
- **Kubernetes / Networking / Namespace (Pods)** — network traffic per namespace

### Cilium Agent Metrics (imported, dashboard ID 16611)

The Cilium Agent Metrics dashboard monitors the eBPF datapath — how Cilium processes and enforces network traffic at the kernel level.

**Most important panels:**

#### Forwarded & Dropped Packets (Cilium network information section)

- **Forwarded Packets / Forwarded Traffic** — all traffic flowing through the eBPF datapath, split by ingress/egress. Baseline indicator that traffic is flowing normally.
- **Dropped Ingress Packets / Dropped Egress Packets** — the most critical operational graphs. Spikes here mean Cilium is denying traffic, broken down by `reason` (policy deny, invalid packet, etc.). During the egress deny incident (Feb 17), these graphs would have shown the Teleport egress drops.
- **Dropped Ingress/Egress Traffic** — same signal in bytes instead of packet count.

#### Policy (Policy section)

- **Endpoints policy enforcement status** — how many endpoints have policies enforced vs. not. Confirms network policies are actually being applied.
- **Policies Per Node / Policy Revision** — tracks policy count and revision number. Useful for confirming policy changes have propagated to the datapath.
- **Cilium drops Ingress** — drops specifically caused by policy, with reason labels.

#### Endpoint State (Endpoints section)

- **Cilium endpoint state** — shows endpoints in `ready`, `waiting-for-identity`, `regenerating`, etc. If endpoints are stuck in non-ready states, something is wrong with Cilium identity allocation.
- **Endpoint regeneration time (p90/p99)** — how long it takes to program new endpoints. High values indicate datapath programming bottlenecks.

#### Health & Resources (Generic section)

- **Errors & Warnings** — Cilium agent errors. Should be zero in normal operation.
- **CPU Usage / Resident Memory** — Cilium agent resource consumption. Important for capacity planning on larger clusters.
- **BPF map pressure** — how full the eBPF maps are. If any approach 100%, new connections will be dropped.

#### Kubernetes Integration

- **apiserver latency / calls** — how Cilium interacts with the K8s API server. High latency means slow policy updates.
- **K8s Events** (Pod, Service, NetworkPolicy) — event processing rates. Useful for diagnosing slow reconciliation.

### Cilium Policy Verdicts (imported, dashboard ID 18015)

Shows ingress/egress policy verdicts by match type and action. Requires `hubble_policy_verdicts_total` metric (needs Hubble metrics export — not currently enabled on Azure ACNS).

## Cilium Metrics Collection

Cilium agent exposes Prometheus metrics on port 9962 (hostPort). A PodMonitor (`manifests/monitoring/cilium-podmonitor.yaml`) scrapes these into Prometheus with a `metricRelabelings` rule that adds `k8s_app=cilium` (required by the Grafana dashboards).

Key metric families:
- `cilium_forward_count_total` / `cilium_forward_bytes_total` — forwarded traffic
- `cilium_drop_count_total` / `cilium_drop_bytes_total` — dropped traffic with reason labels
- `cilium_endpoint` / `cilium_endpoint_state` — endpoint counts and states
- `cilium_policy` / `cilium_policy_endpoint_enforcement_status` — policy state
- `cilium_bpf_map_pressure` — BPF map utilization

## Hubble Network Flow Observation

Hubble provides real-time, packet-level visibility into network flows across the cluster. It operates at the eBPF datapath layer inside Cilium, capturing every connection with source/destination identity, verdict (forwarded or dropped), and TCP flags.

### Prerequisites

- Hubble relay running on AKS (enabled via ACNS: `az aks update --enable-acns`)
- `hubble` CLI v0.13.6 installed (must match ACNS relay version v1.15.0 — newer CLI versions fail with gRPC ALPN mismatch)
- Port-forward to hubble-relay active
- mTLS certs extracted from `hubble-relay-client-certs` secret

### Step-by-Step Setup

**1. Extract Hubble mTLS certificates**

ACNS configures Hubble relay with mutual TLS. Extract the client certs from Kubernetes secrets:

```bash
kubectl get secret hubble-relay-client-certs -n kube-system \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/hubble-ca.crt
kubectl get secret hubble-relay-client-certs -n kube-system \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/hubble-client.crt
kubectl get secret hubble-relay-client-certs -n kube-system \
  -o jsonpath='{.data.tls\.key}' | base64 -d > /tmp/hubble-client.key
```

**2. Start the port-forward to hubble-relay**

```bash
kubectl port-forward -n kube-system svc/hubble-relay 4245:443 &
```

**3. Observe flows**

```bash
# All recent flows in a namespace
hubble observe --namespace davidshaevel-website --last 20 \
  --tls --tls-ca-cert-files /tmp/hubble-ca.crt \
  --tls-client-cert-file /tmp/hubble-client.crt \
  --tls-client-key-file /tmp/hubble-client.key \
  --tls-server-name "*.hubble-relay.cilium.io"

# Only dropped packets (policy denies, invalid packets)
hubble observe --namespace davidshaevel-website --verdict DROPPED \
  --tls --tls-ca-cert-files /tmp/hubble-ca.crt \
  --tls-client-cert-file /tmp/hubble-client.crt \
  --tls-client-key-file /tmp/hubble-client.key \
  --tls-server-name "*.hubble-relay.cilium.io"

# Live stream (follow mode)
hubble observe --namespace davidshaevel-website --follow \
  --tls --tls-ca-cert-files /tmp/hubble-ca.crt \
  --tls-client-cert-file /tmp/hubble-client.crt \
  --tls-client-key-file /tmp/hubble-client.key \
  --tls-server-name "*.hubble-relay.cilium.io"
```

### Reading Hubble Flow Output

Each line represents a single network event:

```
Mar 10 17:57:41.492: 10.224.0.4:50202 (host) -> davidshaevel-website/frontend-5d76bcdcb7-nlm64:3000 (ID:24993) policy-verdict:L3-Only INGRESS ALLOWED (TCP Flags: SYN)
```

| Field | Meaning |
|-------|---------|
| `Mar 10 17:57:41.492` | Timestamp of the flow event |
| `10.224.0.4:50202` | Source IP and port (node IP = kubelet health check) |
| `(host)` | Source identity — `host` means the node itself |
| `->` | Direction: `->` = request, `<-` = response |
| `davidshaevel-website/frontend-...` | Destination pod (namespace/pod-name) |
| `:3000` | Destination port |
| `(ID:24993)` | Cilium security identity of the destination endpoint |
| `policy-verdict:L3-Only` | Policy decision — L3-Only means allowed by IP-based (not L7) policy |
| `INGRESS ALLOWED` | Traffic direction and verdict |
| `(TCP Flags: SYN)` | TCP flags — SYN = new connection, ACK = established, FIN = closing |

**Common flow patterns in davidshaevel-website:**

| Pattern | What It Means |
|---------|---------------|
| `(host) -> frontend:3000` | Kubelet liveness/readiness probes hitting the frontend |
| `(host) -> backend:3001` | Kubelet probes hitting the backend |
| `teleport-agent -> frontend:3000` | Teleport proxying user requests to the frontend |
| `backend -> database:5432` | Backend querying PostgreSQL — normal application traffic |
| `policy-verdict:L3-Only INGRESS ALLOWED` | Traffic allowed by CiliumNetworkPolicy (intra-namespace rule) |
| `to-endpoint FORWARDED` | Packet delivered to the destination pod |
| `to-stack FORWARDED` | Packet handed to the kernel networking stack (response path) |

**Why there's no frontend→backend flow:** The davidshaevel-website frontend is a static Next.js app — it serves HTML/JS/CSS only, with no server-side rendering or backend proxy. API calls (e.g., contact form) are initiated by the user's browser, which routes through Teleport directly to the backend. The frontend pod never makes outbound requests to the backend pod. This is confirmed by both the application code (`NEXT_PUBLIC_API_URL` is a client-side env var) and Hubble flow observation.

**Hubble UI service map for davidshaevel-website:**

```
Teleport Agent ──→ frontend:3000  (static HTML/JS/CSS)
backend ──→ database:5432         (PostgreSQL queries on startup + health checks)
(host) ──→ frontend:3000          (kubelet probes)
(host) ──→ backend:3001           (kubelet probes)
```

**Verdicts to watch for:**

| Verdict | Meaning | Action |
|---------|---------|--------|
| `FORWARDED` | Traffic allowed and delivered | Normal — healthy traffic |
| `DROPPED` | Traffic denied | Investigate — check `reason` field for policy deny vs. invalid packet |
| `POLICY DENIED` | Explicitly blocked by a CiliumNetworkPolicy | Check which policy is blocking — `kubectl get cnp -n <namespace>` |
| `ERROR` | Datapath processing error | Check Cilium agent logs |

**Key flags in `--verdict` filter:**

- `--verdict FORWARDED` — show only allowed traffic
- `--verdict DROPPED` — show only denied traffic (most useful for debugging)

### Hubble CLI Version Compatibility

The ACNS-managed Hubble relay on AKS runs an older image (`mcr.microsoft.com/oss/cilium/hubble-relay:v1.15.0`). The standalone `hubble` CLI must be version **v0.13.x** to match. Newer versions (v1.18+) fail with a gRPC ALPN handshake error due to stricter TLS enforcement in grpc-go v1.67+.

The `cilium` CLI (`cilium hubble` subcommands) does **not** include `hubble observe` — it only wraps management commands (`enable`, `disable`, `port-forward`, `ui`). The standalone `hubble` CLI is required for flow observation.

### Hubble UI

Hubble UI provides a visual service map of network flows within a namespace. Pods appear as nodes, with arrows showing traffic between them (green = forwarded, red = dropped).

**Important:** Hubble UI is per-cluster only. It connects to the local Hubble relay and only shows flows from that cluster. GKE services do not appear in the AKS Hubble UI — GKE has its own Hubble via Dataplane V2 (see [GKE Hubble Access](#gke-hubble-access-dataplane-v2) below).

**1. Start the port-forward**

```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80 &
```

**2. Open in browser**

Navigate to http://localhost:12000

**3. Explore**

- Select a namespace from the dropdown at the top
- **davidshaevel-website** — shows frontend, backend, database pods with traffic flows
- **teleport-cluster** — the most interesting view: shows the Teleport agent fanning out to all services across namespaces (Grafana, Portainer, Argo CD, davidshaevel-website), providing a live visualization of the zero-trust access architecture
- Click any arrow to see individual flow details (source, destination, port, verdict)
- Generate traffic by visiting the website or Grafana via Teleport to see flows appear in real time

## GKE Hubble Access (Dataplane V2)

GKE with Dataplane V2 runs Cilium internally and provides Hubble flow observability through the managed `gke-managed-dpv2-observability` namespace. Unlike AKS (where you need mTLS certs and a specific CLI version), GKE provides a `hubble-cli` container built into the relay pod — no local CLI install or certificate extraction needed.

### Prerequisites

- GKE cluster created with `--enable-dataplane-v2`
- Observability enabled: `--enable-dataplane-v2-flow-observability --enable-dataplane-v2-metrics` (set at creation or via `gcloud container clusters update`)

### Observing Flows

```bash
# Get GKE credentials
gcloud container clusters get-credentials k8s-developer-platform-gke \
  --zone us-central1-a --project <project-id>

# Observe all flows in a namespace
kubectl exec -it -n gke-managed-dpv2-observability \
  deployment/hubble-relay -c hubble-cli -- \
  hubble observe --namespace davidshaevel-website

# Live stream
kubectl exec -it -n gke-managed-dpv2-observability \
  deployment/hubble-relay -c hubble-cli -- \
  hubble observe --namespace davidshaevel-website --follow

# Only dropped packets
kubectl exec -it -n gke-managed-dpv2-observability \
  deployment/hubble-relay -c hubble-cli -- \
  hubble observe --namespace davidshaevel-website --verdict DROPPED
```

### GKE Flow Patterns (davidshaevel-website)

The same three traffic patterns observed on AKS appear on GKE:

```
# 1. Kubelet health probes → frontend (every ~5s)
10.4.0.1:50932 (host) -> davidshaevel-website/frontend-...:3000  policy-verdict:L3-Only INGRESS ALLOWED

# 2. Kubelet health probes → backend (every ~5s)
10.4.0.1:39730 (host) -> davidshaevel-website/backend-...:3001   policy-verdict:L3-Only INGRESS ALLOWED

# 3. Backend → database queries (every ~10s, triggered by health checks)
davidshaevel-website/backend-...:58328 -> davidshaevel-website/database-...:5432  to-endpoint FORWARDED
davidshaevel-website/backend-...:58328 <- davidshaevel-website/database-...:5432  to-endpoint FORWARDED
```

All flows show `FORWARDED` — the Kubernetes NetworkPolicies (default-deny + allow intra-namespace + allow from Teleport) are enforced by GKE's Cilium dataplane.

### Cross-Cloud Comparison: Hubble Access

| | AKS (ACNS) | GKE (Dataplane V2) |
|---|---|---|
| **Hubble relay location** | `kube-system` namespace | `gke-managed-dpv2-observability` namespace |
| **CLI access** | Local `hubble` CLI v0.13.x via port-forward | `kubectl exec` into relay pod's `hubble-cli` container |
| **Authentication** | mTLS certs from `hubble-relay-client-certs` secret | None — exec into the pod directly |
| **Setup steps** | Extract certs, port-forward, version-match CLI | Just `kubectl exec` |
| **Network policies** | CiliumNetworkPolicy (identity-aware, L3/L4) | Standard Kubernetes NetworkPolicy (L3/L4) |
| **Policy enforcement** | Cilium eBPF (managed by Azure) | Cilium eBPF (managed by Google) |
| **GCP console integration** | N/A | Traffic flows in Observability tab |

**Interview talking point — cross-cloud observability:** "Both clusters use Cilium under the hood, but the access patterns differ. On AKS, I use the standalone Hubble CLI with mTLS certificates extracted from a Kubernetes secret — ACNS runs an older relay version so the CLI needs to be version-matched. On GKE, Google bundles a `hubble-cli` container inside the relay pod, so I just `kubectl exec` in — no certs, no version matching. Same Cilium datapath, same flow visibility, different operational experience. Both show the same traffic patterns: kubelet probes, backend→database queries, and policy verdicts."

## Interview Talking Points

### Grafana / Cilium Metrics

**Monitoring story:** "I use the Cilium Agent Metrics dashboard to monitor three things: **traffic flow** (forwarded packets confirms healthy datapath), **policy drops** (any unexpected drops indicate misconfigured network policies — I caught an egress deny issue this way), and **endpoint state** (confirms all pods have valid Cilium identities and enforced policies)."

**Incident example:** "When I added CiliumNetworkPolicy egress rules for DNS, Cilium's implicit default-deny blocked all other egress traffic — Teleport was down for 16 hours. The `cilium_drop_count_total` metric with `direction=EGRESS` would have shown the spike immediately. I removed the egress rules (our design is ingress-only enforcement) and Teleport recovered. That's when I set up the Cilium PodMonitor to get these metrics into Prometheus/Grafana proactively."

**Architecture context:** "On AKS with Azure CNI Overlay, Cilium is managed by Azure (ACNS). I can't modify the Cilium DaemonSet directly, but the agent still exposes standard Prometheus metrics on port 9962. I created a PodMonitor to scrape them and imported the community Cilium Grafana dashboards — same observability you'd get with a self-managed Cilium install."

### Hubble Network Flows

**What Hubble gives you:** "Hubble is the observability layer built into Cilium. It captures every network flow at the eBPF datapath level — source pod, destination pod, port, protocol, and the policy verdict. It's like tcpdump but identity-aware: instead of just IP addresses, you see Kubernetes pod names and Cilium security identities."

**Debugging workflow:** "When I'm troubleshooting a connectivity issue, my first step is `hubble observe --namespace <ns> --verdict DROPPED`. This immediately shows me which packets are being denied and why — whether it's a missing network policy, a wrong port, or traffic coming from an unexpected namespace. I can see the exact source and destination pods, the TCP flags, and the policy verdict in real time."

**Practical example:** "In our davidshaevel-website namespace, I can watch the full request lifecycle: kubelet health probes hitting the frontend on port 3000, backend querying PostgreSQL on port 5432, and Teleport routing external requests through the allow-from-teleport CiliumNetworkPolicy. Each flow shows `policy-verdict:L3-Only INGRESS ALLOWED`, which confirms the network policies are working as designed."

**mTLS and ACNS nuance:** "One thing I learned is that Azure's ACNS configures Hubble relay with mutual TLS using internally-managed certificates. To connect from outside the cluster, I extract the client certs from the `hubble-relay-client-certs` Kubernetes secret. The Hubble CLI also needs to be version-matched to the relay — ACNS runs v1.15.0, so I use the v0.13.x CLI. Newer versions fail due to a gRPC ALPN enforcement change."

**Metrics vs. flows:** "Grafana dashboards give me the aggregate picture — packet rates, drop trends, policy enforcement status over time. Hubble gives me the per-packet detail when I need to drill down. They're complementary: I spot anomalies in Grafana, then investigate the specific flows in Hubble."

### Hubble UI — Teleport Zero-Trust Architecture

**Zero-trust access pattern:** "If I open the Hubble UI and look at the `teleport-cluster` namespace, I get a live architecture diagram of the entire platform. The Teleport agent is the single point of entry — you can see it fanning out to every service: Grafana in the monitoring namespace, Portainer in the portainer namespace, Argo CD in the argocd namespace, and the davidshaevel-website frontend. No service has a public endpoint. Every external request flows through Teleport's identity-aware proxy, and Hubble shows that in real time."

**Why this matters:** "This is the zero-trust model in action. Teleport authenticates and authorizes every request before it reaches any backend service. In the Hubble UI, you can literally see that there are no direct ingress flows from outside the cluster to any application pod — everything is mediated by the Teleport agent. If someone asks 'how do you access Grafana?' or 'how do you access Argo CD?', I can point to this view and show that it all goes through one authenticated gateway."

**Network policy enforcement:** "The Hubble UI also validates that the CiliumNetworkPolicies are working correctly. Each namespace has a default-deny-ingress policy, and the only allowed cross-namespace traffic is from the teleport-cluster namespace via `allow-from-teleport` rules. In the Hubble UI, you see green lines (forwarded) from Teleport to each service, and if you tried to access a service from any other namespace, you'd see a red line (dropped). It's a visual proof that the network segmentation is enforced at the kernel level by Cilium's eBPF datapath."

## Task 7 Summary: What We Found

### Most Useful Dashboards

1. **Kubernetes / Compute Resources / Namespace (Pods)** — first stop for checking application health (CPU, memory, restarts per namespace)
2. **Cilium Agent Metrics** — forwarded/dropped packets, policy enforcement status, endpoint state. Critical for network policy debugging.
3. **Node Exporter / Nodes** — node-level resource usage, important for capacity planning on single-node clusters
4. **Hubble UI (teleport-cluster namespace)** — live architecture diagram showing the zero-trust access pattern across all services

### What ACNS Provides

- **Cilium as the CNI** — Azure manages the Cilium DaemonSet, upgrades, and configuration. No manual Cilium install or lifecycle management.
- **CiliumNetworkPolicy CRDs** — L3/L4 identity-aware policies beyond standard Kubernetes NetworkPolicy.
- **Hubble relay and UI** — network flow observability with mTLS-secured relay, installed automatically via ACNS.
- **Prometheus metrics endpoint** — Cilium agent exposes 139+ metrics on port 9962 (hostPort), ready to scrape.
- **eBPF datapath** — kernel-level packet processing without iptables overhead.

### Gaps and Limitations

| Gap | Impact | Workaround |
|-----|--------|------------|
| No Hubble metrics export to Prometheus | Cilium Policy Verdicts dashboard (18015) has no data — `hubble_policy_verdicts_total` is not scraped | Use Hubble CLI/UI for per-flow policy verdicts instead |
| ACNS runs old Hubble relay (v1.15.0) | Newer hubble CLI (v1.18+) fails with gRPC ALPN error | Pin hubble CLI to v0.13.x |
| No built-in Cilium Grafana dashboards | Must import community dashboards manually and fix datasource references | Imported IDs 16611 and 18015, added `k8s_app` metricRelabeling |
| No ServiceMonitor for Cilium by default | Prometheus doesn't scrape Cilium metrics out of the box | Created PodMonitor in `manifests/monitoring/cilium-podmonitor.yaml` |
| Azure Monitor profile not configured | No Azure-native metrics integration | Using self-managed kube-prometheus-stack instead |
| Hubble UI is per-cluster only | GKE services don't appear in AKS Hubble UI | GKE has its own Hubble via Dataplane V2 (`kubectl exec` into relay pod) |
| GKE lacks CiliumNetworkPolicy CRDs | Can't use identity-aware policies on GKE without GKE Enterprise | Standard Kubernetes NetworkPolicy with `namespaceSelector` instead |
