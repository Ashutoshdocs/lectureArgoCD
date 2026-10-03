# Argo CD Demo: Sync Phases & Hooks

A hands-on demo of running custom code (Kubernetes Jobs) at different points of an Argo CD sync: before, during, after, on failure, and after the app is deleted.

All hook Jobs use public images (`busybox`, `curl`) and print what a real job would do, so the demo runs anywhere without building an image.

---

## The idea in one picture

A sync is **not a single step**. It runs in phases, and in each phase Argo CD runs the resources annotated with that phase's hook.

```
 Sync triggered (manual or auto)
          │
          ▼
 ┌─────────────────┐  ok   ┌──────────────────────────┐  ok   ┌──────────────────┐
 │ 1. PreSync      │ ────▶ │ 2. Sync                  │ ────▶ │ 3. PostSync      │ ──▶ Sync succeeded
 │ PreSync Jobs    │       │ apply manifests          │       │ PostSync Jobs    │
 │ (backup, migrate)│      │ + Sync Jobs              │       │ (tests, notify)  │
 └────────┬────────┘       │ must be Healthy          │       └──────────────────┘
          │ fail           └────────────┬─────────────┘
          ▼                             │ fail
 ┌─────────────────────────────────────────────────────┐
 │ 4. SyncFail: SyncFail Jobs (cleanup, rollback, alert) │
 └─────────────────────────────────────────────────────┘

 Special hooks:  Skip        -> never apply this resource
                 PostDelete  -> run after the Application and its resources are deleted (Argo CD v2.10+)
```

A hook is **any Kubernetes resource** with the annotation `argocd.argoproj.io/hook: <Phase>`. Jobs are the usual choice because they have a clear success or failure; Pods and Argo Workflows also work.

| Phase / Hook | When it runs | What Argo CD waits for | Common uses |
|---|---|---|---|
| **PreSync** | Before any manifest is applied | Job completes successfully | DB migration, backup, pre-checks |
| **Sync** | Together with the normal manifests | Resources applied and Healthy, Jobs succeed | Extra setup tasks, config |
| **PostSync** | After Sync succeeded and **everything is Healthy** | Job completes successfully | Smoke tests, cache warm-up, notifications |
| **SyncFail** | When the sync operation fails | n/a (runs on failure) | Cleanup, rollback, alerts |
| **Skip** | Never | n/a | Keep a manifest in Git that Argo CD must not apply |
| **PostDelete** | After the Application's resources are deleted | Job completes | Clean up external things (DNS, buckets, DB users) |

---

## Repo layout

```
argocd-hooks-demo/
├── README.md
├── argocd/
│   └── application.yaml               # Manual sync, recurse into manifests/
├── manifests/
│   ├── app/                           # The "real" app, all in sync-wave 0
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml            # nginx x2, with readiness probe
│   │   ├── service.yaml
│   │   └── local-secret.yaml          # hook: Skip (never applied)
│   └── hooks/
│       ├── 01-presync-backup.yaml     # PreSync,  wave -1
│       ├── 02-presync-migrate.yaml    # PreSync,  wave 0  (has the failure switch)
│       ├── 03-sync-setup.yaml         # Sync,     wave 1  (after the app is healthy)
│       ├── 04-postsync-test.yaml      # PostSync, wave 0  (real HTTP smoke test)
│       ├── 05-postsync-notify.yaml    # PostSync, wave 1  (HookSucceeded delete policy)
│       ├── 06-syncfail-rollback.yaml  # SyncFail
│       └── 07-postdelete-cleanup.yaml # PostDelete
└── scripts/
    ├── watch.sh                       # Live view of Jobs and app resources
    ├── timeline.sh                    # Hook Jobs in start order, with phase and wave
    └── logs.sh                        # Logs of every hook Job, in order
```

---

## Prerequisites

- A Kubernetes cluster (kind, minikube, k3d, or a cloud cluster)
- `kubectl` and the `argocd` CLI
- **Argo CD v2.10 or newer** (needed for PostDelete)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd admin initial-password -n argocd
argocd login localhost:8080 --username admin --insecure
```

Push this folder to your own Git repo, then set `repoURL` in `argocd/application.yaml`:

```yaml
repoURL: https://github.com/<your-user>/argocd-hooks-demo.git
```

Run all commands from the repo root.

---

## Anatomy of a hook

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration-presync
  annotations:
    argocd.argoproj.io/hook: PreSync                          # WHICH phase
    argocd.argoproj.io/sync-wave: "0"                         # ORDER inside the phase
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation # WHEN to delete the Job
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: busybox:1.36
          command: ["sh", "-c", "echo migrating..."]
```

**Three annotations to know:**

| Annotation | Values | Meaning |
|---|---|---|
| `argocd.argoproj.io/hook` | `PreSync`, `Sync`, `PostSync`, `SyncFail`, `Skip`, `PostDelete` | The phase this resource runs in |
| `argocd.argoproj.io/sync-wave` | Any integer, default `0` | Order **within** a phase. Lower runs first; each wave must be healthy before the next starts |
| `argocd.argoproj.io/hook-delete-policy` | `BeforeHookCreation` (default), `HookSucceeded`, `HookFailed` | When Argo CD deletes the hook resource |

**Hook delete policies:**
- `BeforeHookCreation`: the old Job is deleted just before the next sync creates it again. The Job and its logs stay around until then, which is best for learning and debugging.
- `HookSucceeded`: deleted as soon as it succeeds (the cleanest option).
- `HookFailed`: deleted if it fails.

> **Why this matters:** a Job's pod template can't be changed. With a fixed `name` and no delete policy that removes the old Job, the next sync could fail with "field is immutable". `BeforeHookCreation` avoids this. Another option is `generateName` instead of `name`, which gives every sync a new Job.

---

## Part 1: The full happy path

```bash
kubectl apply -f argocd/application.yaml
```

In a second terminal:

```bash
./scripts/watch.sh
```

Trigger the sync and follow it:

```bash
argocd app sync hooks-demo
```

`argocd app sync` prints each resource as it runs, grouped by phase. You can also follow it in the UI.

When it finishes:

```bash
./scripts/timeline.sh
```

```
JOB                    PHASE     WAVE   STARTED                SUCCEEDED
db-backup-presync      PreSync   -1     ...T10:00:01Z          1
db-migration-presync   PreSync   0      ...T10:00:08Z          1
app-sync-job           Sync      1      ...T10:00:25Z          1
postsync-test          PostSync  0      ...T10:00:33Z          1
```

```bash
./scripts/logs.sh
```

**What to notice:**
1. **PreSync runs first, in wave order:** backup (wave -1), then migrate (wave 0). Nothing from `manifests/app/` exists yet while they run.
2. **Sync phase:** the ConfigMap, Deployment and Service (wave 0) are applied, and Argo CD waits until they are **Healthy**. Only then does `app-sync-job` (wave 1) run.
3. **PostSync** runs only after the whole Sync phase is Healthy, so `postsync-test` can make a real HTTP request to `http://demo-web`.
4. **`postsync-notify` is missing from the timeline.** It has `hook-delete-policy: HookSucceeded`, so it deleted itself after it succeeded.
5. **`rollback-syncfail` did not run,** because nothing failed.
6. **`cleanup-after-delete` did not run.** It's for Part 5.

---

## Part 2: Hooks run on every sync

Hooks are tied to the **sync operation**, not to changes. Sync again without changing anything:

```bash
argocd app sync hooks-demo
./scripts/timeline.sh
```

All the PreSync, Sync and PostSync Jobs ran again (new start times). With `BeforeHookCreation`, the previous Jobs were deleted just before the new ones were created.

> With **automated sync**, a sync (and therefore the hooks) only happens when the app is OutOfSync, meaning after a Git change. Make your hooks **idempotent**, so running a migration twice is harmless.

---

## Part 3: Skip hook

`manifests/app/local-secret.yaml` is in Git but has:

```yaml
annotations:
  argocd.argoproj.io/hook: Skip
```

Check it was never applied:

```bash
kubectl get secret local-secret -n hooks-demo
# Error from server (NotFound)
```

Use Skip for a resource you want to keep in the repo (a template or a local-dev secret) but that something else, not Argo CD, manages in the cluster.

---

## Part 4: Failure and the SyncFail hook

Turn on the failure switch in `manifests/hooks/02-presync-migrate.yaml`:

```yaml
env:
  - name: SIMULATE_FAILURE
    value: "true"       # was "false"
```

```bash
git commit -am "Simulate a failed migration"
git push
argocd app sync hooks-demo
```

The sync fails:

```bash
argocd app get hooks-demo       # Sync status shows the operation Failed
./scripts/timeline.sh
./scripts/logs.sh
```

**What to notice:**
1. `db-backup-presync` succeeded, then `db-migration-presync` **failed**.
2. The sync **stopped at PreSync**: the Deployment was not updated, and the Sync and PostSync Jobs did not run. The running app is untouched, which is exactly why migrations belong in PreSync.
3. `rollback-syncfail` ran and logged the cleanup and alert steps.

Switch it back and confirm the app recovers:

```bash
# set SIMULATE_FAILURE back to "false"
git commit -am "Fix migration"
git push
argocd app sync hooks-demo
```

> **Other ways to see SyncFail:** a Sync phase resource that never becomes healthy (try image `nginx:does-not-exist` with a short `argocd app sync --timeout`), or a failing PostSync test (point `postsync-test` at a wrong URL).

---

## Part 5: PostDelete hook

PostDelete hooks run **after the Application and all its resources are deleted**. Use them to clean up things outside the cluster that Argo CD doesn't track.

In a second terminal, start watching **before** you delete:

```bash
kubectl get jobs,pods -n hooks-demo -w
```

Delete the app (the `resources-finalizer` on the Application makes this a cascade delete):

```bash
argocd app delete hooks-demo --yes
```

**What to notice:**
1. The app resources (Deployment, Service, ConfigMap) and the old hook Jobs are deleted first.
2. Then `cleanup-after-delete` is created and runs.
3. The Application disappears only after the PostDelete hook has finished.

Read its logs while it runs:

```bash
kubectl logs -n hooks-demo job/cleanup-after-delete -f
```

> PostDelete hooks are not part of a sync, so they never run during `argocd app sync`, only on deletion. The namespace still exists afterwards, because `CreateNamespace=true` creates it without tracking it.

---

## Sync waves + hooks: the full order

Waves order resources **within each phase**, and each wave must be healthy before the next starts. The order for this repo is:

| Step | Phase | Wave | Resource |
|---|---|---|---|
| 1 | PreSync | -1 | Job `db-backup-presync` |
| 2 | PreSync | 0 | Job `db-migration-presync` |
| 3 | Sync | 0 | ConfigMap, Deployment, Service (wait for Healthy) |
| 4 | Sync | 1 | Job `app-sync-job` |
| 5 | PostSync | 0 | Job `postsync-test` |
| 6 | PostSync | 1 | Job `postsync-notify` (self-deletes) |
| on failure | SyncFail | 0 | Job `rollback-syncfail` |
| on delete | PostDelete | 0 | Job `cleanup-after-delete` |

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Sync hangs in PreSync or PostSync | The Job is still running or retrying. Check `kubectl get pods -n hooks-demo` and set `backoffLimit` low |
| `field is immutable` on a Job | Fixed `name` without `BeforeHookCreation`; add the delete policy or use `generateName` |
| PostSync never runs | A Sync phase resource is not Healthy (e.g. a failing readiness probe) |
| Hook logs are gone | `HookSucceeded` deleted the Job; use `BeforeHookCreation` while debugging |
| App stuck "Deleting" | A PostDelete hook is failing, or its image can't be pulled. Check its pod |

---

## Key takeaways

- A sync runs in **multiple phases**: PreSync, then Sync, then PostSync, with SyncFail if anything fails.
- A hook is a normal Kubernetes resource (usually a **Job**) with `argocd.argoproj.io/hook`.
- **Sync waves** order resources within a phase; **delete policies** decide when hook resources are removed.
- Hooks run on **every sync**, so make them idempotent.
- Use **Skip** to keep a file out of the cluster, and **PostDelete** (v2.10+) for cleanup after an app is deleted.

---

## Cleanup

```bash
argocd app delete hooks-demo --yes   # if not already deleted in Part 5
kubectl delete namespace hooks-demo
```
