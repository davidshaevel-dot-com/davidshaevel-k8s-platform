# Cilium / Hubble Configuration

Cilium is managed by Azure on AKS (`--network-dataplane cilium`).
It is NOT installed via Helm in this repo. Azure manages the Cilium
DaemonSet in `kube-system`.

## Hubble

Hubble is enabled via Azure Advanced Container Networking Services (ACNS):

- **Enable:** `./scripts/cilium/hubble-enable.sh`
- **Disable:** `./scripts/cilium/hubble-disable.sh`
- **Status:** `./scripts/cilium/status.sh`

Hubble UI is installed separately via a Kubernetes manifest:

- **Install:** `./scripts/cilium/hubble-ui-install.sh`
- **Uninstall:** `./scripts/cilium/hubble-ui-uninstall.sh`
- **Access locally:** `cilium hubble ui` or `kubectl port-forward -n kube-system svc/hubble-ui 12000:80`

## Network Policies

Namespace isolation policies are applied as CiliumNetworkPolicy manifests:

- **Manifests:** `manifests/cilium/namespace-isolation.yaml`
- **Apply:** `./scripts/cilium/apply-policies.sh`

## References

- [Azure ACNS documentation](https://learn.microsoft.com/en-us/azure/aks/use-advanced-container-networking-services)
- [Container Network Observability](https://learn.microsoft.com/en-us/azure/aks/container-network-observability-how-to)
