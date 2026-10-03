# Argo CD Demo: Automation, Pruning, Self-Healing

A hands-on demo of a fully automated GitOps workflow with Argo CD. It covers three features:

| Feature | What it does | Default |
|---|---|---|
| **Automated Sync** | Argo CD applies changes from Git to the cluster on its own, without a manual "Sync" click | Off |
| **Pruning** | Resources deleted from Git are also deleted from the cluster | Off, even with automated sync |
| **Self-Healing** | Manual changes made directly in the cluster (drift) are reverted to match Git | Off |

---

## Repo layout

```
argocd-autosync-demo/
├── README.md
├── argocd/
│   ├── application-manual.yaml     # Baseline: manual sync only
│   └── application-automated.yaml  # Automated sync + prune + selfHeal
└── manifests/
    ├── namespace.yaml
    ├── deployment.yaml
    ├── service.yaml
    └── configmap.yaml              # Deleted from Git later to demo pruning
```

---

## Prerequisites

- A Kubernetes cluster (kind, minikube, k3d, or a cloud cluster)
- `kubectl` and the `argocd` CLI
- This folder pushed to your own **Git repo** (GitHub, GitLab, etc.), because Argo CD watches Git

### 1. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait until the pods are ready
kubectl get pods -n argocd -w
```

### 2. Access the UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Initial admin password
argocd admin initial-password -n argocd

argocd login localhost:8080 --username admin --insecure
```

Open https://localhost:8080.

### 3. Point the Application at your repo

In both files under `argocd/`, replace:

```yaml
repoURL: https://github.com/<your-user>/argocd-autosync-demo.git
```

Commit and push.

---

## Part 0: Baseline (manual sync)

```bash
kubectl apply -f argocd/application-manual.yaml
```

The app shows **OutOfSync**. Nothing is deployed until you sync it:

```bash
argocd app sync demo-app
```

Now change `replicas` in `manifests/deployment.yaml` and push. The app goes **OutOfSync** again and waits for you. This is the problem automation solves.

Remove it before continuing:

```bash
argocd app delete demo-app --yes
```

---

## Part 1: Automated Sync

```bash
kubectl apply -f argocd/application-automated.yaml
```

The key section:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

**Try it:**

1. Change `replicas: 2` to `replicas: 4` in `manifests/deployment.yaml`.
2. Commit and push.
3. Watch Argo CD apply it with no manual step:

```bash
kubectl get pods -n gitops-demo -w
```

> Argo CD polls Git every **3 minutes** by default. To see it immediately, click **Refresh** in the UI or run `argocd app get demo-app --refresh`. In production, use a Git webhook.

**Safety features of automated sync:**
- It syncs only when the app is OutOfSync, and it won't retry the same failed commit repeatedly.
- It won't delete every resource if the Git path suddenly becomes empty, unless `allowEmpty: true` is set.
- Rollback is disabled for automated apps; roll back by reverting the commit in Git.

---

## Part 2: Pruning

Without `prune: true`, deleting a file from Git leaves the resource running in the cluster (the app shows it as needing pruning).

**Try it:**

1. Confirm the ConfigMap exists:
   ```bash
   kubectl get configmap demo-config -n gitops-demo
   ```
2. Delete `manifests/configmap.yaml` from the repo, then commit and push.
3. After the next sync, it is gone from the cluster:
   ```bash
   kubectl get configmap demo-config -n gitops-demo
   # Error from server (NotFound)
   ```

**Protecting one resource from pruning:** add this annotation to it:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
```

---

## Part 3: Self-Healing

Git is the source of truth. With `selfHeal: true`, any change made directly in the cluster is reverted.

**Try it: manual scaling**

```bash
kubectl scale deployment demo-web -n gitops-demo --replicas=10
kubectl get deployment demo-web -n gitops-demo -w
```

Within seconds the replica count returns to the value in Git.

**Try it: delete a resource**

```bash
kubectl delete service demo-web -n gitops-demo
kubectl get service -n gitops-demo -w
```

Argo CD recreates the Service.

**Try it: edit the image**

```bash
kubectl set image deployment/demo-web nginx=nginx:1.25 -n gitops-demo
```

It is reverted to the image defined in Git.

> Self-heal runs shortly after drift is detected (about 5 seconds by default, set by `--self-heal-timeout-seconds` on the application controller).

**Compare:** set `selfHeal: false`, push, and repeat the scale test. The app shows **OutOfSync** but the drift stays until the next Git change or manual sync.

---

## Summary

| Action | Automated only | + prune | + selfHeal |
|---|---|---|---|
| Change pushed to Git | Applied | Applied | Applied |
| File deleted from Git | Resource stays | Resource deleted | Resource deleted |
| `kubectl` change in cluster | Drift stays | Drift stays | Reverted |

---

## Cleanup

```bash
argocd app delete demo-app --yes
kubectl delete namespace gitops-demo
kubectl delete namespace argocd
```
