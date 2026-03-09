# Troubleshooting

Common issues encountered while operating the k8s-platform and their resolutions.

---

## Chrome HSTS Error After AKS Cluster Restart

**Symptom:** After restarting the AKS cluster, Chrome shows "Your connection is not private" when accessing Teleport app proxied services (e.g., `argocd.teleport.davidshaevel.com`, `portainer.teleport.davidshaevel.com`). The error mentions HSTS and there is no "Advanced → Proceed" option.

**Error message:**
> argocd.teleport.davidshaevel.com normally uses encryption to protect your information. When Chrome tried to connect... the website sent back unusual and incorrect credentials... You cannot visit argocd.teleport.davidshaevel.com right now because the website uses HSTS.

**Root cause:** Chrome cached the HSTS (HTTP Strict Transport Security) policy from a previous session. After the cluster restarts, Teleport issues new Let's Encrypt certificates. Even though the new certs are valid, Chrome's cached HSTS state conflicts with the new cert fingerprints, and HSTS prevents bypassing the error.

**Verification:** The certs are actually valid — you can confirm with:
```bash
echo | openssl s_client -connect argocd.teleport.davidshaevel.com:443 \
    -servername argocd.teleport.davidshaevel.com 2>/dev/null \
    | openssl x509 -noout -subject -issuer -dates
```

**Fix: Clear Chrome's HSTS cache**

1. Open Chrome and navigate to `chrome://net-internals/#hsts`
2. Scroll to **"Delete domain security policies"**
3. Enter each affected domain and click **Delete**:
   - `argocd.teleport.davidshaevel.com`
   - `portainer.teleport.davidshaevel.com`
   - (add others as needed, e.g., `grafana.teleport.davidshaevel.com`)
4. Retry accessing the apps — they should load normally

**If that doesn't work:** Clear SSL state via Chrome Settings → Privacy and Security → Security → Manage certificates (or on Mac, clear from Keychain Access).

**First encountered:** 2026-03-08, after AKS cluster had been stopped for 18 days.

---

## Pod Stuck in Pending: Max Volume Count Exceeded

**Symptom:** A pod with a PVC is stuck in `Pending` state. `kubectl describe pod` shows:

> 0/1 nodes are available: 1 node(s) exceed max volume count.

**Root cause:** Azure VM sizes have a hard limit on the number of managed data disks that can be attached. Standard_B2ms allows only 4 data disks. Each PVC backed by a managed disk (the default `StorageClass`) consumes one slot.

**Resolution options:**

1. **Upgrade node VM size** — Standard_B4ls_v2 (4 vCPUs, 8 GiB, ~$107/month) supports 8 data disks. Requires adding a new node pool, draining the old one, and deleting it.
2. **Add a second node** — another Standard_B2ms node adds 4 more disk slots (~$60/month more).
3. **Remove PVC** — use `emptyDir` for non-critical data (e.g., Prometheus metrics on a dev cluster).

**All 2-vCPU Azure VMs are limited to 4 data disks.** To get 8 disks, you must use a 4-vCPU VM.

**Procedure used: Upgrade node pool VM size (zero-downtime)**

AKS doesn't support in-place VM size changes. You must add a new node pool, migrate workloads, and delete the old one.

```bash
# 1. Add a new system node pool with the larger VM size
az aks nodepool add \
    --subscription "${AZURE_SUBSCRIPTION}" \
    --resource-group k8s-developer-platform-rg \
    --cluster-name k8s-developer-platform-aks \
    --name nodepool2 \
    --mode System \
    --node-count 1 \
    --node-vm-size Standard_B4ls_v2

# 2. Wait for the new node to become Ready
kubectl get nodes -w

# 3. Cordon and drain the old node (pods reschedule to new node)
kubectl cordon <old-node-name>
kubectl drain <old-node-name> --ignore-daemonsets --delete-emptydir-data --timeout=120s

# 4. Verify all pods are healthy on the new node
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# 5. Delete the old node pool
az aks nodepool delete \
    --subscription "${AZURE_SUBSCRIPTION}" \
    --resource-group k8s-developer-platform-rg \
    --cluster-name k8s-developer-platform-aks \
    --name nodepool1

# 6. Update DNS (LoadBalancer IP may have changed)
./scripts/teleport/dns.sh

# 7. Update scripts/config.sh with new VM size
```

**Notes:**
- PVC-backed pods (database, Grafana, Prometheus) will have their managed disks reattached to the new node automatically.
- Some system pods (metrics-server, konnectivity-agent) may retry eviction due to PodDisruptionBudgets — the drain command retries until they can be safely moved.
- Total time: ~5-10 minutes (node pool creation + drain + deletion).

**First encountered:** 2026-03-08, when adding Prometheus PVC to a cluster that already had PVCs for Teleport, Portainer, Grafana, and PostgreSQL.

---

## GKE Pods Stuck in Pending: Insufficient CPU on e2-medium

**Symptom:** After deploying davidshaevel-website to GKE via Argo CD, the frontend pod starts but the backend and database pods are stuck in `Pending`. `kubectl describe pod` shows:

> 0/1 nodes are available: 1 Insufficient cpu. no new claims to deallocate, preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.

**Root cause:** GKE's e2-medium (2 shared vCPUs, 4 GiB RAM) has only ~940m allocatable CPU after system reservations (~1060m reserved for kubelet, kube-proxy, kube-dns, fluentbit, metrics agents, etc.). With Portainer agent, Teleport agent, system pods, and the frontend already scheduled, CPU requests totaled ~848m (90%), leaving only ~90m free — not enough for the backend (100m) and database (100m) pods.

**Resource breakdown at time of issue:**

| | Capacity | Allocatable | Requested | Free |
|---|---|---|---|---|
| CPU | 2000m | 940m | 848m | ~90m |
| Memory | 3.8 GiB | 2.8 GiB | ~1.2 GiB | ~1.6 GiB |

**Key insight:** GKE reserves over half the CPU on a 2 shared-core e2-medium for system components. The "2 vCPUs" is misleading — only ~940m is available for workloads.

**Resolution:** Upgraded from `e2-medium` (2 shared vCPUs, 4 GiB, ~$25/month) to `e2-standard-2` (2 dedicated vCPUs, 8 GiB, ~$49/month). Dedicated cores provide ~1,800m allocatable CPU — nearly double — with plenty of headroom for all website pods plus agents.

**Procedure:**
1. Updated `GKE_MACHINE_TYPE` in `scripts/config.sh` from `e2-medium` to `e2-standard-2`
2. Deleted the cluster: `./scripts/gke/stop.sh`
3. Recreated with new type: `./scripts/gke/start.sh`

Since GKE clusters are fully deleted on stop and recreated on start, there is no in-place resize — just change the config and rebuild.

**First encountered:** 2026-03-09, when deploying davidshaevel-website to GKE for multi-cloud deployment (TT-263).

---

## GKE: CiliumNetworkPolicy CRD Not Available

**Symptom:** Applying a `CiliumNetworkPolicy` manifest on GKE returns:

> resource mapping not found for name: "allow-intra-namespace" namespace: "davidshaevel-website" from "...": no matches for kind "CiliumNetworkPolicy" in version "cilium.io/v2"

**Root cause:** GKE Dataplane V2 uses Cilium internally for its dataplane, but does **not** expose the `CiliumNetworkPolicy` CRD. The CRD is only available with GKE Enterprise (paid tier). Standard GKE clusters only support Kubernetes-native `NetworkPolicy` resources.

**Resolution:** Use standard Kubernetes `NetworkPolicy` instead of `CiliumNetworkPolicy` on GKE. GKE Dataplane V2 enforces standard NetworkPolicy via its Cilium dataplane, so the security posture is equivalent.

**Key difference from AKS:** AKS with Azure CNI Overlay + Cilium (ACNS) exposes full `CiliumNetworkPolicy` CRDs. The same security intent requires different manifest formats:
- **AKS:** `CiliumNetworkPolicy` with `endpointSelector` and `fromEndpoints` using `k8s:io.kubernetes.pod.namespace`
- **GKE:** Standard `NetworkPolicy` with `podSelector` and `namespaceSelector` using `kubernetes.io/metadata.name`

See `manifests/cilium/namespace-isolation.yaml` (AKS) vs `manifests/cilium/gke-namespace-isolation.yaml` (GKE).

**First encountered:** 2026-03-09, during GKE multi-cloud deployment (TT-263).
