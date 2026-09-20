# Chapter 5: Multi-Cluster ArgoCD (Dev · QA · Prod)

Run **one ArgoCD** and deploy the **same app to three separate clusters** —
`dev`, `qa`, and `prod` — each on its own single-node VM. Every environment gets
its own **colourful page** so you can tell them apart at a glance:

| Env | Colour | App | Page |
|-----|--------|-----|------|
| dev | 🟢 green | `nginx-dev` | "🌱 Dev Cluster" |
| qa | 🟠 amber | `nginx-qa` | "🧪 QA Cluster" |
| prod | 🔴 red | `nginx-prod` | "🚀 Prod Cluster" |

- **Repo:** `https://github.com/Ashutoshdocs/lectureArgoCD.git`
- **Base path:** `Chapter05_multicluster_argocd`

---

## 🧭 Architecture

```
                         ┌───────────────────────────┐
                         │ DEV VM (kubeadm, 1 node)   │
                         │   ArgoCD runs HERE         │  ← management cluster
                         │   + nginx-dev (green) 🟢    │
                         └─────────────┬─────────────┘
                                       │  ArgoCD manages remote clusters
                     ┌─────────────────┼─────────────────┐
                     ▼                                   ▼
        ┌───────────────────────┐          ┌───────────────────────┐
        │ QA VM (kubeadm,1 node)│          │PROD VM (kubeadm,1 node)│
        │  nginx-qa (amber) 🟠   │          │ nginx-prod (red) 🔴    │
        └───────────────────────┘          └───────────────────────┘

  One Git repo  ──►  three Application manifests  ──►  three destination clusters
```

ArgoCD lives on **one** cluster (we'll use the **dev** VM as the "management"
cluster) and pushes to the other two over the network. Dev is therefore the
**in-cluster** target (`https://kubernetes.default.svc`); qa and prod are
**remote** clusters you register with `argocd cluster add`.

---

## 📁 Files

```
Chapter05_multicluster_argocd/
├── README.md
├── apps/
│   ├── dev/   { configmap.yaml, deployment.yaml, service.yaml }   # green page
│   ├── qa/    { configmap.yaml, deployment.yaml, service.yaml }   # amber page
│   └── prod/  { configmap.yaml, deployment.yaml, service.yaml }   # red page
└── applications/
    ├── nginx-dev.yaml    # dest: in-cluster (dev)
    ├── nginx-qa.yaml     # dest: QA cluster URL
    └── nginx-prod.yaml   # dest: PROD cluster URL
```

Each app is stock `nginx:1.27-alpine` serving a custom page from a ConfigMap
(no image to build) and exposed via **NodePort 30080** — open it at
`http://<that-vm-ip>:30080`.

---

## ✅ Prerequisites

- **3 VMs**, each running a **single-node `kubeadm` cluster** (dev, qa, prod).
- `kubectl` and the **`argocd` CLI** on your workstation (or the dev VM).
- Network reachability: the **dev/ArgoCD** cluster must be able to reach the **qa**
  and **prod** API servers (port `6443`) — use the VMs' reachable IPs, **not**
  `127.0.0.1` or `https://kubernetes.default.svc` for the remote ones.
- This chapter pushed to your Git repo.

> **kubeadm notes (important):**
> - The admin kubeconfig lives at **`/etc/kubernetes/admin.conf`** on each VM, and
>   its `server:` is already `https://<VM_IP>:6443` — usually no IP fix needed
>   (just confirm the dev VM can reach that IP).
> - kubeadm names **every** context `kubernetes-admin@kubernetes`, so you must
>   rename them before merging (step 1).
> - kubeadm **taints the control-plane node** `NoSchedule`. On a single-node
>   cluster you must remove that taint or pods stay `Pending` (step 0).

---

## 0. Prep each single-node kubeadm cluster (remove control-plane taint)

Run on **each** VM (dev, qa, prod) so workloads can schedule on the single node:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
kubectl taint nodes --all node-role.kubernetes.io/master-        2>/dev/null || true
kubectl get nodes            # STATUS should be Ready
```

> If the API server certificate doesn't already include the IP you'll register
> with, add it as a SAN. Normally kubeadm includes the node IP automatically; only
> if you hit an `x509` error, re-init with
> `kubeadm init --apiserver-cert-extra-sans <VM_IP>` (or add it to the kubeadm
> config) so the cert is valid for that address.

---

## 1. Collect kubeconfig contexts for all three clusters

On your workstation, gather a kubeconfig that has a **context per cluster**.
kubeadm stores the admin kubeconfig at `/etc/kubernetes/admin.conf`:

```bash
# Copy each VM's admin kubeconfig:
scp user@DEV_VM:/etc/kubernetes/admin.conf  dev.yaml
scp user@QA_VM:/etc/kubernetes/admin.conf   qa.yaml
scp user@PROD_VM:/etc/kubernetes/admin.conf prod.yaml

# Confirm each server: is a reachable IP (kubeadm usually sets the node IP already):
grep server: dev.yaml qa.yaml prod.yaml
#   → https://DEV_VM_IP:6443 / https://QA_VM_IP:6443 / https://PROD_VM_IP:6443
#   If any shows an IP the dev VM can't reach, edit it to a reachable one.

# kubeadm names every context the same → rename each to a unique name:
KUBECONFIG=dev.yaml  kubectl config rename-context kubernetes-admin@kubernetes dev
KUBECONFIG=qa.yaml   kubectl config rename-context kubernetes-admin@kubernetes qa
KUBECONFIG=prod.yaml kubectl config rename-context kubernetes-admin@kubernetes prod

# Merge into one kubeconfig:
KUBECONFIG=dev.yaml:qa.yaml:prod.yaml kubectl config view --flatten > ~/.kube/config

kubectl config get-contexts        # you should see dev, qa, prod
```

---

## 2. Install ArgoCD on the DEV (management) cluster

```bash
kubectl config use-context dev
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

Log in with the CLI (port-forward in one terminal):

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --username admin --password "$PASS" --insecure
```

---

## 3. Register the QA and PROD clusters ⭐

This is the heart of multi-cluster. `argocd cluster add` creates a service
account + token on the target cluster and stores its credentials in ArgoCD.

```bash
# Names are the CONTEXT names from step 1
argocd cluster add qa
argocd cluster add prod

# Verify — copy the SERVER URLs shown here:
argocd cluster list
```

Example output:
```
SERVER                          NAME        STATUS
https://kubernetes.default.svc  in-cluster  Successful   # dev (local)
https://QA_VM_IP:6443           qa          Successful
https://PROD_VM_IP:6443         prod        Successful
```

---

## 4. Fill in the destination URLs

Edit the two remote Application manifests with the URLs from `argocd cluster list`:

- `applications/nginx-qa.yaml`   → `destination.server: https://QA_VM_IP:6443`
- `applications/nginx-prod.yaml` → `destination.server: https://PROD_VM_IP:6443`

`applications/nginx-dev.yaml` already targets `https://kubernetes.default.svc`
(the dev/in-cluster). Commit & push your edits:

```bash
git add Chapter05_multicluster_argocd
git commit -m "Chapter05: multicluster dev/qa/prod"
git push origin main
```

---

## 5. Deploy all three Applications

From the dev/management context:

```bash
kubectl apply -f Chapter05_multicluster_argocd/applications/nginx-dev.yaml
kubectl apply -f Chapter05_multicluster_argocd/applications/nginx-qa.yaml
kubectl apply -f Chapter05_multicluster_argocd/applications/nginx-prod.yaml

argocd app list          # all three should reach Synced / Healthy
```

In the ArgoCD UI each app shows its **destination cluster** — one repo fanning
out to three clusters.

---

## 6. Open each environment 🎨

Each app is a NodePort on `30080` on its own VM:

```bash
curl http://DEV_VM_IP:30080     # 🌱 green  Dev page
curl http://QA_VM_IP:30080      # 🧪 amber  QA page
curl http://PROD_VM_IP:30080    # 🚀 red    Prod page
```

Open the three IPs in a browser to see the colour-coded pages side by side.

> If NodePort isn't reachable (firewall/cloud SG), open TCP `30080` on each VM,
> or use `kubectl --context <env> -n default port-forward svc/nginx-<env> 8080:80`.

---

## 7. See GitOps across clusters (optional)

Edit a page in Git — e.g. change the heading in `apps/qa/configmap.yaml` — commit
and push. Only **qa** goes OutOfSync and re-syncs (auto), because only its
Application watches that path. Refresh after a ConfigMap reload:

```bash
kubectl --context qa -n default rollout restart deploy/nginx-qa
```

This shows **environment isolation**: each cluster promotes independently from
the same repo.

---

## Mapping to your original manifests

| Your example | Here |
|--------------|------|
| `nginx-dev` → `path: ui_approach/nginx`, dest `kubernetes.default.svc` | `nginx-dev` → `apps/dev`, dest in-cluster |
| `apache-stg` → dest `<argocd-cluster-server-url>` | `nginx-qa` → `apps/qa`, dest QA URL |
| `online-shop-prod` → dest `<prod-cluster-server-url>` | `nginx-prod` → `apps/prod`, dest PROD URL |

Same idea: **one Application per environment, each with a different
`destination.server`**. Point them at your real cluster URLs from
`argocd cluster list`.

---

## 🧰 Troubleshooting

- **Pods stuck `Pending` on a fresh kubeadm cluster** — the control-plane taint
  wasn't removed. Re-run step 0's `kubectl taint … -` on that VM.
- **`argocd cluster add` fails / token error** — your kubeconfig context can't
  reach that VM's API server. Confirm `grep server:` shows a reachable IP and that
  port `6443` is open between the dev VM and the target.
- **Both remote contexts look identical** — you skipped the kubeadm
  `rename-context` step; every kubeadm context is `kubernetes-admin@kubernetes`.
  Rename before merging (step 1).
- **App stuck `Unknown`/`ComparisonError`** — destination URL doesn't match a
  registered cluster exactly. Re-copy it from `argocd cluster list`.
- **Page not reachable** — NodePort `30080` blocked by firewall/security group;
  open it, or use port-forward.
- **`x509`/TLS to remote API** — the VM's API cert doesn't list the IP you
  registered. Re-init kubeadm with `--apiserver-cert-extra-sans <VM_IP>`, or
  register via a hostname/IP the cert already covers.

## 🧹 Cleanup

```bash
kubectl delete -f Chapter05_multicluster_argocd/applications/
argocd cluster rm https://QA_VM_IP:6443
argocd cluster rm https://PROD_VM_IP:6443
```

---

### One-line recap for students
> One ArgoCD, one Git repo, **three Applications** — each with a different
> `destination.server`. Register remote clusters with `argocd cluster add`, then
> each environment deploys to its own cluster.

Happy Learning!
