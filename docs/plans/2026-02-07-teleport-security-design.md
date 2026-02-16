# Design: Secure AKS and Portainer Access with Teleport (TT-141)

## Overview

Install Teleport Community Edition on the AKS cluster to secure access to both the Kubernetes API and the Portainer UI. Teleport becomes the single authenticated entry point, replacing the public LoadBalancer IP currently exposing Portainer.

## Decisions

| Decision | Choice | Reasoning |
|----------|--------|-----------|
| Teleport edition | Community (self-hosted) | Free, more learning value, runs on existing AKS cluster |
| TLS certificates | Built-in ACME (Let's Encrypt) | Teleport Helm chart supports ACME natively, no cert-manager needed |
| Domain | `teleport.davidshaevel.com` | Subdomain of existing Cloudflare-managed domain |
| DNS automation | Cloudflare API via script | Consistent with scripted approach, avoids manual dashboard steps |

## Architecture

```
Internet
    |
    v
Azure Load Balancer (Teleport)
    |
    v
AKS Cluster (portainer-rg)
    |
    +-- teleport-cluster namespace
    |       |
    |       v
    |   Teleport Proxy (port 443 HTTPS)
    |       +-- Web UI:   https://teleport.davidshaevel.com
    |       +-- App Proxy: routes to Portainer (ClusterIP)
    |       +-- K8s Proxy: authenticated kubectl access
    |
    +-- portainer namespace
    |       |
    |       v
    |   Portainer BE (ClusterIP, port 9443)
    |       |  (no longer publicly exposed)
    |       v
    |   Persistent Volume
    |
    +-- (future namespaces)
```

Teleport becomes the single public entry point. Portainer's service type changes from LoadBalancer to ClusterIP, removing its public IP. Users access Portainer through `https://teleport.davidshaevel.com` after authenticating with Teleport.

## Implementation Steps

### 1. Prerequisites (manual)

- Create a Cloudflare API token with DNS edit permissions for the davidshaevel.com zone
- Note the Cloudflare Zone ID from the dashboard overview page
- Add both values to `.envrc`:
  ```bash
  export CLOUDFLARE_API_TOKEN="your-token-here"
  export CLOUDFLARE_ZONE_ID="your-zone-id-here"
  ```
- Update `.envrc.example` with the new variable names

### 2. Install Teleport via Helm

Deploy the `teleport-cluster` Helm chart to the `teleport-cluster` namespace.

Helm values (`teleport-cluster-values.yaml`):
```yaml
clusterName: teleport.davidshaevel.com
proxyListenerMode: multiplex
acme: true
acmeEmail: <email>
```

Commands:
```bash
helm repo add teleport https://charts.releases.teleport.dev
helm repo update

kubectl create namespace teleport-cluster
kubectl label namespace teleport-cluster 'pod-security.kubernetes.io/enforce=baseline'

helm install teleport-cluster teleport/teleport-cluster \
  --namespace teleport-cluster \
  --values teleport-cluster-values.yaml
```

### 3. Create DNS record via Cloudflare API

Once the Teleport LoadBalancer gets an external IP, create an A record:
- **Name:** `teleport.davidshaevel.com`
- **Content:** `<Teleport LoadBalancer IP>`
- **Proxied:** `false` (DNS only, grey cloud) -- Teleport handles its own TLS

### 4. Create Teleport admin user

Use `tctl` inside the Teleport Auth pod:
```bash
kubectl exec -n teleport-cluster deployment/teleport-cluster-auth -- \
  tctl users add admin --roles=editor,access --logins=root,ubuntu
```

Complete registration at the URL provided, set up MFA.

### 5. Register Portainer as a Teleport application

Configure Teleport to proxy traffic to Portainer's ClusterIP service at `https://portainer.portainer.svc.cluster.local:9443`.

### 6. Switch Portainer to ClusterIP

Update the Portainer Helm release:
```bash
helm upgrade portainer portainer/portainer \
  -n portainer \
  --set service.type=ClusterIP \
  --set tls.force=true \
  --set enterpriseEdition.enabled=true \
  --set image.tag=lts
```

This removes the public LoadBalancer IP. Portainer is now only accessible through Teleport.

### 7. Verify end-to-end access

- Access `https://teleport.davidshaevel.com` in a browser
- Log in with the admin user
- Access Portainer through the Teleport app proxy
- Verify `tsh kube` commands work for kubectl access

## New Scripts

| Script | Purpose |
|--------|---------|
| `teleport-install.sh` | Install Teleport via Helm with ACME config |
| `teleport-status.sh` | Show Teleport deployment status and access URL |
| `teleport-uninstall.sh` | Remove Teleport with confirmation prompt |
| `teleport-dns.sh` | Create/update Cloudflare A record for teleport.davidshaevel.com |
| `teleport-dns-delete.sh` | Delete the Cloudflare DNS record |

All scripts follow existing conventions: source `config.sh`, call `setup_logging`, use `set -euo pipefail`.

## New Environment Variables

| Variable | Used By | Purpose |
|----------|---------|---------|
| `CLOUDFLARE_API_TOKEN` | `teleport-dns.sh` | Cloudflare API token with DNS edit permissions |
| `CLOUDFLARE_ZONE_ID` | `teleport-dns.sh` | Cloudflare zone ID for davidshaevel.com |

## References

- [Deploy Teleport on Kubernetes (Helm)](https://goteleport.com/docs/zero-trust-access/deploy-a-cluster/helm-deployments/kubernetes-cluster/)
- [Teleport Kubernetes Access](https://goteleport.com/docs/kubernetes-access/)
- [Teleport Application Access](https://goteleport.com/docs/application-access/)
- [Cloudflare API - DNS Records](https://developers.cloudflare.com/api/resources/dns/subresources/records/)
