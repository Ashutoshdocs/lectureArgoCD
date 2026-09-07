# Kubernetes Deployment Strategies with ArgoCD — Browser-Provable Demos

Four self-contained demos, one folder each, that let you *see* each deployment
strategy happen live in a web browser. Every demo exposes a **NodePort**
service, so no ingress or load balancer is required.

| Strategy | Folder | NodePort | What you'll observe in the browser |
|---|---|---|---|
| Rolling Update | [`rolling-update/`](rolling-update/) | `30081` | Mix of v1 & v2 during rollout, then all v2. No downtime. |
| Recreate (Downtime) | [`recreate-downtime/`](recreate-downtime/) | `30082` | App goes unreachable for a few seconds, then all v2. |
| Blue-Green | [`blue-green/`](blue-green/) | `30083` | Instant cutover from v1 to v2, never a mix. |
| Stable-Canary | [`stable-canary/`](stable-canary/) | `30084` | ~80% v1 / ~20% v2, shift the ratio to promote v2. |

All demos use Google's tiny sample web app **`gcr.io/google-samples/hello-app`**,
which renders a page like this in the browser:

```
Hello, world!
Version: 1.0.0
Hostname: rolling-demo-6b9f...-abcde
```

- **Version** tells you which release served the request (`1.0.0` = v1, `2.0.0` = v2).
- **Hostname** is the pod name, so you can tell pods apart.

> If `gcr.io/google-samples/hello-app` ever fails to pull, replace it everywhere
> with `us-docker.pkg.dev/google-samples/containers/gke/hello-app` (same `:1.0` / `:2.0` tags).

---

## Prerequisites (do this once)

You need a Kubernetes cluster, `kubectl`, ArgoCD, and a Git repo you control.

### 1. A cluster with reachable NodePorts

**minikube (recommended, easiest NodePort access):**
```bash
minikube start
```

**kind** works too, but NodePorts are only reachable if you map them at
cluster-creation time. See each folder's README note, or just use
`kubectl port-forward` as a fallback (shown in every folder README).

### 2. Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
```

Open the ArgoCD UI (optional but nice for watching syncs):
```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# then open https://localhost:8080
# username: admin
# password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

### 3. Put this project in YOUR Git repo

ArgoCD pulls manifests from Git, so the files must live in a repo it can read.

```bash
# from the folder that CONTAINS deployment-strategies-demo/
git init
git add .
git commit -m "deployment strategy demos"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

Then edit the `application.yaml` in each folder and set:
- `repoURL:` to your repo URL
- `path:` if your folder layout differs (default assumes the repo root contains
  the `deployment-strategies-demo/` folder)

---

## How to run any demo

Each folder is independent. The pattern is always the same:

```bash
cd <strategy-folder>
kubectl apply -f application.yaml         # register the app with ArgoCD
# ArgoCD auto-syncs the manifests/ folder into the target namespace
```

Then open the NodePort URL and follow that folder's README to trigger and
watch the strategy. Start here:

1. [`rolling-update/README.md`](rolling-update/README.md)
2. [`recreate-downtime/README.md`](recreate-downtime/README.md)
3. [`blue-green/README.md`](blue-green/README.md)
4. [`stable-canary/README.md`](stable-canary/README.md)

---

## Getting the browser URL (all strategies)

**minikube:**
```bash
minikube service <service-name> -n <namespace> --url
# open the printed URL in your browser
```

**Any cluster (direct NodePort):**
```bash
kubectl get nodes -o wide            # note a node's INTERNAL/EXTERNAL IP
# open http://<node-ip>:<nodeport>
```

**Fallback that always works (port-forward):**
```bash
kubectl -n <namespace> port-forward svc/<service-name> 8088:80
# open http://localhost:8088
```

To watch traffic split without clicking refresh, run a quick loop in a terminal:
```bash
URL="http://<node-ip>:<nodeport>"
while true; do curl -s $URL | grep -E 'Version|Hostname'; echo '---'; sleep 0.5; done
```

---

## Clean up everything
```bash
kubectl delete -f rolling-update/application.yaml
kubectl delete -f recreate-downtime/application.yaml
kubectl delete -f blue-green/application.yaml
kubectl delete -f stable-canary/application.yaml
# ArgoCD prunes the workloads; then remove leftover namespaces if any:
kubectl delete ns rolling-update recreate-downtime blue-green stable-canary --ignore-not-found
```

---

## Why the ArgoCD `Application` lives outside `manifests/`

In every folder, `application.yaml` is a sibling of `manifests/`, not inside it.
ArgoCD is told to sync only the `manifests/` subfolder, so it never tries to
manage its own `Application` object. You apply `application.yaml` yourself once
with `kubectl apply -f application.yaml`.
