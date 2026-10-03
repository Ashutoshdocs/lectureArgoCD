# Argo CD Demo: Propagation Policies

A hands-on demo of how Kubernetes orders resource deletion, and how Argo CD uses the same policies when it prunes resources or deletes an Application.

When you delete an **owner** (a Deployment), the **propagation policy** decides what happens to its **dependents** (the ReplicaSet and Pods, linked by `ownerReferences`):

```
Deployment ──owns──▶ ReplicaSet ──owns──▶ Pod, Pod, Pod
```

| Policy | What happens | Owner gone | Dependents |
|---|---|---|---|
| **Foreground** | The owner enters a "deletion in progress" state (`deletionTimestamp` + `foregroundDeletion` finalizer). The garbage collector deletes all dependents first, then the owner. | **Last** | Deleted first |
| **Background** (Kubernetes default) | The owner is deleted immediately. The garbage collector cleans up the dependents afterwards. | **First** | Deleted afterwards |
| **Orphan** | The owner is deleted, and its dependents are left running with no owner. | Immediately | **Kept (orphaned)** |

> **Watch out for the defaults.** `kubectl delete` defaults to **background**. Argo CD defaults to **foreground**, both when pruning (`PrunePropagationPolicy`) and when deleting an app (`argocd app delete`).

---

## Repo layout

```
argocd-propagation-demo/
├── README.md
├── manifests/
│   ├── deployment.yaml        # Deployment -> ReplicaSet -> 3 Pods (slow shutdown so you can see the order)
│   └── configmap.yaml         # Stays in Git so the app path is never empty
├── argocd/
│   ├── app-foreground.yaml    # PrunePropagationPolicy=foreground -> namespace demo-foreground
│   ├── app-background.yaml    # PrunePropagationPolicy=background -> namespace demo-background
│   └── app-orphan.yaml        # PrunePropagationPolicy=orphan     -> namespace demo-orphan
└── scripts/
    ├── watch.sh               # Live view of owners, deletion state and finalizers
    ├── kubectl-demo.sh        # Deploy + delete with a chosen --cascade policy
    └── cleanup.sh
```

The pods have a 15-second `preStop` sleep, so each deletion takes about 15 seconds and you can follow the order.

---

## Prerequisites

- A Kubernetes cluster (kind, minikube, k3d, or a cloud cluster)
- `kubectl` and the `argocd` CLI
- Argo CD installed (only needed for Parts 3 and 4):

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd admin initial-password -n argocd
argocd login localhost:8080 --username admin --insecure
```

- For Parts 3 and 4, push this folder to your own Git repo and replace `repoURL` in the three files under `argocd/`:

```yaml
repoURL: https://github.com/<your-user>/argocd-propagation-demo.git
```

Run all commands from the repo root.

---

## Part 1: The owner chain

```bash
kubectl create namespace demo-kubectl
kubectl apply -n demo-kubectl -f manifests/deployment.yaml
kubectl rollout status deployment/demo-web -n demo-kubectl
```

Open a **second terminal** and keep it running for Part 2:

```bash
./scripts/watch.sh demo-kubectl
```

```
KIND         NAME                        OWNER                  DELETING-SINCE   FINALIZERS
Deployment   demo-web                    <none>                 <none>           <none>
ReplicaSet   demo-web-7c9d8f6b5          demo-web               <none>           <none>
Pod          demo-web-7c9d8f6b5-abcde    demo-web-7c9d8f6b5     <none>           <none>
...
```

The `OWNER` column comes from `metadata.ownerReferences`, which is how the garbage collector knows what to delete.

---

## Part 2: The three policies with plain kubectl

Each run redeploys the app, then deletes the Deployment with the chosen policy. Keep watching the second terminal.

### Foreground

```bash
./scripts/kubectl-demo.sh foreground
```

What you see:
1. The Deployment **stays**, with `DELETING-SINCE` set and finalizer `[foregroundDeletion]`.
2. The ReplicaSet does the same, and the Pods terminate.
3. Only after all Pods are gone do the ReplicaSet and then the Deployment disappear.

### Background (default)

```bash
./scripts/kubectl-demo.sh background
```

What you see:
1. The Deployment **disappears immediately**.
2. The ReplicaSet and Pods are still there briefly, then the garbage collector removes them.

### Orphan

```bash
./scripts/kubectl-demo.sh orphan
```

What you see:
1. The Deployment disappears.
2. The ReplicaSet and all 3 Pods **keep running**. The ReplicaSet's `OWNER` is now `<none>`.

```bash
kubectl get rs -n demo-kubectl -o jsonpath='{.items[0].metadata.ownerReferences}'
# (empty)
```

> **Adoption:** if you apply the same Deployment again, it **adopts** the orphaned ReplicaSet (same selector and pod template) instead of creating new Pods. Try `kubectl apply -n demo-kubectl -f manifests/deployment.yaml` and check the `OWNER` column again.

Clean up before continuing:

```bash
kubectl delete namespace demo-kubectl
```

---

## Part 3: Argo CD pruning with `PrunePropagationPolicy`

When `prune: true` removes a resource that was deleted from Git, Argo CD deletes it using the policy set in the sync option:

```yaml
syncPolicy:
  automated:
    prune: true
  syncOptions:
    - PrunePropagationPolicy=foreground   # or background | orphan (default: foreground)
```

The three Applications deploy the **same manifests** into three namespaces, so you can compare them side by side.

```bash
kubectl apply -f argocd/
argocd app list
```

Open three terminals:

```bash
./scripts/watch.sh demo-foreground
./scripts/watch.sh demo-background
./scripts/watch.sh demo-orphan
```

**Trigger a prune:** delete the Deployment from Git.

```bash
git rm manifests/deployment.yaml
git commit -m "Remove demo-web to demo pruning"
git push

# Don't wait for the 3-minute poll:
for P in foreground background orphan; do argocd app get demo-$P --refresh >/dev/null; done
```

| Namespace | Result |
|---|---|
| `demo-foreground` | Pods go first; the Deployment is the last to disappear |
| `demo-background` | The Deployment disappears at once; the ReplicaSet and Pods follow |
| `demo-orphan` | The Deployment is gone, but **the ReplicaSet and Pods keep running** |

In the `demo-orphan` app, the leftover ReplicaSet is not tracked by Argo CD, because it was never in Git and its owner is gone. It's now a manual cleanup job:

```bash
kubectl get rs,pods -n demo-orphan
kubectl delete rs -n demo-orphan -l app=demo-web
```

Restore the Deployment before Part 4:

```bash
git revert --no-edit HEAD
git push
```

---

## Part 4: Deleting the Application itself

Deleting an **Application** is another owner-and-dependents situation. Whether its resources are removed is controlled by a **finalizer** on the Application:

| Finalizer on the Application | What `argocd app delete` / `kubectl delete app` does |
|---|---|
| `resources-finalizer.argocd.argoproj.io` | Cascade delete, **foreground** |
| `resources-finalizer.argocd.argoproj.io/background` | Cascade delete, **background** |
| *(no finalizer)* | Only the Application is deleted; resources are **orphaned** |

All three demo apps use the foreground finalizer. With the CLI, you can choose the behaviour per delete:

```bash
# Foreground cascade (the CLI default)
argocd app delete demo-foreground --yes

# Background cascade
argocd app delete demo-background --propagation-policy background --yes

# Non-cascading: remove the Application, keep everything it deployed
argocd app delete demo-orphan --cascade=false --yes
```

Check the result:

```bash
kubectl get deploy,rs,pods -n demo-foreground   # gone
kubectl get deploy,rs,pods -n demo-background   # gone
kubectl get deploy,rs,pods -n demo-orphan       # still running
```

> **Tip:** non-cascading delete is the safe way to move an app to another Argo CD Application, or to stop managing it with Argo CD, without downtime. Create the new Application pointing at the same resources and it takes them over.

> **Stuck deleting?** If an Application hangs in "Deleting", a resource under it usually can't be deleted, or the controller can't reach the cluster. Check `argocd app get <app>` for the blocking resource. Removing the finalizer (`kubectl patch app <app> -n argocd --type merge -p '{"metadata":{"finalizers":null}}'`) forces removal, but it orphans whatever is left.

---

## Summary

| | Foreground | Background | Orphan |
|---|---|---|---|
| Deletion order | Dependents first, then owner | Owner first, then dependents | Owner only |
| Owner visible while deleting | Yes (`foregroundDeletion` finalizer) | No | No |
| Dependents kept | No | No | **Yes** |
| `kubectl delete` | `--cascade=foreground` | `--cascade=background` (default) | `--cascade=orphan` |
| Argo CD prune | `PrunePropagationPolicy=foreground` (default) | `PrunePropagationPolicy=background` | `PrunePropagationPolicy=orphan` |
| Argo CD app delete | `resources-finalizer.argocd.argoproj.io` / CLI default | `.../background` finalizer / `--propagation-policy background` | No finalizer / `--cascade=false` |

**When to use which:**
- **Foreground** when order matters and you need to know everything is gone before the owner is (for example, before recreating it).
- **Background** for fast deletes where order doesn't matter.
- **Orphan** to keep workloads running while you replace or hand over the owner.

---

## Cleanup

```bash
./scripts/cleanup.sh
kubectl delete namespace argocd   # if you also want to remove Argo CD
```
