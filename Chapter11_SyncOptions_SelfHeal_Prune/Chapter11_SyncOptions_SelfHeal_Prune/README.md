# Chapter 11: Sync Options, Self-Heal & Prune (deep-dive)

ArgoCD's `syncPolicy` decides **how** an app is kept in sync. This chapter makes
each knob tangible: you'll fight the cluster against Git and watch ArgoCD win.

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Path in repo:** `Chapter11_SyncOptions_SelfHeal_Prune/manifests`

---

## 🧠 The three behaviours

```
   selfHeal  ─ you edit the CLUSTER   → ArgoCD reverts it to match Git
   prune     ─ you edit GIT (delete)  → ArgoCD deletes it from the cluster
   ignoreDifferences ─ some fields    → allowed to drift (not reverted / not shown OutOfSync)
```

| Setting | Where | Effect |
|---------|-------|--------|
| `automated.selfHeal` | app | live drift → reverted to Git |
| `automated.prune` | app | removed-from-Git → deleted from cluster |
| `automated.allowEmpty` | app | allow syncing to **zero** resources (default false = safety) |
| `syncOptions: CreateNamespace=true` | app | auto-create destination namespace |
| `syncOptions: PruneLast=true` | app | delete prunable resources **after** applying the rest |
| `syncOptions: ApplyOutOfSyncOnly=true` | app | only apply resources that differ (faster) |
| `syncOptions: ServerSideApply=true` | app/res | use k8s server-side apply |
| `syncOptions: Replace=true` | app/res | `kubectl replace` instead of apply (last resort) |
| `syncOptions: Validate=false` | app/res | skip client-side schema validation |
| `sync-options: Prune=false` (annotation) | resource | never prune this resource |
| `sync-options: Delete=false` (annotation) | resource | keep resource even when the app is deleted |
| `ignoreDifferences` | app | ignore drift on specific fields (e.g. replicas) |

---

## 📁 Files

```
Chapter11_SyncOptions_SelfHeal_Prune/
├── README.md
├── application.yaml               # fully-commented syncPolicy
└── manifests/
    ├── namespace.yaml
    ├── configmap.yaml             # the page
    ├── deployment.yaml            # nginx, replicas: 2  (self-heal target)
    ├── service.yaml               # NodePort 30095
    └── extra-configmap.yaml       # "prune-me" → delete from Git to demo prune
```

---

## ✅ Setup

```bash
git add Chapter11_SyncOptions_SelfHeal_Prune && git commit -m "Chapter11: sync options" && git push origin main
kubectl apply -f Chapter11_SyncOptions_SelfHeal_Prune/application.yaml
argocd app get sync-demo
kubectl -n sync-demo get all,cm
# open the page:
kubectl -n sync-demo port-forward svc/web 8080:80    # http://localhost:8080  (or NodePort 30095)
```

---

## Demo 1 — Self-heal reverts a manual SCALE ⭐

Scale the Deployment by hand; ArgoCD snaps it back to `replicas: 2`:

```bash
kubectl -n sync-demo scale deploy/web --replicas=5
kubectl -n sync-demo get deploy web -w      # briefly 5 → back to 2
argocd app get sync-demo                     # OutOfSync → Synced again
```

> With `selfHeal: false`, it would show **OutOfSync** and wait for a manual sync
> instead of reverting.

## Demo 2 — Self-heal reverts a manual EDIT

Edit the live ConfigMap; ArgoCD restores the Git version:

```bash
kubectl -n sync-demo patch configmap web-content --type merge \
  -p '{"data":{"note":"hand-edited!"}}'
kubectl -n sync-demo get configmap web-content -o jsonpath='{.data.note}'; echo
#   → the key is removed/reverted because it isn't in Git
```

## Demo 3 — Prune deletes a resource removed from Git ⭐

Remove the throwaway ConfigMap from Git and push:

```bash
git rm Chapter11_SyncOptions_SelfHeal_Prune/manifests/extra-configmap.yaml
git commit -m "remove prune-me" && git push origin main
# after sync:
kubectl -n sync-demo get configmap prune-me     # → NotFound (pruned)
```

> With `prune: false`, `prune-me` would linger and the app would show **OutOfSync**
> with a "requires pruning" resource until you prune manually
> (`argocd app sync sync-demo --prune`).

## Demo 4 — Protect a resource from pruning (`Prune=false`)

Re-add `extra-configmap.yaml`, uncomment its annotation, push & sync:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
```

Now delete the file from Git again → the ConfigMap **survives** (it becomes an
orphan you'd remove by hand). Great for resources you never want auto-deleted
(e.g. a PVC or a shared secret).

## Demo 5 — Let a field drift with `ignoreDifferences`

By default self-heal fights your HPA over `replicas`. To let replicas drift,
uncomment the `ignoreDifferences` block in `application.yaml`, push & sync:

```yaml
ignoreDifferences:
  - group: apps
    kind: Deployment
    name: web
    namespace: sync-demo
    jsonPointers: [ /spec/replicas ]
```

Now repeat Demo 1: `kubectl scale deploy/web --replicas=5` **stays at 5** — ArgoCD
no longer considers replicas a difference. (`RespectIgnoreDifferences=true` ensures
a sync won't shove it back to 2 either.)

---

## Manual sync flags (when auto is off)

```bash
argocd app sync sync-demo --prune              # apply + delete removed resources
argocd app sync sync-demo --dry-run            # preview only
argocd app sync sync-demo --force              # kubectl replace on conflicts
argocd app sync sync-demo --resource :Service:web   # sync a single resource
```

## Auto vs manual, at a glance

| | selfHeal ON | selfHeal OFF |
|---|---|---|
| cluster drift | auto-reverted | shows OutOfSync, wait |
| | prune ON | prune OFF |
| removed from Git | auto-deleted | OutOfSync "needs prune" |

---

## 🧰 Troubleshooting / gotchas

- **Self-heal isn't reverting** — `automated.selfHeal` is false, or the field is in
  `ignoreDifferences`. Also, self-heal reacts to detected drift; give it a few
  seconds (or `argocd app sync`).
- **App won't delete resources** — `prune` is false, or the resource has
  `Prune=false`. Use `--prune` on a manual sync.
- **App tried to delete EVERYTHING** — a bad Git path made the app empty;
  `allowEmpty: false` protects you (sync is refused). Fix the path.
- **ArgoCD keeps fighting my HPA** — add `ignoreDifferences` on `/spec/replicas`
  (Demo 5) so replica count is allowed to drift.
- **Namespace missing on first sync** — add `CreateNamespace=true` (already set).

## 🧹 Cleanup

```bash
kubectl delete -f Chapter11_SyncOptions_SelfHeal_Prune/application.yaml
kubectl delete namespace sync-demo --ignore-not-found
```

---

### One-line recap for students
> **selfHeal** reverts cluster drift, **prune** deletes what's gone from Git, and
> **ignoreDifferences / Prune=false / sync options** are the escape hatches when you
> need ArgoCD to leave something alone.

Happy Learning!
