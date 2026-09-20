# Chapter 10: Sync Waves & Hooks (ordering inside one app)

Two ArgoCD features that control **ordering within a single Application**:

- **Sync Waves** — apply resources in a defined order (low wave number first),
  waiting for each wave to be Healthy before the next.
- **Hooks** — run Jobs at specific phases: **PreSync** (before), **PostSync**
  (after Healthy), **SyncFail** (on failure). Perfect for DB migrations, smoke
  tests, and alerts.

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Path in repo:** `Chapter10_SyncWaves_and_Hooks/manifests`

---

## 🌊 The order ArgoCD executes

```
   ┌─────────────────────────────────────────────────────────────┐
   │  PreSync hook      db-migrate Job        (runs & must finish) │
   ├─────────────────────────────────────────────────────────────┤
   │  Sync phase, by wave:                                        │
   │     wave -1   Namespace                                       │
   │     wave  0   ConfigMap                                       │
   │     wave  1   Deployment   → wait Healthy                     │
   │     wave  2   Service (NodePort)                              │
   ├─────────────────────────────────────────────────────────────┤
   │  PostSync hook     smoke-test Job        (verify release)     │
   ├─────────────────────────────────────────────────────────────┤
   │  SyncFail hook     on-sync-fail Job       (only if sync fails)│
   └─────────────────────────────────────────────────────────────┘
```

- **Wave** is set with `argocd.argoproj.io/sync-wave: "N"` (a string; can be
  negative). Default is `"0"`. Lower runs first.
- **Hook** is set with `argocd.argoproj.io/hook: PreSync|Sync|PostSync|SyncFail`.
- **Hook cleanup** with `argocd.argoproj.io/hook-delete-policy:` — here
  `HookSucceeded` deletes the Job once it succeeds.

---

## 📁 Files

```
Chapter10_SyncWaves_and_Hooks/
├── README.md
├── application.yaml
└── manifests/
    ├── namespace.yaml                 # wave -1
    ├── configmap.yaml                 # wave  0  (the page)
    ├── deployment.yaml                # wave  1  (nginx)
    ├── service.yaml                   # wave  2  (NodePort 30090)
    ├── hook-presync-migrate.yaml      # PreSync  Job (fake DB migration, ~10s)
    ├── hook-postsync-smoke.yaml       # PostSync Job (smoke test the Service)
    └── hook-syncfail-alert.yaml       # SyncFail Job (alert on failure)
```

Frontend = stock `nginx` serving a page (from the wave-0 ConfigMap) that lists the
wave/hook order, exposed on **NodePort 30090**.

---

## ✅ Prerequisites

- ArgoCD installed, `argocd` CLI logged in.
- This chapter pushed to `main`.

```bash
git add Chapter10_SyncWaves_and_Hooks && git commit -m "Chapter10: sync waves & hooks" && git push origin main
```

---

## 1. Create the Application and WATCH the order ⭐

Apply, then immediately watch — the PreSync migration runs first, then the waves,
then the PostSync smoke test:

```bash
kubectl apply -f Chapter10_SyncWaves_and_Hooks/application.yaml

# Watch resources appear in order (PreSync job → ns → cm → deploy → svc → PostSync job)
watch -n 1 'kubectl -n waves-demo get jobs,pods,deploy,svc,cm 2>/dev/null'
```

Or watch via ArgoCD:

```bash
argocd app get sync-waves-demo            # shows Hook + Wave columns per resource
argocd app sync sync-waves-demo           # (manual sync if you disabled auto)
```

See the hook logs (the story of the rollout):

```bash
kubectl -n waves-demo logs job/db-migrate    # [PreSync] Running DB migration... complete
kubectl -n waves-demo logs job/smoke-test    # [PostSync] Smoke-testing... verified
```

> Because `hook-delete-policy: HookSucceeded`, the Jobs disappear after they
> succeed — check logs quickly, or temporarily change the policy to
> `BeforeHookCreation` to keep the last run.

---

## 2. Open the app

```bash
curl http://<node-ip>:30090        # or:
kubectl -n waves-demo port-forward svc/web 8080:80   # http://localhost:8080
```

The page lists the exact wave/hook order it was deployed in.

---

## 3. Prove the ORDER matters

Watch timestamps — the Deployment (wave 1) is only created **after** the ConfigMap
(wave 0), and the Service (wave 2) after the Deployment:

```bash
kubectl -n waves-demo get cm web-content -o jsonpath='{.metadata.creationTimestamp}'; echo
kubectl -n waves-demo get deploy web       -o jsonpath='{.metadata.creationTimestamp}'; echo
kubectl -n waves-demo get svc web          -o jsonpath='{.metadata.creationTimestamp}'; echo
```

And the PreSync Job's pod completes **before** any `web` pod starts.

## 4. Demo the SyncFail hook (optional)

Force the sync to fail (e.g. an invalid image in the Deployment) and the
`on-sync-fail` Job fires:

```bash
kubectl -n waves-demo set image deploy/web nginx=nginx:doesnotexist   # via Git for real GitOps
# when the sync/health fails, check:
kubectl -n waves-demo get jobs
kubectl -n waves-demo logs job/on-sync-fail
```

---

## Annotation cheat-sheet

| Annotation | Values | Meaning |
|------------|--------|---------|
| `argocd.argoproj.io/sync-wave` | any integer string (`"-1"`, `"0"`, `"2"`) | order within a phase; lower first |
| `argocd.argoproj.io/hook` | `PreSync` `Sync` `PostSync` `SyncFail` `Skip` | which phase a resource runs in |
| `argocd.argoproj.io/hook-delete-policy` | `HookSucceeded` `HookFailed` `BeforeHookCreation` | when to delete the hook resource |

**Waves vs Hooks:**
- *Waves* order **normal** resources of the app (and also resources within a hook phase).
- *Hooks* insert **extra** resources (usually Jobs) at PreSync/PostSync/SyncFail.
- You can combine them: give hooks their own `sync-wave` to order multiple hooks in
  the same phase.

**Common real-world uses**
- **PreSync:** DB schema migration, create secrets, drain/announce maintenance.
- **Waves:** CRDs (wave 0) → controllers (wave 1) → CRs (wave 2); or config → app → ingress.
- **PostSync:** smoke tests, cache warm-up, notify Slack/email, register with a gateway.
- **SyncFail:** page on-call, auto-rollback trigger, cleanup partial changes.

---

## 🧰 Troubleshooting

- **Everything applies at once** — check the annotation is under
  `metadata.annotations` and the value is a **quoted string** (`"1"`, not `1`).
- **Hook Job vanished before I read logs** — `hook-delete-policy: HookSucceeded`
  removed it. Use `BeforeHookCreation` to keep the latest, or read logs promptly.
- **PostSync never runs** — the app must reach **Healthy**; if the Deployment is
  stuck, PostSync waits.
- **Stuck on a wave** — that wave's resource isn't becoming Healthy; inspect it:
  `argocd app get sync-waves-demo` and the pod events.
- **Hook Job fails** — a failed PreSync hook **aborts** the sync (by design), so
  fix the Job (or its image/permissions) before the app will progress.

## 🧹 Cleanup

```bash
kubectl delete -f Chapter10_SyncWaves_and_Hooks/application.yaml
kubectl delete namespace waves-demo --ignore-not-found
```

---

### One-line recap for students
> **Sync waves** order an app's own resources (low number first, health-gated);
> **hooks** run Jobs around the sync — PreSync before, PostSync after Healthy,
> SyncFail on failure — for migrations, smoke tests and alerts.

Happy Learning!
