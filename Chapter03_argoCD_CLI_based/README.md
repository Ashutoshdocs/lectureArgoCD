# Nginx on ArgoCD — CLI Deployment Demo

Deploy an **nginx** app that serves a custom `index.html` to Kubernetes using
**ArgoCD**, driven entirely from the **`argocd` command line** (GitOps style).

The page is served from a Kubernetes **ConfigMap** mounted into the stock
`nginx` image — so there is **no Docker image to build or push**.

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Path in repo:** `Chapter03_argoCD_CLI_based/manifests`

---

## 📁 Layout (inside this repo)

```
Chapter03_argoCD_CLI_based/
├── README.md
├── application.yaml          # optional: kubectl-apply alternative
└── manifests/                # what ArgoCD syncs
    ├── namespace.yaml
    ├── configmap.yaml        # the custom index.html
    ├── deployment.yaml       # nginx Deployment (2 replicas)
    └── service.yaml          # ClusterIP Service on port 80
```

---

## ✅ Prerequisites

- A running Kubernetes cluster + `kubectl` configured.
- **ArgoCD installed** in the cluster (step 1).
- **`argocd` CLI installed** (step 2).
- These files pushed to your repo under `Chapter03_argoCD_CLI_based/` (step 3).

---

## 1. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd
```

## 2. Install the `argocd` CLI

```bash
# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd && rm argocd

# macOS
brew install argocd
```

Verify: `argocd version --client`

## 3. Push this demo to your repo

```bash
git clone https://github.com/Ashutoshdocs/lectureArgoCD.git
cd lectureArgoCD

# copy the Chapter03_argoCD_CLI_based folder in here, then:
git add Chapter03_argoCD_CLI_based
git commit -m "Chapter03: nginx argocd CLI demo"
git push origin main
```

---

## 4. Log in to ArgoCD from the CLI

Port-forward the API server (leave this running in one terminal):

```bash
kubectl get svc -n argocd argocd-server
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'
kubectl get svc -n argocd argocd-server
```

Get the admin password and log in (new terminal):

```bash
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

argocd login localhost:8080 --username admin --password "$PASS" --insecure
```

> `--insecure` accepts ArgoCD's self-signed cert on localhost.

---

## 5. (Public repo — skip) Register a private repo

The demo repo is public, so ArgoCD can read it with no credentials. **Skip this
step** unless your fork is private:

```bash
argocd repo add https://github.com/Ashutoshdocs/lectureArgoCD.git \
  --username <git-user> --password <git-token>
```

---

## 6. Create the Application via CLI  ⭐

This is the core step — creating the app from the command line:

```bash
argocd app create cli_nginx-demo \
  --repo https://github.com/Ashutoshdocs/lectureArgoCD.git \
  --path Chapter03_argoCD_CLI_based/manifests \
  --revision HEAD \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace cli_nginx-demo \
  --sync-option CreateNamespace=true \
  --sync-policy automated \
  --auto-prune \
  --self-heal
```

Inspect what was created:

```bash
argocd app get nginx-demo
argocd app list
```

---

## 7. Sync and watch it deploy

With `--sync-policy automated` it syncs on its own. To trigger and watch it:

```bash
argocd app sync nginx-demo
argocd app wait nginx-demo --health --timeout 180
```

`argocd app get nginx-demo` should show every resource **Synced / Healthy**.
Cross-check with kubectl:

```bash
kubectl get all -n nginx-demo
```

---

## 8. View the nginx page

```bash
use nodeport service
```

Open **http://localhost:nodeportip** — the custom "🚀 Deployed with ArgoCD CLI" page.

---

## 9. GitOps in action (optional)

```bash
# edit the heading in Chapter03_argoCD_CLI_based/manifests/configmap.yaml
git commit -am "update landing page"
git push

argocd app sync nginx-demo                       # or wait for auto-sync
kubectl rollout restart deployment/nginx-demo -n nginx-demo   # re-mount ConfigMap
```

Refresh the browser to see the change.

> ConfigMap updates aren't hot-reloaded into running pods, so `rollout restart`
> re-mounts the new file.

---

## 10. Clean up

```bash
argocd app delete nginx-demo --cascade           # removes all synced resources
# or:
kubectl delete namespace nginx-demo
```

---

## Alternative: one-shot declarative apply

Skip `argocd app create` entirely — `application.yaml` already points at your
repo and path:

```bash
kubectl apply -f Chapter03_argoCD_CLI_based/application.yaml
```

---

## Handy CLI reference

| Command | What it does |
|---------|--------------|
| `argocd app list` | List all applications |
| `argocd app get nginx-demo` | Status + resource tree |
| `argocd app sync nginx-demo` | Force a sync now |
| `argocd app wait nginx-demo --health` | Block until Healthy |
| `argocd app history nginx-demo` | Sync/deploy history |
| `argocd app rollback nginx-demo <id>` | Roll back to a revision |
| `argocd app logs nginx-demo` | Tail app pod logs |
| `argocd app delete nginx-demo --cascade` | Delete app + resources |

**The key trick:** the ConfigMap is mounted as nginx's web root
(`/usr/share/nginx/html`), so the stock image serves your page with **no custom
image build required**.
