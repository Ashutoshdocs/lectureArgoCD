# Nginx on ArgoCD — UI Deployment Demo

A minimal, self-contained demo that deploys an **nginx** app serving a custom
`index.html` to Kubernetes using **ArgoCD**, driven entirely through the
**ArgoCD web UI** (GitOps style).

The custom page is served from a Kubernetes **ConfigMap** mounted into the
stock `nginx` image — so there is **no Docker image to build or push**.

---

## 📁 Repository layout

```
nginx-argocd-demo/
├── README.md                 # this file
├── application.yaml          # optional: ArgoCD Application (for kubectl apply)
└── manifests/                # the app ArgoCD will sync
    ├── namespace.yaml        # nginx-demo namespace
    ├── configmap.yaml        # the custom index.html
    ├── deployment.yaml       # nginx Deployment (2 replicas)
    └── service.yaml          # ClusterIP Service on port 80
```

---

## ✅ Prerequisites

- A running Kubernetes cluster (minikube, kind, k3s, Docker Desktop, or a cloud cluster).
- `kubectl` configured to talk to that cluster.
- **ArgoCD installed** in the cluster (steps below).
- A **Git repository** you can push these files to (GitHub/GitLab/Bitbucket).
  ArgoCD reads manifests from Git — it cannot sync from your laptop.

---

## 1. Install ArgoCD (if you don't have it yet)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait until all pods are Ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
```

---

## 2. Open the ArgoCD UI

Port-forward the ArgoCD API server to your machine:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Now open **https://localhost:8080** in your browser
(accept the self-signed certificate warning).

**Get the initial admin password:**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

- **Username:** `admin`
- **Password:** the value printed above

---

## 3. Push this demo to your Git repo

```bash
cd nginx-argocd-demo
git init
git add .
git commit -m "nginx argocd demo"
git branch -M main
git remote add origin https://github.com/<userName>/lectureArgoCD.git
git push -u origin main
```

Note the repo URL and the path to the manifests folder: **`Chapter02_UI_Based_deployment/manifests`**.

---

## 4. Create the Application in the ArgoCD UI  ⭐

This is the main event — deploying via the UI.

1. Click **+ NEW APP** (top-left).
2. Fill in the **GENERAL** section:
   - **Application Name:** `nginx-demo`
   - **Project Name:** `default`
   - **Sync Policy:** `Automatic`
   - Tick ✅ **Prune Resources** and ✅ **Self Heal**
   - Tick ✅ **Auto-Create Namespace** (creates `nginx-demo` for you)
3. Fill in the **SOURCE** section:
   - **Repository URL:** `https://github.com/<your-user>/nginx-argocd-demo.git`
   - **Revision:** `HEAD`
   - **Path:** `manifests`
4. Fill in the **DESTINATION** section:
   - **Cluster URL:** `https://kubernetes.default.svc` (the in-cluster option)
   - **Namespace:** `nginx-demo`
5. Click **CREATE** (top).

> **Private repo?** Add credentials first under
> **Settings → Repositories → + CONNECT REPO** before creating the app.

---

## 5. Sync and watch it deploy

- The app appears as a tile on the dashboard, initially **Missing / OutOfSync**.
- With **Automatic** sync it syncs on its own within seconds. To do it manually,
  click the app, then **SYNC → SYNCHRONIZE**.
- Click into the app to see the live resource tree:
  `Application → Namespace / ConfigMap / Service / Deployment → ReplicaSet → Pods`.
- Wait for the app to show **Healthy** (green) and **Synced**.

---

## 6. View the nginx page

Port-forward the app's Service and open it:

```bash
kubectl port-forward svc/nginx-demo -n nginx-demo 8081:80
```

Open **http://localhost:8081** — you'll see the custom
"🚀 Deployed with ArgoCD" page from the ConfigMap.

---

## 7. See GitOps in action (optional but fun)

1. Edit the HTML inside `manifests/configmap.yaml` (change the heading text).
2. Commit and push:
   ```bash
   git commit -am "update landing page"
   git push
   ```
3. In the ArgoCD UI the app flips to **OutOfSync**. With auto-sync it reconciles
   automatically (or click **SYNC**).
4. Restart the pods to pick up the changed ConfigMap, then refresh the browser:
   ```bash
   kubectl rollout restart deployment/nginx-demo -n nginx-demo
   ```

> ConfigMap changes aren't hot-reloaded into running pods, so the
> `rollout restart` re-mounts the updated file. (For automatic reloads, tools
> like Reloader or a checksum annotation can be added later.)

---

## 8. Clean up

**From the UI:** open the app → **DELETE** → type `nginx-demo` to confirm.
This removes all synced resources (including the namespace).

**Or from the CLI:**

```bash
kubectl delete -f application.yaml    # if you used the declarative Application
# or just delete the namespace:
kubectl delete namespace nginx-demo
```

---

## Alternative: declarative install (skip the UI)

If you'd rather not click through the UI, edit `application.yaml` (set your
`repoURL`) and apply it:

```bash
kubectl apply -f application.yaml
```

ArgoCD picks it up and syncs the same manifests.

---

## How the pieces fit together

| File | Kind | Purpose |
|------|------|---------|
| `namespace.yaml` | Namespace | Isolates the demo in `nginx-demo` |
| `configmap.yaml` | ConfigMap | Holds the custom `index.html` |
| `deployment.yaml` | Deployment | Runs `nginx:1.27-alpine`, mounts the ConfigMap at `/usr/share/nginx/html` |
| `service.yaml` | Service | Exposes the pods on port 80 (ClusterIP) |
| `application.yaml` | ArgoCD Application | Tells ArgoCD which repo/path to sync (optional — the UI does the same) |

The key trick: the ConfigMap is mounted as the nginx web root, so the stock
image serves your page with **no custom image build required**.
