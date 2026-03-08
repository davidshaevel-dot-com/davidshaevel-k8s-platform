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

**First encountered:** 2026-03-08, when adding Prometheus PVC to a cluster that already had PVCs for Teleport, Portainer, Grafana, and PostgreSQL.
