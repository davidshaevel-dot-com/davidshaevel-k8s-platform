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
