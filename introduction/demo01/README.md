# Argo CD Basic GitOps Demo

This practical demonstrates the basic working of **Argo CD** using a Kubernetes cluster and a Git repository.

The demo proves:

```text
Developer
    |
    | git push
    v
Git Repository
    |
    | Argo CD watches Git
    v
Argo CD
    |
    | Sync / Reconcile
    v
Kubernetes Cluster
    |
    v
Nginx Pods
```

---

# 1. Objective

By the end of this demo, you will understand:

* What Argo CD is
* What GitOps means
* How Argo CD connects Git and Kubernetes
* How to create an Argo CD Application
* How Argo CD deploys Kubernetes manifests
* How Git changes are synchronized to Kubernetes
* What `Synced` and `OutOfSync` mean
* How `selfHeal` works
* How `prune` works

---

# 2. Prerequisites

You need:

* A running Kubernetes cluster
* `kubectl`
* Git
* A GitHub repository

Verify Kubernetes:

```bash
kubectl get nodes
```

Example:

```text
NAME           STATUS   ROLES           AGE
controlplane   Ready    control-plane   10d
worker         Ready    <none>          10d
```

Verify Git:

```bash
git --version
```

---

# 3. Architecture

```text
                    GitHub
                 ┌───────────┐
                 │           │
                 │ deployment│
                 │ service   │
                 │           │
                 └─────┬─────┘
                       |
                       | Git
                       v
                ┌──────────────┐
                │   Argo CD    │
                │              │
                │ Application  │
                └──────┬───────┘
                       |
                       | Sync
                       v
              ┌──────────────────┐
              │ Kubernetes       │
              │                  │
              │ Namespace        │
              │ nginx-demo       │
              │                  │
              │ Deployment       │
              │       |          │
              │       v          │
              │   Nginx Pods     │
              │                  │
              │ Service          │
              └──────────────────┘
```

---

# 4. Install Argo CD

Create the Argo CD namespace:

```bash
kubectl create namespace argocd
```

Install Argo CD:

```bash
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Check the pods:

```bash
kubectl get pods -n argocd
```

Watch until the pods become `Running`:

```bash
kubectl get pods -n argocd -w
```

---

# 5. Access Argo CD UI

For this lab, use port-forwarding:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open:

```text
https://localhost:8080
```

You may receive a certificate warning because this is a lab setup.

---

# 6. Get Argo CD Admin Password

Run:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Copy the password.

Login:

```text
Username: admin
Password: <password>
```

---

# 7. Create Git Repository

Create a GitHub repository:

```text
argocd-basic-demo
```

Clone it:

```bash
git clone https://github.com/YOUR-USERNAME/argocd-basic-demo.git
```

Enter the repository:

```bash
cd argocd-basic-demo
```

Repository structure:

```text
argocd-basic-demo/
│
├── deployment.yaml
└── service.yaml
```

---

# 8. Create Kubernetes Deployment

Create:

```text
deployment.yaml
```

Content:

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
```

---

# 9. Create Kubernetes Service

Create:

```text
service.yaml
```

Content:

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

# 10. Push Manifests to Git

Check the files:

```bash
ls
```

Expected:

```text
deployment.yaml
service.yaml
```

Add the files:

```bash
git add .
```

Commit:

```bash
git commit -m "Initial nginx deployment"
```

Push:

```bash
git push
```

---

# 11. Important GitOps Concept

Normally we could deploy the application manually:

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

But **do not do this for this demo**.

Instead:

```text
Git
 |
 v
Argo CD
 |
 v
Kubernetes
```

Argo CD will deploy the application.

---

# 12. Create Argo CD Application

Create:

```text
argocd-app.yaml
```

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
    path: .

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

Replace:

```text
YOUR-USERNAME
```

with your GitHub username.

---

# 13. Apply Argo CD Application

Run:

```bash
kubectl apply -f argocd-app.yaml
```

Check:

```bash
kubectl get application -n argocd
```

Expected:

```text
NAME         SYNC STATUS   HEALTH STATUS
nginx-demo   Synced        Healthy
```

---

# 14. Verify Kubernetes

Check the namespace:

```bash
kubectl get all -n nginx-demo
```

You should see:

```text
NAME                               READY
pod/nginx-demo-xxxxxxxxxx-xxxxx    1/1
pod/nginx-demo-xxxxxxxxxx-xxxxx    1/1

NAME                  TYPE       PORT
service/nginx-demo    NodePort   80:30080/TCP

NAME                          READY
deployment.apps/nginx-demo    2/2
```

---

# 15. Check Argo CD UI

Open:

```text
https://localhost:8080
```

You should see:

```text
Application: nginx-demo

SYNC STATUS:   Synced
HEALTH STATUS: Healthy
```

The application tree should show:

```text
nginx-demo
│
├── Service
│
└── Deployment
      │
      ├── Pod
      └── Pod
```

---

# 16. Demo 1 — Change Replicas Through Git

Initially:

```yaml
replicas: 2
```

Change it to:

```yaml
replicas: 5
```

Commit:

```bash
git add deployment.yaml
git commit -m "Scale nginx to 5 replicas"
```

Push:

```bash
git push
```

Now check:

```bash
kubectl get deployment -n nginx-demo
```

Eventually:

```text
NAME         READY   UP-TO-DATE   AVAILABLE
nginx-demo   5/5     5            5
```

Check pods:

```bash
kubectl get pods -n nginx-demo
```

You should have five pods.

---

# 17. What Happened?

You changed:

```text
Git
replicas: 2
      |
      | git push
      v
replicas: 5
```

Argo CD detected the change:

```text
Git desired state
       |
       v
replicas = 5
       |
       v
Argo CD
       |
       v
Kubernetes
       |
       v
5 Pods
```

This is GitOps.

---

# 18. Demo 2 — Prove Self-Healing

Git currently says:

```yaml
replicas: 5
```

Now manually change Kubernetes:

```bash
kubectl scale deployment nginx-demo \
  --replicas=1 \
  -n nginx-demo
```

Check:

```bash
kubectl get deployment -n nginx-demo
```

You may temporarily see:

```text
NAME         READY
nginx-demo   1/1
```

But Argo CD has:

```yaml
selfHeal: true
```

Therefore Argo CD compares:

```text
Git:

replicas = 5


Kubernetes:

replicas = 1
```

Argo CD detects drift:

```text
DRIFT DETECTED
      |
      v
Argo CD
      |
      v
Restore desired state
      |
      v
replicas = 5
```

Check again:

```bash
kubectl get deployment -n nginx-demo
```

Eventually:

```text
NAME         READY
nginx-demo   5/5
```

---

# 19. Demo 3 — Delete a Resource

Delete the service manually:

```bash
kubectl delete service nginx-demo -n nginx-demo
```

Check:

```bash
kubectl get svc -n nginx-demo
```

Argo CD detects that the Service is missing.

Because:

```yaml
selfHeal: true
```

is enabled, Argo CD reconciles the cluster back to Git.

Check:

```bash
kubectl get svc -n nginx-demo
```

The Service should be recreated.

---

# 20. Demo 4 — Prune

`prune: true` means Argo CD can remove Kubernetes resources that are no longer defined in Git.

For example, suppose Git contains:

```text
deployment.yaml
service.yaml
```

Now delete:

```text
service.yaml
```

from Git.

Then:

```bash
git add .
git commit -m "Remove service"
git push
```

Argo CD sees:

```text
Git:
Deployment

Kubernetes:
Deployment
Service
```

The Service exists in Kubernetes but not in Git.

Because:

```yaml
prune: true
```

Argo CD removes the Service.

---

# 21. Important Argo CD Status

## Synced

```text
Git desired state
       =
Kubernetes state
```

Everything matches.

---

## OutOfSync

```text
Git desired state
       !=
Kubernetes state
```

There is drift.

Example:

```text
Git:
replicas = 5

Kubernetes:
replicas = 2
```

Argo CD reports:

```text
OutOfSync
```

---

## Healthy

The Kubernetes resources are functioning correctly.

Example:

```text
Deployment: Healthy
Pods: Running
```

---

## Degraded

A resource is not healthy.

Example:

```text
ImagePullBackOff
CrashLoopBackOff
Unavailable replicas
```

---

# 22. Key Argo CD Application Fields

The most important part of the Application YAML is:

```yaml
source:
  repoURL: https://github.com/YOUR-USERNAME/argocd-basic-demo.git
  targetRevision: HEAD
  path: .
```

Meaning:

```text
repoURL
   ↓
Which Git repository?

targetRevision
   ↓
Which Git revision/branch?

path
   ↓
Where are the Kubernetes manifests?
```

Destination:

```yaml
destination:
  server: https://kubernetes.default.svc
  namespace: nginx-demo
```

Meaning:

```text
Which Kubernetes cluster?
        +
Which namespace?
```

---

# 23. Sync Policy

We used:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

Meaning:

```text
automated
    |
    └── Automatically synchronize Git changes

prune
    |
    └── Remove resources deleted from Git

selfHeal
    |
    └── Correct manual changes made directly
        to Kubernetes
```

---

# 24. GitOps vs Traditional Deployment

## Traditional

```text
Developer
    |
    v
Git
    |
    v
CI/CD Pipeline
    |
    v
kubectl apply
    |
    v
Kubernetes
```

The pipeline actively pushes changes.

---

## GitOps with Argo CD

```text
Developer
    |
    v
Git
    |
    v
Argo CD
    |
    | continuously compares
    |
    v
Kubernetes
```

Argo CD continuously reconciles the desired state.

---

# 25. Useful Commands

Check Argo CD pods:

```bash
kubectl get pods -n argocd
```

Check Argo CD services:

```bash
kubectl get svc -n argocd
```

Check applications:

```bash
kubectl get applications -n argocd
```

Describe application:

```bash
kubectl describe application nginx-demo -n argocd
```

Check deployed resources:

```bash
kubectl get all -n nginx-demo
```

Check deployment:

```bash
kubectl get deployment -n nginx-demo
```

Check pods:

```bash
kubectl get pods -n nginx-demo
```

Watch pods:

```bash
kubectl get pods -n nginx-demo -w
```

---

# 26. Complete Demo Flow

Use this sequence while teaching:

```text
1. Install Argo CD
        |
        v
2. Create Git repository
        |
        v
3. Add deployment.yaml
        |
        v
4. Add service.yaml
        |
        v
5. Push to Git
        |
        v
6. Create Argo CD Application
        |
        v
7. Argo CD reads Git
        |
        v
8. Argo CD deploys to Kubernetes
        |
        v
9. Verify Pods
        |
        v
10. Change replicas 2 → 5 in Git
        |
        v
11. Argo CD automatically syncs
        |
        v
12. Manually scale 5 → 1
        |
        v
13. Argo CD self-heals back to 5
```

---

# 27. Final Concept

The most important concept to remember:

```text
                 SOURCE OF TRUTH
                       |
                       v
                     GIT
                       |
                       v
                  ARGO CD
                       |
                       v
                  KUBERNETES
```

**Git contains the desired state.**

**Argo CD continuously works to make Kubernetes match that desired state.**

Therefore:

```text
Git = Desired State

Kubernetes = Current State

Argo CD = Reconciliation Engine
```

That is the fundamental idea behind **GitOps with Argo CD**.
