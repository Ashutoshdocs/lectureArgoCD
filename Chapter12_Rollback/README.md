# Argo CD Demo — Rollback to a Previous Version

This demo shows how to **roll back** an application deployed by Argo CD.
You deploy **Version 1** of an HTML page, ship **Version 2**, then return to
**Version 1** — two ways: the GitOps way (`git revert`) and Argo CD's built-in
**History and Rollback** feature.

```text
v1 (teal)  ──ship──►  v2 (orange)  ──rollback──►  v1 (teal)
   |                     |                          |
   git                   git                        Git revert  OR  Argo CD history
```

---

# 1. Objective

By the end of this demo you will understand:

* How to ship a new version of a page through Git
* How Argo CD records a **revision history** of every sync
* How to roll back with **`git revert`** (auto-sync friendly, recommended)
* How to roll back with **Argo CD History & Rollback** (`argocd app rollback`)
* Why **automated `selfHeal`** fights a manual rollback — and how to handle it

---

# 2. Repository Layout

```text
argocd-basic-demo/
└── lectureArgoCD/
    └── rollback/
        ├── index.html          # the page — version marker + accent colour
        ├── deployment.yaml      # nginx, mounts the HTML ConfigMap
        ├── service.yaml         # NodePort 30081
        ├── kustomization.yaml   # generates the ConfigMap from index.html
        └── argocd-app.yaml      # Argo CD Application (points at this folder)
```

Each edit to `index.html` becomes a **new Git commit** and therefore a **new
Argo CD revision** — those revisions are exactly what you roll back to.

---

# 3. `index.html` — Version 1

Save as `lectureArgoCD/rollback/index.html`. The version tag and accent
colour live in two CSS variables at the top, so a version bump is a tiny,
obvious edit.

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Rollback Demo</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet" />
  <style>
    :root {
      /* EDIT THESE TWO LINES TO MAKE A NEW VERSION */
      --accent: #0f9d8f;        /* v1 = teal   (v2 try: #e8622c) */
      --version: "v1";          /* shown in the big tag         */

      --paper: #0e1116; --ink: #f2f4f8; --muted: #99a2b2;
      --line: #242a34; --card: #161b22; --radius: 16px;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; }
    body {
      background:
        radial-gradient(900px 500px at 80% -20%, color-mix(in srgb, var(--accent) 22%, transparent) 0%, rgba(0,0,0,0) 60%),
        var(--paper);
      color: var(--ink);
      font-family: "Space Grotesk", system-ui, -apple-system, sans-serif;
      line-height: 1.5; min-height: 100vh;
      display: flex; align-items: center; justify-content: center;
      padding: clamp(20px, 5vw, 56px);
    }
    .card { width: 100%; max-width: 760px; background: var(--card); border: 1px solid var(--line); border-radius: var(--radius); overflow: hidden; }
    .banner { height: 6px; background: var(--accent); }
    .body { padding: clamp(28px, 6vw, 52px); }
    .tag {
      display: inline-flex; align-items: baseline; gap: 4px;
      font-family: "IBM Plex Mono", ui-monospace, monospace;
      font-size: clamp(40px, 12vw, 84px); font-weight: 500;
      color: var(--accent); line-height: 1; letter-spacing: -0.02em; margin: 0 0 18px;
    }
    .tag::before { content: var(--version); }
    h1 { font-size: clamp(26px, 5vw, 40px); font-weight: 700; letter-spacing: -0.02em; margin: 0 0 14px; }
    p.lede { color: var(--muted); font-size: clamp(16px, 2.3vw, 19px); max-width: 56ch; margin: 0 0 28px; }
    .meta { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 28px; }
    .chip { font-family: "IBM Plex Mono", ui-monospace, monospace; font-size: 13px; color: var(--muted); border: 1px solid var(--line); border-radius: 999px; padding: 6px 12px; }
    .chip b { color: var(--ink); font-weight: 500; }
    .hint { border-left: 3px solid var(--accent); background: color-mix(in srgb, var(--accent) 8%, transparent); border-radius: 8px; padding: 14px 16px; color: var(--muted); font-size: 14px; }
    .hint code { color: var(--ink); font-family: "IBM Plex Mono", monospace; }
  </style>
</head>
<body>
  <main class="card">
    <div class="banner" aria-hidden="true"></div>
    <div class="body">
      <p class="tag" aria-label="current version"></p>
      <h1>You are looking at Version 1.</h1>
      <p class="lede">
        This page is stored in Git and deployed by Argo CD. Ship a new version by
        editing <code>index.html</code>; roll back by pointing Argo CD at an
        earlier revision. The colour and tag above change with each version, so a
        rollback is obvious at a glance.
      </p>
      <div class="meta">
        <span class="chip">app:&nbsp;<b>nginx-rollback</b></span>
        <span class="chip">ns:&nbsp;<b>rollback-demo</b></span>
        <span class="chip">port:&nbsp;<b>30081</b></span>
      </div>
      <p class="hint">
        Next: change <code>--accent</code> and <code>--version</code> at the top of
        this file, commit, and push. Then roll back and watch this go teal again.
      </p>
    </div>
  </main>
</body>
</html>
```

---

# 4. `deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: nginx-rollback

spec:
  replicas: 2

  selector:
    matchLabels:
      app: nginx-rollback

  template:
    metadata:
      labels:
        app: nginx-rollback

    spec:
      containers:
        - name: nginx
          image: nginx:1.27

          ports:
            - containerPort: 80

          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true

      volumes:
        - name: html
          configMap:
            name: nginx-html   # rewritten to nginx-html-<hash> by Kustomize
```

---

# 5. `service.yaml` (NodePort)

```yaml
apiVersion: v1
kind: Service

metadata:
  name: nginx-rollback

spec:
  type: NodePort

  selector:
    app: nginx-rollback

  ports:
    - port: 80
      targetPort: 80
      nodePort: 30081
```

---

# 6. `kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml

configMapGenerator:
  - name: nginx-html
    files:
      - index.html
```

---

# 7. `argocd-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application

metadata:
  name: nginx-rollback
  namespace: argocd

spec:
  project: default

  source:
    repoURL: https://github.com/YOUR-USERNAME/argocd-basic-demo.git
    targetRevision: HEAD
    path: lectureArgoCD/rollback

  destination:
    server: https://kubernetes.default.svc
    namespace: rollback-demo

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Replace `YOUR-USERNAME` with your GitHub username.

---

# 8. Deploy Version 1

Push the files, then register the Application:

```bash
git add .
git commit -m "rollback demo: version 1 (teal)"
git push

kubectl apply -f lectureArgoCD/rollback/argocd-app.yaml
```

Check and open it:

```bash
kubectl get application nginx-rollback -n argocd
kubectl get all -n rollback-demo

# open http://<NODE-IP>:30081   (or port-forward)
kubectl port-forward svc/nginx-rollback -n rollback-demo 8081:80
# then http://localhost:8081  → big teal "v1"
```

---

# 9. Ship Version 2

Edit **only the two marked lines** in `index.html`:

```diff
-      --accent: #0f9d8f;        /* v1 = teal */
-      --version: "v1";
+      --accent: #e8622c;        /* v2 = orange */
+      --version: "v2";
```

(Optionally change the `<h1>` text to "You are looking at Version 2.")

Commit and push:

```bash
git add index.html
git commit -m "rollback demo: version 2 (orange)"
git push
```

Argo CD syncs and the page turns **orange "v2"**. You now have two revisions
in history — this is the state we will roll back from.

```text
Git history:            Argo CD synced:
  commit A  = v1  ◄─ rollback target
  commit B  = v2  ◄─ current
```

---

# 10. Rollback — Method A: `git revert` (recommended)

This is the GitOps-native rollback. Git stays the source of truth, and it
works **even with automated sync on**, because you are moving `HEAD` back to
the old state with a brand-new commit.

```bash
# undo the v2 commit; creates a new commit that restores v1 content
git revert --no-edit HEAD
git push
```

Argo CD sees the new `HEAD`, re-syncs, and the page returns to **teal "v1"**.

```text
commit A = v1
commit B = v2
commit C = revert of B  → content == v1   ◄─ HEAD now
```

Watch it:

```bash
kubectl get application nginx-rollback -n argocd -w
kubectl get pods -n rollback-demo -w
```

Why this is preferred: your Git history honestly records that a rollback
happened, and nothing drifts out of sync.

---

# 11. Rollback — Method B: Argo CD History & Rollback

Argo CD keeps a deployment history and can roll the cluster back to any past
**synced revision** without touching Git.

> ⚠️ **Critical:** with `automated` + `selfHeal` enabled, Argo CD will
> immediately re-sync the cluster to Git `HEAD` and **undo your rollback**.
> You must turn automation off first, then roll back.

### 1. Log in to the Argo CD CLI

```bash
# password (same as the UI admin password):
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# with the UI port-forward running (kubectl port-forward svc/argocd-server -n argocd 8080:443)
argocd login localhost:8080 --username admin --password <PASSWORD> --insecure
```

### 2. Disable automated sync (so the rollback sticks)

```bash
argocd app set nginx-rollback --sync-policy none
```

### 3. Look at the history and pick a revision

```bash
argocd app history nginx-rollback
```

```text
ID  DATE                 REVISION
0   2025-... (v1)        <sha-A>
1   2025-... (v2)        <sha-B>   ← current
```

### 4. Roll back to the v1 entry (ID 0)

```bash
argocd app rollback nginx-rollback 0
```

The page returns to **teal "v1"**. The app will show `OutOfSync` because the
cluster (v1) no longer matches Git `HEAD` (v2) — that is expected while
automation is off.

### 5. Re-enable automation when you're done

```bash
argocd app set nginx-rollback --sync-policy automated --auto-prune --self-heal
```

> Re-enabling automation makes Argo CD sync back to Git `HEAD` (v2). If you
> want v1 to be permanent, fix it in Git (Method A) instead.

**Same idea in the UI:** open the app → **History and Rollback** → pick the
v1 row → **Rollback**. (Disable Auto-Sync first via **App Details → Sync
Policy → Disable Auto-Sync**.)

---

# 12. Method A vs Method B

| | `git revert` (A) | Argo CD rollback (B) |
|---|---|---|
| Source of truth | Git (stays correct) | Cluster only (Git now differs) |
| Works with auto-sync on | ✅ yes | ❌ no — must disable first |
| Leaves an audit trail | ✅ in Git history | ✅ in Argo CD history |
| Best for | permanent rollback / production | quick recovery / incident triage |

Rule of thumb: **fix production in Git (A); use Argo CD rollback (B) for a
fast, temporary revert during an incident.**

---

# 13. Bonus — Kubernetes-level rollback

Independent of Argo CD, the Deployment also keeps a ReplicaSet history:

```bash
kubectl rollout history deployment/nginx-rollback -n rollback-demo
kubectl rollout undo deployment/nginx-rollback -n rollback-demo
```

Note: with `selfHeal` on, Argo CD will pull this back to Git state too — so
for GitOps, prefer Method A.

---

# 14. Core Concept

```text
        GIT = desired state (every version is a commit)
                 |
                 v
   ARGO CD keeps a history of synced revisions
                 |
        ┌────────┴─────────┐
        v                  v
  git revert          argocd app rollback
 (move Git back)     (move cluster back)
        |                  |
        v                  v
     Kubernetes serves the previous version
```

**To roll back the right way, roll back Git — Argo CD does the rest.**
