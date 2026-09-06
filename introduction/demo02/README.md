# Argo CD GitOps Demo 02 — Auto-Updating HTML Page

This demo extends the basic Argo CD flow. Instead of serving the default
Nginx welcome page, Nginx serves **your own `index.html`**, and Argo CD
**automatically re-deploys the page whenever you edit `index.html` and push to Git.**

```text
Developer
    |
    | edit index.html  →  git push
    v
Git Repository
    |
    | Argo CD watches Git
    v
Argo CD
    |
    | Kustomize regenerates the HTML ConfigMap (new hash)
    | Deployment reference changes → rolling update
    v
Kubernetes Cluster
    |
    v
Nginx Pods  →  serve your new HTML
```

---

# 1. Objective

By the end of this demo you will understand:

* How to serve a custom HTML page from Nginx in Kubernetes
* How to keep that HTML **in Git** as `index.html`
* How Argo CD **auto-updates** the page when `index.html` changes
* Why we use a **Kustomize `configMapGenerator`** instead of a plain ConfigMap
* How the ConfigMap **content hash** forces a rolling update
* How `selfHeal` and `prune` behave with this setup

---

# 2. Repository Layout

All files for this demo live under this path in your repo:

```text
argocd-basic-demo/
└── lecture argoCD/
    └── introduction/
        └── demo02/
            ├── index.html          # your beautiful page (source of truth)
            ├── deployment.yaml      # nginx, mounts the HTML ConfigMap
            ├── service.yaml         # NodePort 30080
            ├── kustomization.yaml   # generates the ConfigMap from index.html
            └── argocd-app.yaml      # Argo CD Application (points at this folder)
```

> ⚠️ **Note on the space in `lecture argoCD`.**
> A space in a path is valid inside the YAML `path:` field, but it is painful
> everywhere else (git, shells, tooling). Renaming the folder to
> **`lecture-argocd`** is strongly recommended. If you keep the space,
> always quote the path (`"lecture argoCD/introduction/demo02"`).

---

# 3. The Key Idea — Why a ConfigMap + Kustomize

Nginx serves static files from `/usr/share/nginx/html`. To put *your* HTML
there through GitOps, the HTML must live in a Kubernetes object. We store it
in a **ConfigMap** and **mount it** into the Nginx container.

But a plain ConfigMap has a problem: if you only change the ConfigMap's
*contents*, the Deployment's spec never changes, so pods are not restarted
and the update is slow/uncertain.

**Kustomize `configMapGenerator` solves this.** It builds the ConfigMap from
your `index.html` and appends a **hash of the file contents** to its name:

```text
index.html unchanged  →  nginx-html-dk7fmtb6tt
index.html EDITED     →  nginx-html-6h8m6b4mh8   (new name!)
```

Kustomize also rewrites the Deployment's volume reference to the new name.
A changed name = a changed Deployment spec = **an automatic rolling update**.
`prune: true` then deletes the old, unused ConfigMap.

```text
edit index.html
      |
      v
new content hash
      |
      v
new ConfigMap name  ──►  Deployment reference changes
      |                          |
      v                          v
old ConfigMap pruned      rolling update → new HTML served
```

---
```
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```
---
# 4. `index.html` — the Page (source of truth)

This is the file you edit. It is a self-contained, responsive page.
Save it as `lecture argoCD/introduction/demo02/index.html`.

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Deployed by Argo CD</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=IBM+Plex+Mono:wght@400;500&display=swap" rel="stylesheet" />
  <style>
    :root {
      --paper: #f4f5f7; --ink: #151a2d; --muted: #656d84; --line: #dde0e7;
      --card: #ffffff; --indigo: #4340c9; --sync: #12915a; --signal: #e8622c;
      --radius: 14px;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; }
    body {
      background:
        radial-gradient(1200px 600px at 85% -10%, #e9e8fb 0%, rgba(233,232,251,0) 55%),
        var(--paper);
      color: var(--ink);
      font-family: "Space Grotesk", system-ui, -apple-system, sans-serif;
      line-height: 1.5; min-height: 100vh;
      display: flex; flex-direction: column; align-items: center;
      padding: clamp(20px, 5vw, 56px);
    }
    .wrap { width: 100%; max-width: 880px; }
    .mono { font-family: "IBM Plex Mono", ui-monospace, SFMono-Regular, monospace; font-variant-ligatures: none; }
    .topbar { display: flex; justify-content: space-between; align-items: center; gap: 16px; flex-wrap: wrap; margin-bottom: clamp(32px, 7vw, 64px); }
    .ref { display: inline-flex; align-items: center; gap: 8px; font-size: 13px; color: var(--muted); background: var(--card); border: 1px solid var(--line); padding: 7px 12px; border-radius: 999px; }
    .ref b { color: var(--ink); font-weight: 600; }
    .status { display: inline-flex; align-items: center; gap: 9px; font-size: 14px; font-weight: 600; color: var(--sync); background: rgba(18,145,90,0.09); border: 1px solid rgba(18,145,90,0.25); padding: 7px 14px 7px 12px; border-radius: 999px; }
    .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--sync); box-shadow: 0 0 0 0 rgba(18,145,90,0.5); animation: pulse 2.2s ease-out infinite; }
    @keyframes pulse { 0% { box-shadow: 0 0 0 0 rgba(18,145,90,0.45); } 70% { box-shadow: 0 0 0 10px rgba(18,145,90,0); } 100% { box-shadow: 0 0 0 0 rgba(18,145,90,0); } }
    .kicker { color: var(--indigo); font-weight: 600; font-size: 15px; margin: 0 0 14px; }
    h1 { font-size: clamp(38px, 8vw, 68px); line-height: 1.02; letter-spacing: -0.02em; font-weight: 700; margin: 0 0 20px; }
    .lede { font-size: clamp(17px, 2.4vw, 20px); color: var(--muted); max-width: 60ch; margin: 0 0 clamp(28px, 5vw, 44px); }
    .proof { border: 1px solid var(--line); border-left: 4px solid var(--signal); background: var(--card); border-radius: var(--radius); padding: 22px 24px; margin-bottom: clamp(32px, 6vw, 52px); }
    .proof .label { font-size: 13px; color: var(--muted); margin: 0 0 8px; }
    .proof .value { font-size: clamp(22px, 4vw, 30px); font-weight: 600; color: var(--signal); margin: 0; }
    .flow { display: grid; grid-template-columns: 1fr auto 1fr auto 1fr; align-items: stretch; gap: 10px; margin-bottom: clamp(32px, 6vw, 52px); }
    .node { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius); padding: 16px 14px; text-align: center; }
    .node .n-title { font-weight: 600; font-size: 15px; }
    .node .n-sub { font-size: 12px; color: var(--muted); margin-top: 3px; }
    .arrow { display: flex; align-items: center; justify-content: center; color: var(--indigo); font-size: 20px; font-weight: 600; }
    .facts { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: clamp(32px, 6vw, 52px); }
    .fact { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius); padding: 16px 18px; }
    .fact .k { font-size: 12px; color: var(--muted); margin: 0 0 6px; }
    .fact .v { font-size: 15px; word-break: break-word; }
    footer { color: var(--muted); font-size: 13px; border-top: 1px solid var(--line); padding-top: 20px; }
    @media (max-width: 620px) { .flow { grid-template-columns: 1fr; } .arrow { transform: rotate(90deg); padding: 2px 0; } .facts { grid-template-columns: 1fr; } }
    @media (prefers-reduced-motion: reduce) { .dot { animation: none; } }
  </style>
</head>
<body>
  <main class="wrap">
    <div class="topbar">
      <span class="ref mono">repo:&nbsp;<b>argocd-basic-demo</b>&nbsp;· path:&nbsp;<b>demo02</b></span>
      <span class="status"><span class="dot" aria-hidden="true"></span>Synced · Healthy</span>
    </div>

    <p class="kicker">GitOps, live</p>
    <h1>This page shipped itself from Git.</h1>
    <p class="lede">
      Nobody ran <span class="mono">kubectl apply</span> for this. The HTML you're reading lives
      in a ConfigMap generated from <span class="mono">index.html</span>. Argo CD watches the
      repository and keeps the cluster matching it — commit a change and it lands here on its own.
    </p>

    <!-- Change the line below, commit, and push. Watch it update after Argo CD syncs. -->
    <section class="proof" aria-label="Live edit marker">
      <p class="label">Edit this line in <span class="mono">index.html</span>, then push:</p>
      <p class="value mono">Revision 1 — hello from GitOps 👋</p>
    </section>

    <section class="flow" aria-label="Deployment pipeline">
      <div class="node"><div class="n-title">Git</div><div class="n-sub mono">desired state</div></div>
      <div class="arrow" aria-hidden="true">→</div>
      <div class="node"><div class="n-title">Argo CD</div><div class="n-sub mono">reconciles</div></div>
      <div class="arrow" aria-hidden="true">→</div>
      <div class="node"><div class="n-title">Kubernetes</div><div class="n-sub mono">current state</div></div>
    </section>

    <section class="facts" aria-label="Deployment details">
      <div class="fact"><p class="k">Served by</p><p class="v mono">nginx:1.27</p></div>
      <div class="fact"><p class="k">Namespace</p><p class="v mono">nginx-demo</p></div>
      <div class="fact"><p class="k">Exposed on</p><p class="v mono">NodePort 30080</p></div>
    </section>

    <footer>
      Content mounted read-only from a Kustomize-generated ConfigMap. Sync policy:
      <span class="mono">automated · prune · selfHeal</span>.
    </footer>
  </main>
</body>
</html>
```

---

# 5. `deployment.yaml`

Nginx mounts the generated ConfigMap at its web root. Note the volume
reference is `nginx-html` — Kustomize rewrites it to the hashed name.

```yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: nginx-demo

spec:
  replicas: 2

  selector:
    matchLabels:
      app: nginx-demo

  template:
    metadata:
      labels:
        app: nginx-demo

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

# 6. `service.yaml` (NodePort)

```yaml
apiVersion: v1
kind: Service

metadata:
  name: nginx-demo

spec:
  type: NodePort

  selector:
    app: nginx-demo

  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
```

---

# 7. `kustomization.yaml`

This is what makes the auto-update work. `configMapGenerator` reads
`index.html` and produces a content-hashed ConfigMap.

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

Test it locally (optional):

```bash
cd "lecture argoCD/introduction/demo02"
kubectl kustomize .        # or: kustomize build .
```

You will see a `ConfigMap` named `nginx-html-<hash>` and a `Deployment`
whose volume points at that exact hashed name.

---

# 8. `argocd-app.yaml`

The Application points at the demo02 folder. Argo CD auto-detects
`kustomization.yaml` and renders with Kustomize.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application

metadata:
  name: nginx-demo
  namespace: argocd

spec:
  project: default

  source:
    repoURL: https://github.com/YOUR-USERNAME/argocd-basic-demo.git
    targetRevision: HEAD
    path: "lecture argoCD/introduction/demo02"

  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-demo

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Replace `YOUR-USERNAME` with your GitHub username.

---

# 9. Deploy

Push everything to Git first:

```bash
git add .
git commit -m "demo02: custom auto-updating HTML page"
git push
```

Then register the Application (one time):

```bash
kubectl apply -f "lectureArgoCD/introduction/demo02/argocd-app.yaml"
```

Check status:

```bash
kubectl get application -n argocd
```

Expected:

```text
NAME         SYNC STATUS   HEALTH STATUS
nginx-demo   Synced        Healthy
```

---

# 10. Verify

Check the resources:

```bash
kubectl get all -n nginx-demo
kubectl get configmap -n nginx-demo
```

You should see a `nginx-html-<hash>` ConfigMap, 2 pods, a Deployment, and
a NodePort Service.

Open the page:

```bash
# On the node / via NodePort
http://<NODE-IP>:30080
```

Or port-forward if you can't reach the node port directly:

```bash
kubectl port-forward svc/nginx-demo -n nginx-demo 8081:80
# then open http://localhost:8081
```

---

# 11. The Main Event — Auto-Update on `index.html` Change

1. Open `lecture argoCD/introduction/demo02/index.html`.
2. Change the proof line, e.g.:

   ```html
   <p class="value mono">Revision 1 — hello from GitOps 👋</p>
   ```

   to:

   ```html
   <p class="value mono">Revision 2 — updated live via Argo CD 🚀</p>
   ```

3. Commit and push:

   ```bash
   git add index.html
   git commit -m "Update page to Revision 2"
   git push
   ```

4. Watch Argo CD reconcile:

   ```bash
   kubectl get application nginx-demo -n argocd -w
   kubectl get pods -n nginx-demo -w
   ```

What happens under the hood:

```text
index.html changed
      |
      v
Kustomize builds nginx-html-<NEW hash>
      |
      v
Deployment volume ref updated → rolling update
      |
      v
new pods serve the new page
      |
      v
old nginx-html-<OLD hash> pruned
```

Refresh the browser — your new content is live. No `kubectl apply`, no
manual restart.

> Argo CD polls Git roughly every 3 minutes by default. To see it instantly,
> click **Refresh / Sync** in the Argo CD UI, or configure a Git webhook.

---

# 12. Self-Heal (bonus)

Because `selfHeal: true` is set, manual drift is reverted. Try scaling by hand:

```bash
kubectl scale deployment nginx-demo --replicas=1 -n nginx-demo
kubectl get deployment -n nginx-demo -w
```

Argo CD sees Git says `replicas: 2` and restores it.

---

# 13. Status Reference

| Status      | Meaning                                             |
|-------------|-----------------------------------------------------|
| `Synced`    | Git desired state == cluster state                  |
| `OutOfSync` | Drift between Git and cluster                        |
| `Healthy`   | Resources are running correctly                     |
| `Degraded`  | A resource is failing (e.g. `CrashLoopBackOff`)     |

---

# 14. Useful Commands

```bash
# Argo CD
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl describe application nginx-demo -n argocd

# App resources
kubectl get all -n nginx-demo
kubectl get configmap -n nginx-demo
kubectl get pods -n nginx-demo -w

# Render locally
kubectl kustomize "lecture argoCD/introduction/demo02"
```

---

# 15. Core Concept

```text
        SOURCE OF TRUTH
              |
              v
          index.html  (in Git)
              |
              v
          Kustomize  →  hashed ConfigMap
              |
              v
           Argo CD    →  reconciles
              |
              v
         Kubernetes   →  Nginx serves your page
```

**Git holds the desired page. Argo CD makes the cluster match it — every push.**
