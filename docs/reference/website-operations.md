# Website Operations

Quick reference for operating the davidshaevel-website deployment on AKS.

---

## Viewing Pod Logs

### kubectl

```bash
# Logs by component
kubectl logs -n davidshaevel-website -l component=frontend
kubectl logs -n davidshaevel-website -l component=backend
kubectl logs -n davidshaevel-website -l component=database

# Follow logs in real-time
kubectl logs -n davidshaevel-website -l component=backend -f

# Last N lines
kubectl logs -n davidshaevel-website -l component=backend --tail=30

# Specific pod by name
kubectl logs -n davidshaevel-website <pod-name>

# All pods in namespace
kubectl logs -n davidshaevel-website --all-containers=true
```

### Argo CD UI

1. Teleport → argocd app
2. Click **davidshaevel-website** application
3. In the topology tree: Deployment → ReplicaSet → **Pod**
4. Click a pod → **Logs** tab

### Portainer UI

1. Teleport → portainer app → AKS environment
2. Namespaces → **davidshaevel-website**
3. Click a pod → **Logs** icon (document icon)

---

## Checking Pod Status

```bash
# All pods in namespace
kubectl get pods -n davidshaevel-website

# Detailed pod info (events, conditions, container status)
kubectl describe pod -n davidshaevel-website -l component=backend

# Watch pods in real-time
kubectl get pods -n davidshaevel-website -w
```

---

## Accessing Services

```bash
# Port-forward frontend (http://localhost:3000)
kubectl port-forward svc/frontend -n davidshaevel-website 3000:3000

# Port-forward backend (http://localhost:3001)
kubectl port-forward svc/backend -n davidshaevel-website 3001:3001

# Health checks
curl http://localhost:3000/health
curl http://localhost:3001/api/health
```

---

## Argo CD Application

```bash
# Check sync and health status
kubectl get applications -n argocd

# Force a sync
kubectl patch application davidshaevel-website -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Or from the Argo CD UI: click Sync on the davidshaevel-website application
```

---

## Exec Into Containers

```bash
# Frontend container
kubectl exec -it -n davidshaevel-website deployment/frontend -- sh

# Backend container
kubectl exec -it -n davidshaevel-website deployment/backend -- sh

# Database container
kubectl exec -it -n davidshaevel-website deployment/database -- sh
```

Application files are at `/app` in both frontend and backend containers (production builds — compiled output only, no source code).
