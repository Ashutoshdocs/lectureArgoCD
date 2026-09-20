# Chapter 9: ApplicationSet — Progressive Sync (RollingSync)

**Progressive Sync** rolls a change out across an ApplicationSet's Applications in
**ordered waves** instead of all at once. Here: one Git commit updates
`dev → qa → prod`, and each wave only starts **after the previous is Healthy**.
It's a staged, environment-by-environment rollout with an automatic health gate.

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Base path:** `Chapter09_ApplicationSet_ProgressiveSync`

---

## 🌊 How it works

```
   You bump the VERSION in Git (all 3 env folders) and push
                         │  all 3 apps go OutOfSync
                         ▼
          ApplicationSet  strategy: RollingSync
                         │
     ┌──── wave 1 ───────┴───────────────────────────────┐
     │  sync web-dev  →  wait until dev is Healthy+Synced │
     └───────────────────────┬───────────────────────────┘
                             ▼
     ┌──── wave 2 ──────────────────────────────────────┐
     │  sync web-qa   →  wait until qa is Healthy+Synced │
     └───────────────────────┬──────────────────────────┘
                             ▼
     ┌──── wave 3 ────────────────────────────────────────┐
     │  sync web-prod →  wait until prod is Healthy+Synced │
     └────────────────────────────────────────────────────┘
```

Steps are matched by the **`env` label** on each generated Application. If a wave
fails to become Healthy, the rollout **stops** there — prod never gets a broken
version.

---

## 📁 Files

```
Chapter09_ApplicationSet_ProgressiveSync/
├── README.md
├── appset.yaml                 # ApplicationSet + RollingSync strategy
└── apps/
    ├── dev/   { configmap(v1, NodePort 30081), deployment, service }   # 🟢
    ├── qa/    { configmap(v1, NodePort 30082), deployment, service }   # 🟠
    └── prod/  { configmap(v1, NodePort 30083), deployment, service }   # 🔴
```

Each env is a frontend (stock `nginx`, page from ConfigMap, no build) exposed on a
distinct **NodePort** and showing a big **VERSION** so you can watch the rollout.

---

## ✅ Prerequisites

- ArgoCD + the **ApplicationSet controller** running.
- `argocd` CLI logged in.
- This chapter pushed to `main`.
- Templates use `goTemplate: true` (v2.5+).

### ⚠️ Enable the Progressive Sync feature flag (required)

RollingSync is behind a feature flag. Turn it on, then wait for the rollout:

```bash
kubectl -n argocd set env deploy/argocd-applicationset-controller \
  ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_PROGRESSIVE_SYNCS=true
kubectl -n argocd rollout status deploy/argocd-applicationset-controller
```

> Alternative (declarative): set `applicationsetcontroller.enable.progressive.syncs: "true"`
> in the `argocd-cmd-params-cm` ConfigMap, then restart the controller.

Push first:
```bash
git add Chapter09_ApplicationSet_ProgressiveSync && git commit -m "Chapter09: progressive sync" && git push origin main
```

---

## 1. Create the ApplicationSet

```bash
kubectl apply -f Chapter09_ApplicationSet_ProgressiveSync/appset.yaml
argocd app list          # → web-dev, web-qa, web-prod (all sync to v1.0.0)
```

Open each env (NodePort on the node's IP):

```bash
curl http://<node-ip>:30081     # 🌱 dev  v1.0.0
curl http://<node-ip>:30082     # 🧪 qa   v1.0.0
curl http://<node-ip>:30083     # 🚀 prod v1.0.0
```

> Single-node kubeadm/minikube: `<node-ip>` is the node's IP; open port 30081-30083
> in the firewall, or use `kubectl -n <env> port-forward svc/web 8080:80`.

---

## 2. ⭐ Trigger a progressive rollout

Bump the version **in all three env pages** in one commit, then push:

```bash
# change  v1.0.0  →  v2.0.0  in each configmap.yaml:
sed -i 's/v1.0.0/v2.0.0/' Chapter09_ApplicationSet_ProgressiveSync/apps/*/configmap.yaml
git commit -am "release v2.0.0" && git push origin main
```

Now **watch the waves** — dev turns v2 first, then qa, then prod:

```bash
watch -n 2 'argocd app list | grep web-'
# or watch health/sync per app:
argocd app get web-dev
```

Refresh the three NodePort pages in order — dev flips to **v2.0.0**, and only once
dev is Healthy does qa start, then prod. That staggered flip is progressive sync.

---

## 3. Bonus: watch the health gate STOP a bad rollout

Make the change break **health** so the rollout halts before prod:

```bash
# point qa at a non-existent image → qa never becomes Healthy
sed -i 's#image: nginx:1.27-alpine#image: nginx:doesnotexist#' \
  Chapter09_ApplicationSet_ProgressiveSync/apps/qa/deployment.yaml
git commit -am "break qa image" && git push origin main
```

Rollout: dev → v-new (Healthy) → **qa stuck (Degraded)** → **prod NOT touched**.
That's the safety property — a failing wave protects the later environments. Revert:

```bash
sed -i 's#image: nginx:doesnotexist#image: nginx:1.27-alpine#' \
  Chapter09_ApplicationSet_ProgressiveSync/apps/qa/deployment.yaml
git commit -am "fix qa image" && git push origin main
```

---

## Anatomy of the strategy

```yaml
strategy:
  type: RollingSync
  rollingSync:
    steps:
      - matchExpressions: [{ key: env, operator: In, values: [dev] }]
      - matchExpressions: [{ key: env, operator: In, values: [qa] }]
      - matchExpressions: [{ key: env, operator: In, values: [prod] }]
```

- Each **step** selects Applications by **label** (`env`), set in the template's
  `metadata.labels`.
- A step completes when its Applications are **Synced + Healthy**.
- Add `maxUpdate: 100%` (count or %) to a step to control how many apps in that
  step sync at once — useful when a step matches many apps (e.g. many clusters).

> Progressive sync needs **automated sync** on the generated apps (set here) so the
> controller can drive each wave.

---

## 🧰 Troubleshooting

- **All 3 update at once (no waves)** — the feature flag isn't enabled. Set
  `ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_PROGRESSIVE_SYNCS=true` on the
  applicationset controller and restart it.
- **Rollout never advances past wave 1** — dev didn't reach Healthy+Synced; check
  `argocd app get web-dev`. A step waits indefinitely for health.
- **Steps don't match any app** — the `env` label isn't on the generated
  Applications; it must be in `template.metadata.labels`.
- **NodePort not reachable** — open 30081-30083 on the node, or use port-forward.
- **`missingkey` template error** — version/goTemplate mismatch; keep
  `goTemplate: true` with `{{.env}}` (v2.5+).

## 🧹 Cleanup

```bash
kubectl delete -f Chapter09_ApplicationSet_ProgressiveSync/appset.yaml
kubectl delete ns dev qa prod --ignore-not-found
# optional: turn the feature flag back off
kubectl -n argocd set env deploy/argocd-applicationset-controller \
  ARGOCD_APPLICATIONSET_CONTROLLER_ENABLE_PROGRESSIVE_SYNCS-
```

---

### One-line recap for students
> **RollingSync** syncs an ApplicationSet's apps in labelled **waves**
> (dev → qa → prod), gating each wave on the previous being Healthy — a safe,
> staged rollout across environments from a single Git change.

Happy Learning!
