# K8s Platform Ops Experience — Bumble Interview Prep

**Date:** 2026-03-08
**Context:** Preparing for Bumble Sr. SRE interview (March 12). Track B of interview prep plan.
**Goal:** Transform the k8s-platform from "infrastructure I built" into "a platform I operate" — deploy a real application, set up monitoring, and practice incident response.
**Time budget:** ~8 hours across Sunday–Monday

---

## Success Criteria

- davidshaevel-website deployed to AKS via Argo CD (and GKE as stretch)
- Prometheus + Grafana running with node/pod/container dashboards
- ACNS/Hubble dashboards explored and understood
- At least one incident simulated, troubleshot, and resolved
- Can narrate the full deploy → monitor → incident → resolution flow naturally in 15–20 minutes

---

## Architecture

```
AKS Cluster (existing)
├── argocd namespace (existing)
│   └── Applications:
│       ├── portainer (existing)
│       └── davidshaevel-website (NEW)
├── davidshaevel-website namespace (NEW)
│   ├── frontend (Next.js, image from ACR)
│   └── backend (NestJS, image from ACR)
├── monitoring namespace (NEW)
│   └── kube-prometheus-stack (Prometheus + Grafana + node-exporter + kube-state-metrics)
├── kube-system (existing)
│   └── Hubble relay + UI (existing, ACNS)
└── other existing namespaces...

GKE Cluster (stretch goal)
├── davidshaevel-website namespace (NEW)
│   ├── frontend
│   └── backend
└── (monitored from AKS Grafana or accessed via Teleport)
```

### Key Decisions

- **Separate namespace** (`davidshaevel-website`) for the application
- **kube-prometheus-stack** Helm chart for monitoring — standard, includes Grafana with pre-built dashboards
- **GKE deployment** via Argo CD as stretch goal — demonstrates multi-cloud deployment consistency
- **Access** via Teleport app proxy (same pattern as Portainer and Argo CD)

### Not In Scope

- No global load balancer / shared traffic routing between clusters
- No Loki/log aggregation
- No alerting rules
- No shared database between clusters

---

## Phases

### Phase 1 — Start Clusters & Deploy the App (~2 hours)

1. Start AKS cluster, verify existing services (Teleport, Portainer, Argo CD, Hubble)
2. Create Kubernetes manifests for davidshaevel-website (Deployment, Service, namespace) — commit to repo
3. Create Argo CD Application manifest for the website
4. Deploy via Argo CD, verify pods running and app accessible
5. Add Cilium network policies for the new namespace (same pattern as existing namespaces)

### Phase 2 — Monitoring Stack (~2 hours)

6. Install kube-prometheus-stack via Helm
7. Explore built-in Grafana dashboards (node, pod, container metrics)
8. Explore ACNS/Hubble dashboards and metrics — see what Azure provides out of the box
9. Register Grafana in Teleport (same app proxy pattern)
10. Verify davidshaevel-website metrics visible in Grafana

### Phase 3 — Incident Simulation (~2 hours)

11. **Application incident:** Push a bad image tag via Argo CD (e.g., `frontend:nonexistent`), observe in Grafana (pod restarts, CrashLoopBackOff), troubleshoot with kubectl + dashboards, roll back via Argo CD
12. **Network incident:** Apply a Cilium policy that blocks frontend→backend traffic, observe in Hubble flows, diagnose, fix
13. Practice narrating each incident while working through it

### Phase 4 — GKE Stretch + Polish (~2 hours)

14. Start GKE cluster
15. Create Argo CD Application targeting GKE for the same website
16. Deploy, verify consistency across clusters
17. Practice the full 15–20 min walkthrough

### Cut Line

- Phase 4 drops first if time is tight
- Phase 3 can be trimmed to just the application incident
- Phases 1–2 are essential

---

## Interview Narrative Structure

**Opening (2 min):** "I built a multi-cloud Kubernetes platform to learn platform engineering hands-on. Let me walk you through how I deploy, monitor, and operate applications on it."

**Architecture overview (3 min):** AKS + GKE, Teleport zero-trust access (no public endpoints), Cilium networking with Hubble observability, Argo CD for GitOps.

**Deployment story (3 min):** "Here's how I deploy my website. I define the manifests in Git, Argo CD syncs them to the cluster. Same manifests deploy to both AKS and GKE — operational consistency across clouds."

**Monitoring story (3 min):** "I use Prometheus and Grafana for resource metrics, and Hubble for network flow observability. Here's what my dashboards look like — I can see pod health, resource usage, and network traffic in real time."

**Incident response story (5 min):** "Let me walk you through a real incident. I deployed a Cilium network policy that accidentally triggered implicit egress deny, which broke Teleport for 16 hours. Here's how I diagnosed it using Hubble flows and kubectl, and here's the fix." Plus simulated incidents for variety.

**Tradeoffs & what's next (3 min):** Design decisions, what I'd add next (Crossplane, Loki, alerting).

### Likely Follow-Up Questions

- Why Teleport over nginx ingress / API gateway?
- Why Cilium over default CNI?
- Why Argo CD over Flux or Helm-only?
- How would this scale to 5,000 hosts?
