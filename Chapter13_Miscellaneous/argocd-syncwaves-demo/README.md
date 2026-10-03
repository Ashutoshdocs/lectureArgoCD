# Argo CD Demo: Sync Waves

A hands-on demo of controlling the **order** in which Argo CD applies resources during a sync.

It deploys a small app whose parts really depend on each other, so the wrong order visibly breaks things:

```
wave -1   ConfigMaps (app config, nginx config)
   │
wave  0   Redis (Deployment + Service)                  ← must be Ready
   │
wave  1   db-seed Job: writes "greeting" into Redis     ← must Complete
   │
wave  2   backend: reads "greeting" from Redis at startup (fails if missing)
   │
wave  3   frontend: nginx proxy to http://backend (fails if the Service is missing)
   │
wave  4   smoke-test Job: curl frontend, expect the greeting
```

---

## What is a sync wave?

An annotation on any resource:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"   # a string holding an integer; negatives allowed
```

- Default wave is **`0`**.
- **Lower waves run first:** `-5`, then `-1`, then `0`, then `1`, then `10`.
- Argo CD applies all resources in a wave, then **waits until every one of them is Healthy** before starting the next wave.
- If a wave never becomes Healthy, the sync **stops there**, and later waves are not applied.

### The full ordering rule

Argo CD sorts everything in a sync by:

1. **Phase:** PreSync, then Sync, then PostSync (see the hooks demo)
2. **Wave:** lowest first, within each phase
3. **Kind:** within the same wave, e.g. Namespaces and CRDs before ConfigMaps and Secrets, before Services, before Deployments
4. **Name:** alphabetical, as a final tie-breaker

So without any waves, a Namespace is still created before the Deployment that lives in it. What kind ordering can't know is that **your backend needs Redis to be seeded first**. That's what waves are for.

### What "Healthy" means

Waves wait for health, so health checks decide how long a wave takes:

| Resource | Healthy when |
|---|---|
| Deployment / StatefulSet | Rollout finished, and pods pass their **readiness probe** |
| Job | Completed successfully |
| Service | Immediately (for `LoadBalancer`: once it has an address) |
| ConfigMap / Secret | Immediately (no health check) |
| Custom resource with no health check | Immediately |

> **A missing readiness probe makes waves useless.** The Deployment counts as Healthy as soon as its containers start, not when the app can actually serve requests. Every Deployment in this demo has a readiness probe for that reason.

There's also a short pause between waves (2 seconds by default, set with `ARGOCD_SYNC_WAVE_DELAY` on the application controller). It gives other controllers time to react to the previous wave.

---

## Repo layout

```
argocd-syncwaves-demo/
├── README.md
├── argocd/
│   ├── waves-demo.yaml        # App WITH waves    -> namespace waves-demo
│   └── no-waves-demo.yaml     # App WITHOUT waves -> namespace no-waves-demo
├── manifests/                 # The app, one file per wave
│   ├── kustomization.yaml
│   ├── 00-config.yaml         # wave -1
│   ├── 10-redis.yaml          # wave 0
│   ├── 20-seed-job.yaml       # wave 1 (Sync hook, re-created each sync)
│   ├── 30-backend.yaml        # wave 2
│   ├── 40-frontend.yaml       # wave 3
│   └── 50-smoke-test.yaml     # wave 4 (Sync hook)
├── no-waves/
│   └── kustomization.yaml     # Same manifests, sync-wave annotations removed
└── scripts/
    ├── watch.sh               # Live pods/jobs view (watch RESTARTS)
    ├── order.sh               # Resources in creation order, with their wave
    └── cleanup.sh
```

> File name prefixes (`00-`, `10-`...) are **only for humans**. Argo CD ignores file names and order; only the annotation counts.

> The two Jobs are **Sync hooks** with a wave. A plain Job can't be updated on the next sync because its pod template is immutable, so the hook with `BeforeHookCreation` gives you a fresh Job on each sync. Hooks and waves work together: waves order resources *inside* each phase.

---

## Prerequisites

- A Kubernetes cluster (kind, minikube, k3d, or a cloud cluster)
- `kubectl` and the `argocd` CLI
- Argo CD installed:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd admin initial-password -n argocd
argocd login localhost:8080 --username admin --insecure
```

Push this folder to your own Git repo, then set `repoURL` in both files under `argocd/`:

```yaml
repoURL: https://github.com/<your-user>/argocd-syncwaves-demo.git
```

Run all commands from the repo root.

---

## Part 1: Waves in action

```bash
kubectl apply -f argocd/waves-demo.yaml
```

In a second terminal:

```bash
./scripts/watch.sh waves-demo
```

Start the sync:

```bash
argocd app sync waves-demo
```

In the UI (or `argocd app get waves-demo`), watch the resources appear one wave at a time.

When it's done:

```bash
./scripts/order.sh waves-demo
```

```
CREATED                WAVE   KIND         NAME
...T10:00:01Z          -1     ConfigMap    app-config
...T10:00:01Z          -1     ConfigMap    frontend-nginx-conf
...T10:00:04Z          0      Service      redis
...T10:00:04Z          0      Deployment   redis
...T10:00:16Z          1      Job          db-seed
...T10:00:24Z          2      Service      backend
...T10:00:24Z          2      Deployment   backend
...T10:00:35Z          3      Service      frontend
...T10:00:35Z          3      Deployment   frontend
...T10:00:45Z          4      Job          smoke-test
```

**What to notice:**
1. Resources in the **same wave** are created together. Inside a wave, the Service comes before the Deployment (kind ordering).
2. The **gaps between waves** are the time spent waiting for health: Redis's readiness probe, the seed Job completing, the backend passing its probe.
3. **Zero restarts** in the `watch.sh` view. Every component started after its dependencies were ready.

Check the result end-to-end:

```bash
kubectl logs -n waves-demo job/smoke-test
# <h1>Hello from sync waves v1</h1><p>served by backend-...</p>
# [wave 4] PASS
```

---

## Part 2: The same app without waves

`no-waves/kustomization.yaml` reuses the exact same manifests but removes every `sync-wave` annotation, so everything is in wave 0 and only kind ordering applies.

```bash
kubectl apply -f argocd/no-waves-demo.yaml
./scripts/watch.sh no-waves-demo      # second terminal
argocd app sync no-waves-demo
```

**What you'll likely see** (exact results depend on timing):
- The **backend** init container fails with `ERROR: 'greeting' not found in redis`, and pods show `Init:Error` or `Init:CrashLoopBackOff` with restarts.
- The **frontend** may crash with `host not found in upstream "backend"`.
- The **seed** or **smoke-test** Job fails because Redis or the frontend isn't ready yet, so the **sync fails**.

```bash
./scripts/order.sh no-waves-demo
kubectl get pods -n no-waves-demo      # compare the RESTARTS column with waves-demo
```

Kubernetes may *eventually* recover through restarts, but the deploy was noisy, slow, and marked failed. Waves turn "retry until it works" into a predictable order.

Remove it before continuing:

```bash
argocd app delete no-waves-demo --yes
```

---

## Part 3: A blocked wave stops everything after it

Make **two changes** in one commit:

1. `manifests/30-backend.yaml` (wave 2): break the image.
   ```yaml
   image: nginx:1.27-does-not-exist
   ```
2. `manifests/40-frontend.yaml` (wave 3): scale up.
   ```yaml
   replicas: 3
   ```

```bash
git commit -am "Break backend, scale frontend"
git push
argocd app sync waves-demo --async
argocd app get waves-demo
```

**What to notice:**
- The sync is stuck **waiting for wave 2**: the backend rollout never becomes Healthy (`ImagePullBackOff`).
- The frontend is **still at 2 replicas**. Wave 3 hasn't been applied, even though that change is in Git.
- The old backend pods keep serving, because the Deployment's rolling update doesn't remove them until new pods are ready.

The sync keeps waiting. Stop it, fix Git, and sync again:

```bash
argocd app terminate-op waves-demo

git revert --no-edit HEAD
git push
argocd app sync waves-demo
```

> This is the safety net: a broken dependency stops the rollout **before** the things that depend on it change.

---

## Part 4: Waves control order, not restarts

Change the greeting in `manifests/00-config.yaml`:

```yaml
GREETING: "Hello from sync waves v2"
```

```bash
git commit -am "Greeting v2"
git push
argocd app sync waves-demo
```

The sync **fails at wave 4**. Check why:

```bash
kubectl logs -n waves-demo job/smoke-test
# <h1>Hello from sync waves v1</h1> ...
# [wave 4] FAIL
```

The waves ran in order: wave -1 updated the ConfigMap, and wave 1 re-seeded Redis with v2. But the **backend pods didn't restart**, because their pod template didn't change, so they still serve the greeting they loaded at startup.

**Fix:** change the pod template so the backend rolls out. Bump the annotation in `manifests/30-backend.yaml`:

```yaml
template:
  metadata:
    annotations:
      config-version: "2"   # was "1"
```

```bash
git commit -am "Roll backend for greeting v2"
git push
argocd app sync waves-demo
kubectl logs -n waves-demo job/smoke-test   # [wave 4] PASS
```

> Kustomize's `configMapGenerator` or Helm's `checksum/config` annotation do this automatically, by changing the pod template whenever the config changes.

---

## Best practices

- **Only add waves for real dependencies.** Most resources are fine in wave 0; kind ordering already handles Namespace, then ConfigMap, then Deployment.
- **Leave gaps** (`-10`, `0`, `10`, `20`) so you can insert a step later without renumbering everything.
- **Always add readiness probes.** A wave is only as good as the health check it waits on.
- **Use Jobs as gates** (migrations, seeding, checks) to make a later wave wait for a task, not just for pods.
- **Waves order syncs, not restarts.** Change the pod template (checksum annotation, config hash) when config changes.
- **Watch for stuck syncs.** A wave that never becomes Healthy blocks everything after it. Use `argocd app terminate-op` and fix Git.
- **For ordering across Applications** (e.g. an ingress controller before apps), give the Application resources themselves waves in an app-of-apps setup.

---

## Summary

| Concept | Remember |
|---|---|
| Annotation | `argocd.argoproj.io/sync-wave: "<int>"`, default `0`, negatives allowed |
| Order | Phase, then **wave** (low to high), then kind, then name |
| Between waves | Waits until everything in the wave is **Healthy** |
| Failure | A wave that never becomes Healthy **blocks all later waves** |
| With hooks | Waves order resources **within** PreSync, Sync and PostSync |
| Not covered | Waves don't restart pods; change the pod template for that |

---

## Cleanup

```bash
./scripts/cleanup.sh
```
