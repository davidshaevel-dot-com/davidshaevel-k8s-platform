# K8s Platform System Overview — Design

**Date:** 2026-03-12
**Goal:** Create a structured reference document that covers the full platform — architecture, operations, and incident response — organized as a scannable interview guide.

**Format:** Structured reference with headers, tables, and bullet points. Flow-based organization (build → run → fix) so you can start at any section depending on the question.

**Target file:** `docs/reference/system-overview.md`

---

## Sections

### 1. Platform Overview

Concise elevator pitch — what, why, key numbers.

- What: Multi-cloud Kubernetes developer platform managing AKS and GKE
- Why: Built to learn platform engineering hands-on — not just "infrastructure I built" but "a platform I operate"
- Key numbers: 2 clusters, 5 namespaces on AKS, 10+ automation scripts, 4 GitHub Actions workflows, zero public endpoints
- Compact tech stack table (from README)
- Cost awareness: ~$185/mo running, ~$10/mo stopped, GKE fully ephemeral

### 2. Architecture & Design Decisions

Architecture diagram (simplified) plus a design decisions table pairing each choice with reasoning.

Decisions to cover:
- Teleport over ingress controller (zero-trust, no public endpoints)
- Cilium over default CNI (eBPF, identity-aware policies, Hubble)
- Argo CD over Flux or Helm-only (declarative GitOps, multi-cluster, UI)
- Single Argo CD managing both clusters (operational consistency)
- GKE as ephemeral secondary (cost optimization, Argo CD auto-syncs on rebuild)
- Standard NetworkPolicy on GKE (GKE Enterprise too expensive for CiliumNetworkPolicy CRDs)
- kube-prometheus-stack over Azure Monitor (portable, open-source)
- Separate repos for app code and manifests (standard GitOps pattern)

Also: "What's not in scope and why" — no alerting, no log aggregation, no shared database, no global load balancer.

### 3. Deployment & GitOps

How code gets to production on both clusters.

- Two-repo model: davidshaevel-website (app code) and davidshaevel-k8s-platform (manifests)
- Deployment flow: push code → CI builds image → manual tag update → push → Argo CD auto-syncs both clusters
- Why manual step exists and why it's fine
- Multi-cluster sync: same manifests, only infra-level difference is GKE image pull secret
- GKE ephemeral rebuild: delete and recreate, Argo CD auto-syncs everything back

### 4. Monitoring & Observability

Three layers, each with distinct purpose.

- Layer 1 — Metrics (Prometheus + Grafana): resource metrics, key dashboards
- Layer 2 — Network flows (Hubble): per-packet eBPF visibility, policy verdicts
- Layer 3 — Application status (Argo CD): sync/health/drift detection
- Cross-cloud differences: AKS Hubble CLI with mTLS vs GKE kubectl exec, Hubble UI vs GCP Console
- The gap: monitoring without alerting — in production, add Argo CD notifications + Prometheus alerting rules

### 5. Incident Response

Two simulated + one real incident, each demonstrating a different triage pattern.

- Real: Cilium egress deny (16h Teleport outage) — implicit default-deny on egress
- Simulated: Bad image tag — rolling update preserved availability, Argo CD showed Degraded
- Simulated: Network policy blocking backend→database — additive policies, persistent connections, CrashLoopBackOff
- Generalizable triage framework: alert → scope → pods → events/logs → network flows → root cause → fix → verify

### 6. Multi-Cloud Operations

Cross-cloud patterns and operational differences.

- Why multi-cloud: operational consistency, cross-cloud troubleshooting, single control plane
- Cross-cloud comparison table: networking, observability, image pull, cluster lifecycle
- Deployment patterns enabled: blue/green, canary, active/active via Cloudflare weighted DNS
- Cost management: AKS always-on, GKE ephemeral

### 7. Tradeoffs & Future Work

Self-awareness and forward thinking.

- Current tradeoffs: no alerting, no logs, manual image promotion, single-node, no shared state
- What I'd add next: alerting, CI-driven promotion, Loki, Crossplane, External Secrets Operator
- Likely follow-up questions with brief answers: why Teleport, why Cilium, why Argo CD, how would this scale

---

## Content Sources

All content is pulled from existing docs — no new research needed:

| Section | Primary source |
|---------|---------------|
| 1. Overview | README.md, CLAUDE.md |
| 2. Architecture | README.md, CLAUDE.md, GKE multi-cloud design doc |
| 3. Deployment | website-deployment-flow.md, GKE multi-cloud design doc |
| 4. Monitoring | monitoring-and-observability.md |
| 5. Incidents | ops-experience plan (Tasks 8-9), ops-experience design doc |
| 6. Multi-cloud | GKE multi-cloud design doc, monitoring-and-observability.md |
| 7. Tradeoffs | ops-experience design doc, GKE multi-cloud design doc |
