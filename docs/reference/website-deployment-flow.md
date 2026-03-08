# Website Deployment Flow

How davidshaevel-website code changes flow from source to running on the cluster.

---

## Two Repos, Two Concerns

| Repo | Contains | Trigger |
|------|----------|---------|
| **davidshaevel-website** | Application source code (Next.js, NestJS, Dockerfiles) | Code pushes build Docker images → ACR |
| **davidshaevel-k8s-platform** | Kubernetes manifests (Deployment, Service, Argo CD Application) | Manifest changes → Argo CD syncs to cluster |

This separation is the standard GitOps pattern. Application code and deployment config live in different repos, giving independent release control.

---

## Current Flow

```
1. Developer pushes code to davidshaevel-website (main branch)
2. GitHub Actions builds Docker images → ACR
   - Tagged with git short SHA (e.g., frontend:abc1234) and "latest"
3. *** MANUAL STEP *** Update image tag in k8s-platform manifests
   - Edit manifests/davidshaevel-website/frontend.yaml (and/or backend.yaml)
   - Change image tag from old SHA to new SHA
4. Commit and push k8s-platform to main
5. Argo CD auto-syncs → new image deployed to cluster
```

**Why the manual step exists:** Argo CD watches Git manifests, not container registries. It doesn't know a new image was pushed to ACR until the manifest changes.

**Why this is actually fine:**
- Explicit control over what's deployed and when
- Git history shows exactly which image was deployed and by whom
- You can roll back the deployment (revert the manifest) without rolling back code
- Matches how most production GitOps workflows operate

---

## Automation Options (Roadmap)

### Option A: CI-Driven Promotion (Recommended)

The davidshaevel-website CI pipeline updates the k8s-platform manifest after a successful build.

```
1. Push code to davidshaevel-website
2. GitHub Actions builds image → ACR (tag: abc1234)
3. Same workflow (or repository_dispatch) opens a PR against k8s-platform
   - Updates image tag in manifests/davidshaevel-website/*.yaml
4. PR is reviewed and merged (or auto-merged for dev environments)
5. Argo CD auto-syncs
```

**Pros:** Full control, explicit audit trail, works with plain YAML manifests, no additional controllers.
**Cons:** Requires custom CI pipeline logic.

### Option B: Argo CD Image Updater

A companion controller that watches ACR for new images and updates Argo CD Applications.

**Critical limitation:** Only works with Helm and Kustomize applications — NOT plain YAML manifests. Our current setup uses plain YAML, so this would require switching to Kustomize or Helm for the website manifests.

**Other considerations:**
- Still in `argoproj-labs` (not promoted to main `argoproj` org)
- Maintainers explicitly state: "not recommended for critical production workloads"
- ACR authentication requires extra setup (auth script or service principal)
- Two write-back modes: cluster-only (loses overrides on recreate) or git (recommended, true GitOps)

**Update strategies:** semver (semantic version sorting), newest-build (by build timestamp — good for git SHA tags), digest (watches mutable tags like `latest`), alphabetical.

### Option C: Kustomize + Image Updater

Switch website manifests from plain YAML to Kustomize, then use Image Updater.

```
manifests/davidshaevel-website/
├── kustomization.yaml    # References base manifests + image overrides
├── base/
│   ├── namespace.yaml
│   ├── frontend.yaml
│   └── backend.yaml
└── .argocd-source-davidshaevel-website.yaml  # Image Updater writes here
```

This would enable Image Updater's git write-back mode while keeping manifests readable.

---

## Recommendation

**For now:** The manual flow is appropriate for a dev/learning platform. It gives explicit control and is simple to operate.

**Next step (if automating):** Option A (CI-driven promotion) — add a step to the davidshaevel-website build workflow that uses `repository_dispatch` to trigger a k8s-platform workflow that bumps the image tag and opens a PR. No additional controllers needed, works with plain YAML.

**Future consideration:** Option C (Kustomize + Image Updater) if the platform grows to manage many applications where manual or CI-driven promotion becomes overhead.

---

## Interview Talking Points

- "Application code and deployment config are in separate repos — the standard GitOps pattern"
- "Argo CD watches the manifest repo, not the registry — I have explicit control over what's deployed"
- "I can roll back deployments independently of code changes by reverting the manifest"
- "To automate, I'd add CI-driven promotion — the build pipeline bumps the image tag in the deployment repo via PR"
- "Argo CD Image Updater is an option but requires Helm/Kustomize, and it's still in argoproj-labs"
