# Teleport Access

How to reach the platform's Kubernetes clusters through Teleport from a laptop, starting from a Mac with no Teleport client and ending at `kubectl get nodes` on both clusters.

Every step below was walked on 2026-11-13 on macOS on Apple silicon, with Homebrew installed, on a home network. The outputs quoted are what that walk showed. Two sections, [Log out](#9-log-out) and [Reset a login that no longer works](#10-reset-a-login-that-no-longer-works), were **not walked on 2026-11-13** and are marked that way. They are written from this repo's existing notes.

Follow the steps in order. Each one only uses tools, files and logins that earlier steps have already set up.

---

## Before you start

- **A Mac with [Homebrew](https://brew.sh/).** The walk used macOS on Apple silicon.
- **`kubectl`.** The walk used `kubectl` v1.37.0. See the [version note](#kubectl-version-skew) in step 7.
- **`dig` and `curl`.** Both come with macOS.
- **Permission to run this repo's GitHub Actions workflows.** AKS Start and GKE Start are manual workflows. You can run them from the GitHub website or the GitHub mobile app.
- **The Teleport `admin` user's password, and the authenticator app that holds its second factor.** The server requires a second factor on every sign-in.
- **A browser.** The walk used Chrome.
- **The Azure CLI (`az`), signed in to the subscription that holds the AKS cluster.** You need it only for the account reset in [step 10](#10-reset-a-login-that-no-longer-works). The 2026-11-13 walk did not use it.

---

## 1. Start the clusters

Teleport runs inside the AKS cluster, so nothing below works until AKS is running.

1. Run the **AKS Start** workflow in GitHub Actions. On 2026-11-13 it took about 12 minutes (12:39 to 12:51 CST).
2. Wait until every step is green. Three steps matter for access:
   - **Update Cloudflare DNS** creates the `teleport` and `*.teleport` A records.
   - **Wait for DNS Propagation** is a 60-second sleep.
   - **Verify Teleport** checks for HTTP 200 on `/web/login`. That check runs **from the GitHub runner, not from your network**, so a green step does not prove your own network can resolve the name yet (see step 2).
3. For the GKE cluster, also run the **GKE Start** workflow. It is a separate manual workflow and took about 12 minutes (14:38 to 14:51 CST). GKE Stop deletes the GKE cluster, so `k8s-developer-platform-gke` appears in Teleport only after GKE Start has finished. In the walk, GKE Start ran after AKS Start, and the browser sign-in in step 3 happened before GKE Start.

---

## 2. Check the name resolves

From the network you will work on:

```bash
dig +short teleport.davidshaevel.com
```

If the name resolves, this prints an address. Go on to step 3.

**If it prints nothing even though AKS Start is green**, a resolver on your network has probably cached a "no such name" answer from a lookup made while the cluster was stopped. On 2026-11-13 the name returned NXDOMAIN on the home network from 12:52 to 13:03, and Chrome showed `DNS_PROBE_FINISHED_NXDOMAIN`. The fix was to wait for the cached answer to expire. See [Teleport Name Returns NXDOMAIN After AKS Start](troubleshooting.md#teleport-name-returns-nxdomain-after-aks-start) for the checks and the fix.

To avoid this, do not look the name up, or open it in a browser, while the cluster is stopped.

---

## 3. Sign in from the browser

Signing in from the browser first proves that the name resolves, the certificate is valid, and the password and second factor work, before you install anything.

1. Open `https://teleport.davidshaevel.com`.
2. After a restart, Teleport Community first shows a **"Welcome to Teleport"** terms notice. Tick the checkbox and click **Continue**.
3. The sign-in form has:
   - **Username** and **Password**
   - a **Multi-factor Type** selector, set to **Authenticator App**, with a six-digit **Authenticator Code** field
   - a **Sign in with a Passkey** option below the form (not used in the walk)
4. Sign in as `admin` with the password and a code from the authenticator app.

The **Resources** page then lists:

| Kind | Name |
|------|------|
| Application | `argocd` |
| Application | `davidshaevel-website-aks` |
| Application | `grafana` |
| Application | `portainer` |
| Kubernetes cluster | `k8s-developer-platform-aks` |
| Kubernetes cluster | `teleport.davidshaevel.com` |

The GKE cluster was still stopped when this list was read. After GKE Start it shows up in `tsh kube ls` (step 6).

---

## 4. Install the client

```bash
brew install teleport
tsh version
```

On 2026-11-13 Homebrew installed `teleport 18.11.1` with two dependencies, `libcbor` and `libfido2`. `tsh version` printed:

```
Teleport v18.11.1 git: go1.27.3
```

**Compare the client with the server.** Read `server_version` from `https://teleport.davidshaevel.com/webapi/ping`. On 2026-11-13 it showed:

| Field | Value |
|-------|-------|
| `server_version` | `18.6.8` |
| `min_client_version` | `17.0.0` |
| auth type | local |
| second factor | on |
| preferred local MFA | webauthn |

Keep `tsh` on the **same major version** as `server_version`. In the walk the client (18.11.1) was newer than the server (18.6.8) within major version 18, and no version warning appeared at login. If Homebrew ever installs a newer major version than the server runs, stop and get a matching client first. This page does not cover pinning an older client because the walk did not need one.

---

## 5. `tsh login`

```bash
tsh login --proxy=teleport.davidshaevel.com --user=admin
```

It prompts twice:

```
Enter password for Teleport user admin:
Enter an OTP code from a device:
```

Enter the password, then a code from the authenticator app. On success it prints a status block. On 2026-11-13 it showed:

| Field | Value |
|-------|-------|
| Profile URL | `https://teleport.davidshaevel.com:443` |
| Logged in as | `admin` |
| Cluster | `teleport.davidshaevel.com` |
| Roles | `access, editor` |
| Kubernetes | `enabled` |
| Kubernetes groups | `cluster-admin, system:masters` |
| Valid until | about 12 hours later ("valid for 11h59m") |
| Extensions | `login-ip, permit-agent-forwarding, permit-port-forwarding, permit-pty, private-key-policy` |

Sessions last 12 hours. When one expires, run `tsh login` again.

---

## 6. List the clusters

```bash
tsh kube ls
```

On 2026-11-13, with both clusters started, it listed:

- `k8s-developer-platform-aks`
- `k8s-developer-platform-gke`
- `teleport.davidshaevel.com`

`k8s-developer-platform-gke` is listed only after GKE Start (step 1).

---

## 7. Log `kubectl` in to a cluster

### AKS

```bash
tsh kube login k8s-developer-platform-aks
```

```
Logged into Kubernetes cluster "k8s-developer-platform-aks". Try 'kubectl version' to test the connection.
```

```bash
kubectl get nodes
```

On 2026-11-13 this showed one node, `Ready`, version `v1.33.6`.

### GKE

```bash
tsh kube login k8s-developer-platform-gke
kubectl get nodes
```

On 2026-11-13 this showed one node, `Ready`, version `v1.36.4-gke`.

### What `tsh kube login` changes

Each `tsh kube login` writes a context named `teleport.davidshaevel.com-<cluster name>` into `~/.kube/config` and makes it the current context. For example, the AKS login writes `teleport.davidshaevel.com-k8s-developer-platform-aks`.

### kubectl version skew

The walk used `kubectl` v1.37.0 against the AKS server at 1.33. That is four minor versions ahead, which is outside `kubectl`'s [supported version skew](https://kubernetes.io/releases/version-skew-policy/#kubectl). Listing nodes worked anyway.

---

## 8. Switch clusters

To point `kubectl` at the other cluster, run another `tsh kube login` with its name:

```bash
tsh kube login k8s-developer-platform-gke   # kubectl now talks to GKE
tsh kube login k8s-developer-platform-aks   # kubectl now talks to AKS
```

Each login makes that cluster's `teleport.davidshaevel.com-<cluster name>` context current.

---

## 9. Log out

> **Not walked on 2026-11-13.** The command comes from this repo's `CLAUDE.md` (Helpful Commands → Teleport client). Its output, and what it does to the `teleport.davidshaevel.com-*` contexts in `~/.kube/config`, were not observed.

```bash
tsh logout
```

To use Teleport again afterwards, start from [step 5](#5-tsh-login).

---

## 10. Reset a login that no longer works

> **Not walked on 2026-11-13. The reset command is Teleport's standard one and has not been run against this cluster.** The other commands come from this repo's `CLAUDE.md` (Helpful Commands → Azure CLI, AKS, Teleport admin) and `docs/plans/2026-02-07-teleport-security-design.md`.

### The client's login is stale

For example, the 12-hour session has expired. Log out and log in again:

```bash
tsh logout
tsh login --proxy=teleport.davidshaevel.com --user=admin
```

Then continue from [step 6](#6-list-the-clusters).

### The account itself no longer works

For example, the password is lost or the authenticator app is gone. You cannot fix this through Teleport, because Teleport is what you can no longer sign in to. Instead, use a **direct AKS context** (Azure credentials, not Teleport) and run `tctl` inside the Teleport auth pod.

1. Get a direct AKS context:

   ```bash
   az login
   az account set --subscription "<subscription-name>"
   az aks get-credentials --resource-group k8s-developer-platform-rg --name k8s-developer-platform-aks
   ```

2. Confirm the user exists:

   ```bash
   kubectl exec -n teleport-cluster deployment/teleport-cluster-auth -- tctl users ls
   ```

3. Reset the user:

   ```bash
   kubectl exec -n teleport-cluster deployment/teleport-cluster-auth -- tctl users reset admin
   ```

   This prints a one-time link for setting a new password and second factor. Open it in a browser and complete it. See Teleport's [`tctl users reset` reference](https://goteleport.com/docs/reference/cli/tctl/#tctl-users-reset).

4. Start again from [step 3](#3-sign-in-from-the-browser). After the next `tsh kube login`, `kubectl` goes through Teleport again.
